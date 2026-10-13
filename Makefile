# Every command an engineer or an agent needs. CI runs the same commands.

CORE        := Packages/PianismCore
SWIFT_DIRS  := Packages

.PHONY: help test test-core lint format clean

help: ## List the available commands
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

test: test-core ## Run every automated test

test-core: ## Unit-test the platform-independent core (fast, no simulator)
	swift test --package-path $(CORE) -Xswiftc -warnings-as-errors

lint: ## Check formatting without changing files
	swift format lint --strict --recursive --parallel $(SWIFT_DIRS)

format: ## Format all Swift sources in place
	swift format --in-place --recursive --parallel $(SWIFT_DIRS)

clean: ## Remove build output
	rm -rf build $(CORE)/.build
