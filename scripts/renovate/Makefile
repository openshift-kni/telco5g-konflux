# Renovate Scripts Makefile
# ==========================
# This Makefile provides targets for running Renovate scripts.

SCRIPT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# Default repo file path - can be overridden
RENOVATE_CONFIG_FILE ?= renovate.json

# Default version - can be overridden
# Mintmaker uses `latest` docker image internally so we also use `latest` by default
# In principle this could mean slight version mismatches but it will probably be fine
RENOVATE_VERSION ?= latest

# Format the file first, and then validate it, so that its easier to see any non-fatal warnings at the end
.PHONY: all
all: renovate-format-config-file renovate-validate-config-file

.PHONY: renovate-validate-config-file
renovate-validate-config-file: ## Validate the renovate.json file
	@echo "Validating the renovate.json file..."
	$(SCRIPT_DIR)/renovate-validate-config-file.sh $(RENOVATE_CONFIG_FILE) $(RENOVATE_VERSION)

.PHONY: renovate-format-config-file
renovate-format-config-file: ## Format the renovate.json file
	@echo "Formatting the renovate.json file..."
	$(SCRIPT_DIR)/renovate-format-config-file.sh $(RENOVATE_CONFIG_FILE)

.PHONY: help
help: ## Display available targets
	@echo "Renovate Scripts"
	@echo "==============="
	@echo ""
	@echo "This Makefile provides targets for running Renovate scripts."
	@echo ""
	@echo "Variables:"
	@echo "  RENOVATE_CONFIG_FILE     Path to renovate.json file (default: renovate.json)"
	@echo "  RENOVATE_VERSION         Version of renovate to use (default: latest)"
	@echo ""
	@echo "Examples:"
	@echo "  make renovate-validate-config-file                        # Use default renovate.json"
	@echo "  make renovate-validate-config-file RENOVATE_CONFIG_FILE=/path/to/file  # Use custom file"
	@echo "  make renovate-validate-config-file RENOVATE_VERSION=41.67.0  # Use custom version"
	@echo "  make renovate-format-config-file                        # Use default renovate.json"
	@echo "  make renovate-format-config-file RENOVATE_CONFIG_FILE=/path/to/file  # Use custom file"
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(SCRIPT_DIR)/Makefile
