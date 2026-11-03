# Every command an engineer or an agent needs. CI runs these same targets.

PROJECT     := Pianism.xcodeproj
SCHEME      := Pianism
CORE        := Packages/PianismCore
FEATURES    := Packages/PianismFeatures
ADAPTERS    := Packages/PianismPersistence Packages/PianismSystem Packages/PianismMIDI
SWIFT_DIRS  := App AppUITests Widgets Packages scripts
RESULTS     := build/results
# Xcode 26 compiles package dependencies with -suppress-warnings, which clashes with the packages'
# own .treatAllWarnings(as: .error). Turning suppression off keeps warnings visible, and fatal, everywhere.
# CI sets QUIET= to keep xcodebuild's full output in the job log.
QUIET       ?= -quiet
XCODE_FLAGS := SWIFT_SUPPRESS_WARNINGS=NO $(QUIET)
# Fails a build or test on any compiler warning, including the few warnings-as-errors misses (#24).
NO_WARNINGS := scripts/fail-on-warnings.sh
DEVICES     ?= iPhone iPad
# The iOS version to test on, such as 26 or 27.0; empty means the newest installed.
IOS         ?=

.PHONY: help test test-core test-features test-adapters test-app build evidence lint unused mutate format clean

help: ## List the available commands
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

test: test-core test-features test-adapters test-app ## Run every automated test

test-core: ## Unit-test the platform-independent core (fast, no simulator)
	$(NO_WARNINGS) swift test --package-path $(CORE)

test-features: ## Unit-test the screens' view models on the Mac (seconds, no simulator)
	$(NO_WARNINGS) swift test --package-path $(FEATURES)

test-adapters: ## Integration-test the adapter packages, which need Apple-only APIs (macOS, no simulator)
	@for package in $(ADAPTERS); do $(NO_WARNINGS) swift test --package-path $$package || exit 1; done

build: ## Build the app as it ships (Release) for the simulator; the tests build Debug
	$(NO_WARNINGS) xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=iOS Simulator' \
		$(XCODE_FLAGS)
	@app="$$(xcodebuild -showBuildSettings -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=iOS Simulator' 2>/dev/null | awk '$$1 == "CODESIGNING_FOLDER_PATH" {print $$3}')"; \
		plutil -lint -s "$$app/PrivacyInfo.xcprivacy" || { echo "The app has no valid privacy manifest (NFR-2)."; exit 1; }

# Builds once, then tests each device without rebuilding. One simulator at a time, each shut down
# after its tests: two booted simulators overload an 8 GB Mac, and iOS's launch watchdog then kills apps.
# A failed test runs once more and passes if the retry does: on CI's slow runners, UI tests flake.
# The test runner Xcode generates gets the audio background mode, which CoreMIDI requires of a process
# that makes a virtual source (`testAPianoTheSystemAnnouncesIsHeard`; without it, kMIDINotPermitted). No
# build setting reaches the runner's own Info.plist, and the simulator runs the edited bundle (its signature no
# longer verifies, which the simulator doesn't check). Added after every build, as a rebuild may write the plist
# afresh, and skipped when it's there.
# A failure skips xcodebuild's diagnostics (sysdiagnoses, log archives): on CI's iOS 27 runners,
# collecting them ran past the job's time limit and lost the result bundle. UITestCase still attaches
# each failure's screen and UI tree.
# The app is installed before the simulator boots for the tests: on a fresh iOS 27 simulator, an app
# installed while the system's notification service is still starting up never gets registered with it,
# so the system drops every notification the app schedules until the next boot.
# XCTDisableSpindump: when a launch isn't confirmed in time, which happens now and then on a freshly booted
# iOS 27 simulator, XCTest spends about 100 s taking a whole-machine spindump before failing the test.
# The retry passes, and the spindump has never helped, so it's skipped (#136).
# Without a limit, a launch that never returns ran until the CI job's hour was up (#136), so every test gets
# 15 minutes: the longest takes under 3, and the warm-up before the first (#153) can take 13. A test that
# runs out isn't retried, and XCTest's spindump of it, which XCTDisableSpindump doesn't skip, adds 2 minutes.
test-app: ## Build the app once, then run its end-to-end tests on each simulator in DEVICES (default: iPhone iPad), on iOS IOS (such as 27.0; default: newest)
	$(NO_WARNINGS) xcodebuild build-for-testing -project $(PROJECT) -scheme $(SCHEME) \
		-destination "$$(scripts/simulator-destination.sh $(firstword $(DEVICES)) $(IOS))" $(XCODE_FLAGS)
	@app="$$(xcodebuild -showBuildSettings -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'generic/platform=iOS Simulator' 2>/dev/null | awk '$$1 == "CODESIGNING_FOLDER_PATH" {print $$3}')"; \
	runner="$$(dirname "$$app")/PianismUITests-Runner.app/Info.plist"; \
	plutil -p "$$runner" | grep -q '"audio"' || plutil -insert UIBackgroundModes -string audio -append "$$runner" || exit 1; \
	for device in $(DEVICES); do \
		echo "== End-to-end tests on $$device"; \
		rm -rf $(RESULTS)/app-$$device.xcresult; \
		destination="$$(scripts/simulator-destination.sh $$device $(IOS))" || exit 1; \
		udid="$${destination##*id=}"; \
		xcrun simctl bootstatus "$$udid" -b >/dev/null && xcrun simctl install "$$udid" "$$app" && \
			xcrun simctl shutdown "$$udid" && xcrun simctl bootstatus "$$udid" -b >/dev/null && \
			xcrun simctl spawn "$$udid" defaults write -g XCTDisableSpindump -bool YES || exit 1; \
		xcodebuild test-without-building -project $(PROJECT) -scheme $(SCHEME) -destination "$$destination" \
			-resultBundlePath $(RESULTS)/app-$$device.xcresult -collect-test-diagnostics never \
			-retry-tests-on-failure -test-iterations 2 \
			-test-timeouts-enabled YES -default-test-execution-time-allowance 900 $(XCODE_FLAGS); \
		status=$$?; \
		xcrun simctl shutdown "$$udid"; \
		[ $$status -eq 0 ] || exit 1; \
	done

evidence: ## Export the screenshots the last test-app run captured, one folder per device
	rm -rf build/evidence
	@for device in $(DEVICES); do \
		if [ -d $(RESULTS)/app-$$device.xcresult ]; then \
			xcrun xcresulttool export attachments --path $(RESULTS)/app-$$device.xcresult \
				--output-path build/evidence/$$device >/dev/null; \
		fi; \
	done
	@find build/evidence -name '*.png'

lint: ## Check formatting without changing files
	swift format lint --strict --recursive --parallel $(SWIFT_DIRS)

unused: ## Fail on unused code in the app and the package code it builds (Periphery, pinned; ADR 0005)
	scripts/unused.sh

mutate: ## Plant one bug at a time in the core and adapters and report the ones no test catches (minutes)
	python3 scripts/mutate.py $(CORE) $(ADAPTERS)

format: ## Format all Swift sources in place
	swift format --in-place --recursive --parallel $(SWIFT_DIRS)

clean: ## Remove build output
	rm -rf build Packages/*/.build
