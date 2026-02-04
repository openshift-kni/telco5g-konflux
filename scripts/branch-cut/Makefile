# Branch Cut Scripts Makefile
# ===========================
# This Makefile provides targets for branch cut operations across the project.

SCRIPT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# Project root (defaults to repository root)
PROJECT_ROOT ?= $(shell git rev-parse --show-toplevel 2>/dev/null || realpath $(SCRIPT_DIR)/../..)

# Single exclude list: comma or space-separated entries (paths or extensions)
# Mix paths (relative/absolute) and extensions (use .ext, e.g., .gz)
EXCLUDE ?=
EXCLUDE_ARG := $(if $(strip $(EXCLUDE)),--exclude $(EXCLUDE),)

# Exclude variables: comma or space-separated variable names to skip during version replacement
# Example: RUNTIME_IMAGE,OPM_IMAGE
EXCLUDE_VARS ?=
EXCLUDE_VARS_ARG := $(if $(strip $(EXCLUDE_VARS)),--exclude-vars $(EXCLUDE_VARS),)

# Check for uncommitted changes before switching branches (default: true)
CHECK_UNCOMMITTED ?= true

# Compute new version from CURRENT_VERSION (X.Y.Z -> X.(Y+1))
define compute_new_version
$(shell echo "$(CURRENT_VERSION)" | sed -E 's/^([0-9]+)\.([0-9]+).*/\1.\2/' | awk -F. '{print $$1"."($$2+1)}')
endef

# Compute release branch name from CURRENT_VERSION (X.Y.Z -> release-X.Y)
define compute_release_branch
$(shell echo "$(CURRENT_VERSION)" | sed -E 's/^([0-9]+)\.([0-9]+).*/release-\1.\2/')
endef

# Example:
#   make branch-cut CURRENT_VERSION=4.21.0
.PHONY: branch-cut
branch-cut: ## Perform full branch cut (bump on main + prepare release branch)
	@if [ -z "$(CURRENT_VERSION)" ]; then \
		echo "Error: CURRENT_VERSION is required (e.g., 4.21.0)"; \
		exit 1; \
	fi
	$(eval NEW_VERSION := $(call compute_new_version))
	$(eval RELEASE_BRANCH := $(call compute_release_branch))
	@echo "Branch cut: $(CURRENT_VERSION) -> $(NEW_VERSION)"
	@echo "Release branch: $(RELEASE_BRANCH)"
	@echo ""
	$(SCRIPT_DIR)/konflux-branch-cut.sh --current-version "$(CURRENT_VERSION)" --project-root "$(PROJECT_ROOT)" $(EXCLUDE_ARG) $(EXCLUDE_VARS_ARG)

# Example:
#   make branch-cut-with-git CURRENT_VERSION=4.21.0
.PHONY: branch-cut-with-git
branch-cut-with-git: ## Perform full branch cut with git workflow (fetch, branch, commit on both branches)
	@if [ -z "$(CURRENT_VERSION)" ]; then \
		echo "Error: CURRENT_VERSION is required (e.g., 4.21.0)"; \
		exit 1; \
	fi
	$(eval NEW_VERSION := $(call compute_new_version))
	$(eval RELEASE_BRANCH := $(call compute_release_branch))
	$(eval BRANCH_NAME := branch-cut-to-$(NEW_VERSION))
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
	@echo ""
	@echo "==> Performing branch cut..."
	$(SCRIPT_DIR)/konflux-branch-cut.sh --current-version "$(CURRENT_VERSION)" --project-root "$(PROJECT_ROOT)" $(EXCLUDE_ARG) $(EXCLUDE_VARS_ARG)
	@echo ""
	@echo "==> Staging and committing changes on current branch..."
	@git -C "$(PROJECT_ROOT)" add -A
	@if git -C "$(PROJECT_ROOT)" diff --cached --quiet; then \
		echo "Warning: No changes to commit"; \
	else \
		git -C "$(PROJECT_ROOT)" commit -m "[BRANCH-CUT] Bump to $(NEW_VERSION) and prepare $(RELEASE_BRANCH)"; \
		echo "==> Successfully created commit"; \
	fi
	@echo ""
	@echo "Branch cut completed!"
	@echo "  - Version bumped: $(CURRENT_VERSION) -> $(NEW_VERSION)"
	@echo "  - Branches to push and create PRs:"
	@echo "    * $(BRANCH_NAME) -> PR to main"
	@echo "    * prepare-$(RELEASE_BRANCH) -> PR to $(RELEASE_BRANCH)"

.PHONY: help
help: ## Display available targets
	@echo "Branch Cut Scripts"
	@echo "=================="
	@echo ""
	@echo "This Makefile performs the complete branch cut workflow:"
	@echo "  1. On main: Bump version X.Y -> X.(Y+1) and rename Tekton pipelines"
	@echo "  2. Creates 'prepare-release-X.Y' branch from 'release-X.Y'"
	@echo "  3. On prepare-release-X.Y: Replace 'main' with 'release-X.Y' in YAML files"
	@echo ""
	@echo "PREREQUISITES:"
	@echo "  - The release branch (release-X.Y) MUST exist before running branch-cut"
	@echo ""
	@echo "BRANCHES CREATED:"
	@echo "  - branch-cut-to-X.(Y+1)  -> PR to main"
	@echo "  - prepare-release-X.Y   -> PR to release-X.Y"
	@echo ""
	@echo "Variables:"
	@echo "  CURRENT_VERSION     Current version to branch cut from (e.g., 4.21.0)"
	@echo "  PROJECT_ROOT        Project root directory (default: repo root)"
	@echo "  EXCLUDE             Comma/space-separated: paths or extensions (use .ext, e.g., .gz)"
	@echo "  EXCLUDE_VARS        Comma/space-separated: variable names to skip in replacements (e.g., RUNTIME_IMAGE,OPM_IMAGE)"
	@echo "  CHECK_UNCOMMITTED   Check for uncommitted changes before branching (default: true)"
	@echo ""
	@echo "Examples:"
	@echo "  make branch-cut CURRENT_VERSION=4.21.0"
	@echo "  make branch-cut-with-git CURRENT_VERSION=4.21.0"
	@echo "  make branch-cut CURRENT_VERSION=4.21.0 EXCLUDE=\"docs/,.png\""
	@echo "  make branch-cut CURRENT_VERSION=4.21.0 EXCLUDE_VARS=\"RUNTIME_IMAGE,OPM_IMAGE\""
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-25s %s\n", $$1, $$2}' $(SCRIPT_DIR)/Makefile
