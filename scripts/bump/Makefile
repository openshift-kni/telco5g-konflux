# Bump Scripts Makefile
# ======================
# This Makefile provides a target to bump the minor version across the project.

SCRIPT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# Project root (defaults to repository root)
PROJECT_ROOT ?= $(shell git rev-parse --show-toplevel 2>/dev/null || realpath $(SCRIPT_DIR)/../..)

# Example:
#   make bump-minor CURRENT_VERSION=4.21.0
.PHONY: bump-minor
bump-minor: ## Bump minor version across the project (use CURRENT_VERSION=4.21.0)
	@if [ -z "$(CURRENT_VERSION)" ]; then \
		echo "Error: CURRENT_VERSION is required (e.g., 4.21.0)"; \
		exit 1; \
	fi
	@echo "Bumping minor version from $(CURRENT_VERSION) in $(PROJECT_ROOT)"
	$(SCRIPT_DIR)/konflux-bump-minor.sh --current-version "$(CURRENT_VERSION)" --project-root "$(PROJECT_ROOT)"

.PHONY: help
help: ## Display available targets
	@echo "Bump Scripts"
	@echo "============"
	@echo ""
	@echo "This Makefile provides a target for bumping the minor version across the project."
	@echo ""
	@echo "Variables:"
	@echo "  CURRENT_VERSION   Current version to bump from (e.g., 4.21.0)"
	@echo "  PROJECT_ROOT      Project root directory (default: repo root)"
	@echo ""
	@echo "Examples:"
	@echo "  make bump-minor CURRENT_VERSION=4.21.0"
	@echo "  make bump-minor CURRENT_VERSION=4.21.0 PROJECT_ROOT=/path/to/project"
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(SCRIPT_DIR)/Makefile


