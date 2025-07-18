# Telco5G Konflux Linting Targets
# ================================
# This Makefile provides linting targets for shell scripts and YAML files.
# ================================

# venv python integration derived from https://venthur.de/2021-03-31-python-makefiles.html
export SHELL := /usr/bin/env bash

# Get the directory of this Makefile
export TELCO5G_KONFLUX_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# Host python is used to setup venv
export PY ?= python3
export TELCO5G_KONFLUX_VENV := $(TELCO5G_KONFLUX_DIR)/venv
export TELCO5G_KONFLUX_BIN := $(TELCO5G_KONFLUX_VENV)/bin

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail

.SHELLFLAGS = -ec

# The 'all' target is the default goal.
all: lint
	@echo "All linting and testing tasks completed successfully."

.PHONY: venv
venv: $(TELCO5G_KONFLUX_VENV)

# This rule creates the Python virtual environment if it doesn't exist
# or if the requirements file has been updated.
$(TELCO5G_KONFLUX_VENV): $(TELCO5G_KONFLUX_DIR)/requirements.txt
	$(PY) -m venv $(TELCO5G_KONFLUX_VENV)
	$(TELCO5G_KONFLUX_BIN)/pip install --upgrade -r $(TELCO5G_KONFLUX_DIR)/requirements.txt
	touch $(TELCO5G_KONFLUX_VENV)

# The 'lint' target runs all available linters.
.PHONY: lint
lint: yamllint shellcheck bashate ## Run all linters
	@echo "All linters passed."

# The 'yamllint' target depends on the virtual environment to ensure
# the linter is installed before being run.
.PHONY: yamllint
yamllint: venv
	cd $(TELCO5G_KONFLUX_DIR) && $(TELCO5G_KONFLUX_BIN)/yamllint -c $(TELCO5G_KONFLUX_DIR)/.yamllint.yaml .

# The 'shellcheck' target runs the shellcheck linter on all .sh files.
# It depends on the venv, assuming shellcheck-py is listed in requirements.txt.
# NOTE: shellcheck does not check for line length; it focuses on shell syntax and correctness.
.PHONY: shellcheck
shellcheck: venv
	cd $(TELCO5G_KONFLUX_DIR) && $(TELCO5G_KONFLUX_BIN)/shellcheck --severity=error $(shell find $(TELCO5G_KONFLUX_DIR) -path $(TELCO5G_KONFLUX_VENV) -prune -o -type f -name "*.sh" -size +0c -print)

# The 'bashate' target runs the bashate linter on all .sh files.
# It depends on the venv, assuming bashate is listed in requirements.txt.
# NOTE: bashate has a hardcoded 80-character limit that cannot be changed.
# The E006 error for long lines has been ignored.
.PHONY: bashate
bashate: venv
	cd $(TELCO5G_KONFLUX_DIR) && $(TELCO5G_KONFLUX_BIN)/bashate --ignore=E006 $(shell find $(TELCO5G_KONFLUX_DIR) -path $(TELCO5G_KONFLUX_VENV) -prune -o -type f -name "*.sh" -print)

# Helper function to run a specific test for a given operator and release.
define run-overlay-test-for-release
	cd $(TELCO5G_KONFLUX_DIR)/test/overlay && \
	debug_flag=""; \
	if [[ -n "$(DEBUG)" ]]; then \
		debug_flag="--debug"; \
	fi; \
	if [[ -n "$(TEST)" ]]; then \
		test_file="$(1)/$(2)/$(TEST)"; \
		if [[ -f "$$test_file" ]]; then \
			echo "Running specific test: $(TEST) for $(1) release: $(2)"; \
			if ! "$$test_file" $$debug_flag; then \
				exit 1; \
			fi; \
		else \
			echo "Error: Test file $$test_file not found"; \
			exit 1; \
		fi; \
	else \
		echo "Testing $(1) release: $(2)"; \
		./runner.sh "$(1)" "$(2)" $$debug_flag; \
	fi
endef

