# Tekton Scripts Makefile
# =======================
# This Makefile provides targets for running Tekton pipeline management scripts.

SCRIPT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# Default pipeline files - can be overridden
PIPELINE_FILES ?= .tekton/build-pipeline.yaml .tekton/fbc-pipeline.yaml

.PHONY: update-task-refs
update-task-refs: ## Update task references in pipeline files (use PIPELINE_FILES to specify files)
	@echo "Updating task references in pipeline files..."
	@echo "  Pipeline files: $(PIPELINE_FILES)"
	$(SCRIPT_DIR)/konflux-update-task-refs.sh $(PIPELINE_FILES)

.PHONY: help
help: ## Display available targets
	@echo "Tekton Scripts"
	@echo "=============="
	@echo ""
	@echo "This Makefile provides targets for Tekton pipeline management."
	@echo ""
	@echo "Variables:"
	@echo "  PIPELINE_FILES  Space-separated list of pipeline files (default: $(PIPELINE_FILES))"
	@echo ""
	@echo "Examples:"
	@echo "  make update-task-refs                                    # Use default pipeline files"
	@echo "  make update-task-refs PIPELINE_FILES=\"file1.yaml file2.yaml\"  # Use custom files"
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(SCRIPT_DIR)/Makefile
