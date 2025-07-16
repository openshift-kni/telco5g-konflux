# RPM Lock Scripts Makefile
# ==========================
# This Makefile provides targets for running RPM repository filtering scripts.

SCRIPT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# Default repo file path - can be overridden
REPO_FILE ?= redhat.repo

.PHONY: filter-unused-repos
filter-unused-repos: ## Filter unused repositories from redhat.repo files (use REPO_FILE=path to specify file)
	@echo "Filtering unused repositories from $(REPO_FILE)..."
	$(SCRIPT_DIR)/konflux-filter-unused-repos.sh $(REPO_FILE) > $(REPO_FILE).tmp && mv $(REPO_FILE).tmp $(REPO_FILE)

.PHONY: help
help: ## Display available targets
	@echo "RPM Lock Scripts"
	@echo "==============="
	@echo ""
	@echo "This Makefile provides targets for filtering unused RPM repositories."
	@echo ""
	@echo "Variables:"
	@echo "  REPO_FILE     Path to redhat.repo file (default: redhat.repo)"
	@echo ""
	@echo "Examples:"
	@echo "  make filter-unused-repos                        # Use default redhat.repo"
	@echo "  make filter-unused-repos REPO_FILE=/path/to/file  # Use custom file"
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(SCRIPT_DIR)/Makefile