# Generic function to run tests for any operator and release 
# - The RELEASE variable (optional) is used to run tests for a specific release. If not set, all releases
#   for the operator are tested. 
# - The TEST variable (optional) is used to run a specific test file. If not set, all tests are run.
# - The DEBUG variable (optional) is used to enable verbose/debug output in the test scripts for easier troubleshooting.
define run-overlay-tests
	@echo "Running tests for $(1) operator..."
	@cd $(TELCO5G_KONFLUX_DIR)/test/overlay && \
	if [[ -n "$(RELEASE)" ]]; then \
		release_dir="$(1)/$(RELEASE)"; \
		if [[ -d "$$release_dir" ]]; then \
			$(call run-overlay-test-for-release,$(1),$(RELEASE)) \
		else \
			echo "Error: Release directory $$release_dir not found"; \
			exit 1; \
		fi; \
	else \
		if [[ -n "$(TEST)" ]]; then \
			echo "Running specific test $(TEST) for all releases of $(1)"; \
			test_found=false; \
			for release_dir in $(1)/4.*; do \
				if [[ -d "$$release_dir" ]]; then \
					release=$$(basename "$$release_dir"); \
					test_file="$$release_dir/$(TEST)"; \
					if [[ -f "$$test_file" ]]; then \
						test_found=true; \
						$(call run-overlay-test-for-release,$(1),$$release) \
					else \
						echo "Warning: Test file $(TEST) not found for release $$release"; \
					fi; \
				fi; \
			done; \
			if [[ "$$test_found" == "false" ]]; then \
				echo "Error: Test file $(TEST) not found in any release for operator $(1)"; \
				exit 1; \
			fi; \
		else \
			for release_dir in $(1)/4.*; do \
				if [[ -d "$$release_dir" ]]; then \
					release=$$(basename "$$release_dir"); \
					$(call run-overlay-test-for-release,$(1),$$release) \
				fi; \
			done; \
		fi; \
	fi
endef

# Test target for all operators
.PHONY: test-overlay
test-overlay: test-overlay-lca test-overlay-nrop test-overlay-ocloud test-overlay-talm ## Run all operator tests (use RELEASE=x.y for specific release, DEBUG=1 for verbose output)
	@echo "All operator tests completed."

# Test targets for individual operators
# Usage examples:
#   make test-overlay-<operator>                                      # Run all releases for operator 
#   make test-overlay-<operator> RELEASE=4.20                         # Run specific release for operator
#   make test-overlay-<operator> DEBUG=1                              # Run all releases for operator with verbose output
#   make test-overlay-<operator> RELEASE=4.20 DEBUG=1                 # Run specific release for operator with verbose output
#   make test-overlay-<operator> TEST=00.test.sh                      # Run a specific test file for all releases of operator
#   make test-overlay-<operator> TEST=00.test.sh RELEASE=4.20         # Run a specific test file for a specific release
#   make test-overlay-<operator> TEST=00.test.sh RELEASE=4.20 DEBUG=1 # Run a specific test file for a specific release with verbose output
.PHONY: test-overlay-lca
test-overlay-lca: ## Run tests for LCA operator (use RELEASE=x.y for specific release, DEBUG=1 for verbose output)
	$(call run-overlay-tests,lca)

.PHONY: test-overlay-nrop
test-overlay-nrop: ## Run tests for NROP operator (use RELEASE=x.y for specific release, DEBUG=1 for verbose output)
	$(call run-overlay-tests,nrop)

.PHONY: test-overlay-ocloud
test-overlay-ocloud: ## Run tests for OCLOUD operator (use RELEASE=x.y for specific release, DEBUG=1 for verbose output)
	$(call run-overlay-tests,ocloud)

.PHONY: test-overlay-talm
test-overlay-talm: ## Run tests for TALM operator (use RELEASE=x.y for specific release, DEBUG=1 for verbose output)
	$(call run-overlay-tests,talm)

# The 'clean' target removes generated artifacts like the virtual environment,
# the 'bin' directory for downloaded tools, and Python cache files.
.PHONY: clean
clean:
	rm -rf $(TELCO5G_KONFLUX_VENV)
	rm -rf $(TELCO5G_KONFLUX_DIR)/bin
	find $(TELCO5G_KONFLUX_DIR) -type f -name "*.pyc" -delete
	find $(TELCO5G_KONFLUX_DIR) -type d -name "__pycache__" -delete

.PHONY: help
help: ## Display this help message
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
