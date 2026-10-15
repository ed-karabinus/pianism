# Every command an engineer or an agent needs. CI runs these same targets.

PROJECT     := Pianism.xcodeproj
SCHEME      := Pianism
CORE        := Packages/PianismCore
ADAPTERS    := Packages/PianismPersistence
SWIFT_DIRS  := App AppUITests Packages
RESULTS     := build/results
# Xcode 26 compiles package dependencies with -suppress-warnings, which clashes with the packages'
# own .treatAllWarnings(as: .error). Turning suppression off keeps warnings visible, and fatal, everywhere.
# CI sets QUIET= to keep xcodebuild's full output in the job log.
QUIET       ?= -quiet
XCODE_FLAGS := SWIFT_SUPPRESS_WARNINGS=NO $(QUIET)
DEVICES     ?= iPhone iPad

.PHONY: help test test-core test-adapters test-app build evidence lint format clean

help: ## List the available commands
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

test: test-core test-adapters test-app ## Run every automated test

test-core: ## Unit-test the platform-independent core (fast, no simulator)
	swift test --package-path $(CORE)

test-adapters: ## Integration-test the adapter packages, which need Apple-only APIs (macOS, no simulator)
	@for package in $(ADAPTERS); do swift test --package-path $$package || exit 1; done

build: ## Build the app for the simulator
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
		-destination "$$(scripts/simulator-destination.sh)" \
		$(XCODE_FLAGS)

test-app: ## Build the app and run its end-to-end tests on each simulator in DEVICES (default: iPhone iPad)
	@for device in $(DEVICES); do \
		echo "== End-to-end tests on $$device"; \
		rm -rf $(RESULTS)/app-$$device.xcresult; \
		xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
			-destination "$$(scripts/simulator-destination.sh $$device)" \
			-resultBundlePath $(RESULTS)/app-$$device.xcresult \
			$(XCODE_FLAGS) || exit 1; \
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

format: ## Format all Swift sources in place
	swift format --in-place --recursive --parallel $(SWIFT_DIRS)

clean: ## Remove build output
	rm -rf build Packages/*/.build
