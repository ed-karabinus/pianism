# Every command an engineer or an agent needs. CI runs these same targets.

PROJECT     := Pianism.xcodeproj
SCHEME      := Pianism
CORE        := Packages/PianismCore
ADAPTERS    := Packages/PianismPersistence
SWIFT_DIRS  := App AppUITests Packages scripts
RESULTS     := build/results
# Xcode 26 compiles package dependencies with -suppress-warnings, which clashes with the packages'
# own .treatAllWarnings(as: .error). Turning suppression off keeps warnings visible, and fatal, everywhere.
# CI sets QUIET= to keep xcodebuild's full output in the job log.
QUIET       ?= -quiet
XCODE_FLAGS := SWIFT_SUPPRESS_WARNINGS=NO $(QUIET)
# Fails a build or test on any compiler warning, including the few warnings-as-errors misses (#24).
NO_WARNINGS := scripts/fail-on-warnings.sh
DEVICES     ?= iPhone iPad

.PHONY: help test test-core test-adapters test-app build evidence lint unused mutate format clean

help: ## List the available commands
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

test: test-core test-adapters test-app ## Run every automated test

test-core: ## Unit-test the platform-independent core (fast, no simulator)
	$(NO_WARNINGS) swift test --package-path $(CORE)

test-adapters: ## Integration-test the adapter packages, which need Apple-only APIs (macOS, no simulator)
	@for package in $(ADAPTERS); do $(NO_WARNINGS) swift test --package-path $$package || exit 1; done

build: ## Build the app as it ships (Release) for the simulator; the tests build Debug
	$(NO_WARNINGS) xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=iOS Simulator' \
		$(XCODE_FLAGS)

# Builds once, then tests each device without rebuilding. One simulator at a time, each shut down
# after its tests: two booted simulators overload an 8 GB Mac, and iOS's launch watchdog then kills apps.
test-app: ## Build the app once, then run its end-to-end tests on each simulator in DEVICES (default: iPhone iPad)
	$(NO_WARNINGS) xcodebuild build-for-testing -project $(PROJECT) -scheme $(SCHEME) \
		-destination "$$(scripts/simulator-destination.sh $(firstword $(DEVICES)))" $(XCODE_FLAGS)
	@for device in $(DEVICES); do \
		echo "== End-to-end tests on $$device"; \
		rm -rf $(RESULTS)/app-$$device.xcresult; \
		destination="$$(scripts/simulator-destination.sh $$device)" || exit 1; \
		udid="$${destination##*id=}"; \
		xcrun simctl bootstatus "$$udid" -b >/dev/null || exit 1; \
		xcodebuild test-without-building -project $(PROJECT) -scheme $(SCHEME) -destination "$$destination" \
			-resultBundlePath $(RESULTS)/app-$$device.xcresult $(XCODE_FLAGS); \
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
