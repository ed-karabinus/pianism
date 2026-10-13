# Every command an engineer or an agent needs. CI runs these same targets.

PROJECT     := Pianism.xcodeproj
SCHEME      := Pianism
CORE        := Packages/PianismCore
SWIFT_DIRS  := App AppUITests Packages
RESULTS     := build/results

.PHONY: help test test-core test-app build lint format clean

help: ## List the available commands
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

test: test-core test-app ## Run every automated test

test-core: ## Unit-test the platform-independent core (fast, no simulator)
	swift test --package-path $(CORE) -Xswiftc -warnings-as-errors

build: ## Build the app for the simulator
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
		-destination "$$(scripts/simulator-destination.sh)" \
		SWIFT_TREAT_WARNINGS_AS_ERRORS=YES -quiet

test-app: ## Build the app and run its end-to-end tests in the simulator
	rm -rf $(RESULTS)/app.xcresult
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
		-destination "$$(scripts/simulator-destination.sh)" \
		-resultBundlePath $(RESULTS)/app.xcresult \
		SWIFT_TREAT_WARNINGS_AS_ERRORS=YES -quiet

lint: ## Check formatting without changing files
	swift format lint --strict --recursive --parallel $(SWIFT_DIRS)

format: ## Format all Swift sources in place
	swift format --in-place --recursive --parallel $(SWIFT_DIRS)

clean: ## Remove build output
	rm -rf build $(CORE)/.build Packages/PianismFeatures/.build
