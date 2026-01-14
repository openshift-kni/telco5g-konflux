# Bump Scripts Makefile
# ======================
# This Makefile provides targets to bump the minor version across the project.

SCRIPT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# Project root (defaults to repository root)
PROJECT_ROOT ?= $(shell git rev-parse --show-toplevel 2>/dev/null || realpath $(SCRIPT_DIR)/../..)

# Single exclude list: comma or space-separated entries (paths or extensions)
# Mix paths (relative/absolute) and extensions (use .ext, e.g., .gz)
EXCLUDE ?=
EXCLUDE_ARG := $(if $(strip $(EXCLUDE)),--exclude $(EXCLUDE),)

# Check for uncommitted changes before switching branches (default: true)
CHECK_UNCOMMITTED ?= true

# Compute new version from CURRENT_VERSION (X.Y.Z -> X.(Y+1))
define compute_new_version
$(shell echo "$(CURRENT_VERSION)" | sed -E 's/^([0-9]+)\.([0-9]+).*/\1.\2/' | awk -F. '{print $$1"."($$2+1)}')
endef

# Example:
#   make bump-minor CURRENT_VERSION=4.21.0
.PHONY: bump-minor
bump-minor: ## Bump minor version (only file replacements, no git operations)
	@if [ -z "$(CURRENT_VERSION)" ]; then \
		echo "Error: CURRENT_VERSION is required (e.g., 4.21.0)"; \
		exit 1; \
	fi
	@echo "Bumping minor version from $(CURRENT_VERSION) in $(PROJECT_ROOT)"
	$(SCRIPT_DIR)/konflux-bump-minor.sh --current-version "$(CURRENT_VERSION)" --project-root "$(PROJECT_ROOT)" $(EXCLUDE_ARG)

# Example:
#   make bump-minor-with-git CURRENT_VERSION=4.21.0
.PHONY: bump-minor-with-git
bump-minor-with-git: ## Bump minor version with full git workflow (fetch, branch, commit)
	@if [ -z "$(CURRENT_VERSION)" ]; then \
		echo "Error: CURRENT_VERSION is required (e.g., 4.21.0)"; \
		exit 1; \
	fi
	$(eval NEW_VERSION := $(call compute_new_version))
	$(eval BRANCH_NAME := bump-to-$(NEW_VERSION))
	@echo "==> Fetching latest changes from remote..."
	@git -C "$(PROJECT_ROOT)" fetch
	@if [ "$(CHECK_UNCOMMITTED)" = "true" ]; then \
		echo "==> Checking for uncommitted changes..."; \
		if ! git -C "$(PROJECT_ROOT)" diff --quiet || ! git -C "$(PROJECT_ROOT)" diff --cached --quiet; then \
			echo "Error: You have uncommitted changes. Please commit or stash them first."; \
			exit 1; \
		fi; \
	fi
	@echo "==> Checking out main branch..."
	@git -C "$(PROJECT_ROOT)" checkout main
	@echo "==> Pulling latest changes..."
	@git -C "$(PROJECT_ROOT)" pull
	@echo "==> Creating branch '$(BRANCH_NAME)'..."
	@if git -C "$(PROJECT_ROOT)" show-ref --verify --quiet "refs/heads/$(BRANCH_NAME)"; then \
		echo "Error: branch '$(BRANCH_NAME)' already exists"; \
		exit 1; \
	fi
	@git -C "$(PROJECT_ROOT)" checkout -b "$(BRANCH_NAME)"
	@echo "==> Bumping minor version from $(CURRENT_VERSION) to $(NEW_VERSION)..."
	$(SCRIPT_DIR)/konflux-bump-minor.sh --current-version "$(CURRENT_VERSION)" --project-root "$(PROJECT_ROOT)" $(EXCLUDE_ARG)
	@echo "==> Staging changes..."
	@git -C "$(PROJECT_ROOT)" add -A
	@if git -C "$(PROJECT_ROOT)" diff --cached --quiet; then \
		echo "Warning: No changes to commit"; \
	else \
		echo "==> Committing changes..."; \
		git -C "$(PROJECT_ROOT)" commit -m "[BRANCH-CUT] Bump to $(NEW_VERSION)"; \
		echo "==> Successfully created commit on branch '$(BRANCH_NAME)'"; \
	fi
	@echo "Version bump completed."

.PHONY: help
help: ## Display available targets
	@echo "Bump Scripts"
	@echo "============"
	@echo ""
	@echo "This Makefile provides targets for bumping the minor version across the project."
	@echo ""
	@echo "Variables:"
	@echo "  CURRENT_VERSION     Current version to bump from (e.g., 4.21.0)"
	@echo "  PROJECT_ROOT        Project root directory (default: repo root)"
	@echo "  EXCLUDE             Comma/space-separated: paths or extensions (use .ext, e.g., .gz)"
	@echo "  CHECK_UNCOMMITTED   Check for uncommitted changes before branching (default: true)"
	@echo ""
	@echo "Examples:"
	@echo "  make bump-minor CURRENT_VERSION=4.21.0"
	@echo "  make bump-minor-with-git CURRENT_VERSION=4.21.0"
	@echo "  make bump-minor-with-git CURRENT_VERSION=4.21.0 CHECK_UNCOMMITTED=false"
	@echo "  make bump-minor CURRENT_VERSION=4.21.0 PROJECT_ROOT=/path/to/project"
	@echo "  make bump-minor CURRENT_VERSION=4.21.0 EXCLUDE=\"docs/,README.md,.png,.gz\""
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(SCRIPT_DIR)/Makefile


