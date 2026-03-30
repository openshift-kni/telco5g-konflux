# Bundle Scripts Makefile
# =======================
# This Makefile provides targets for running bundle overlay scripts.

SCRIPT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# Default file paths - can be overridden
PINNING_FILE ?= pin_images.in.yaml
RELEASE_FILE ?= release.in.yaml
MAPPING_FILE ?= map_images.in.yaml
CSV_FILE ?= clusterserviceversion.yaml

# Mapping target (staging or production)
MAPPING_TARGET ?= staging

# Bundle image for validation (required for konflux-validate-bundle-labels-match-annotations-file target)
BUNDLE_IMAGE ?=

.PHONY: konflux-validate-bundle-labels-match-annotations-file
konflux-validate-bundle-labels-match-annotations-file: ## Validate bundle image labels match metadata/annotations.yaml (requires BUNDLE_IMAGE)
	@if [ -z "$(BUNDLE_IMAGE)" ]; then \
		echo "ERROR: BUNDLE_IMAGE is required. Usage: make konflux-validate-bundle-labels-match-annotations-file BUNDLE_IMAGE=<bundle-image>"; \
		exit 1; \
	fi
	$(SCRIPT_DIR)/konflux-validate-bundle-labels-match-annotations-file.sh "$(BUNDLE_IMAGE)"

.PHONY: bundle-overlay
bundle-overlay: ## Apply bundle overlay (basic: pinning + release)
	@echo "Applying bundle overlay..."
	@echo "  Release file: $(RELEASE_FILE)"
	@echo "  CSV file: $(CSV_FILE)"
	@if [ -f "$(PINNING_FILE)" ]; then \
		echo "  Pinning file: $(PINNING_FILE)"; \
		$(SCRIPT_DIR)/konflux-bundle-overlay.sh --set-release-file $(RELEASE_FILE) --set-csv-file $(CSV_FILE) --set-pinning-file $(PINNING_FILE); \
	else \
		echo "  No pinning file found, skipping image pinning"; \
		$(SCRIPT_DIR)/konflux-bundle-overlay.sh --set-release-file $(RELEASE_FILE) --set-csv-file $(CSV_FILE); \
	fi

.PHONY: bundle-overlay-with-mapping
bundle-overlay-with-mapping: ## Apply bundle overlay with registry mapping (use MAPPING_TARGET=staging|production)
	@echo "Applying bundle overlay with mapping..."
	@echo "  Release file: $(RELEASE_FILE)"
	@echo "  CSV file: $(CSV_FILE)"
	@echo "  Mapping file: $(MAPPING_FILE)"
	@echo "  Mapping target: $(MAPPING_TARGET)"
	@if [ -f "$(PINNING_FILE)" ]; then \
		echo "  Pinning file: $(PINNING_FILE)"; \
		if [ "$(MAPPING_TARGET)" = "staging" ]; then \
			$(SCRIPT_DIR)/konflux-bundle-overlay.sh --set-release-file $(RELEASE_FILE) --set-csv-file $(CSV_FILE) --set-pinning-file $(PINNING_FILE) --set-mapping-file $(MAPPING_FILE) --set-mapping-staging; \
		else \
			$(SCRIPT_DIR)/konflux-bundle-overlay.sh --set-release-file $(RELEASE_FILE) --set-csv-file $(CSV_FILE) --set-pinning-file $(PINNING_FILE) --set-mapping-file $(MAPPING_FILE) --set-mapping-production; \
		fi; \
	else \
		echo "  No pinning file found, skipping image pinning"; \
		if [ "$(MAPPING_TARGET)" = "staging" ]; then \
			$(SCRIPT_DIR)/konflux-bundle-overlay.sh --set-release-file $(RELEASE_FILE) --set-csv-file $(CSV_FILE) --set-mapping-file $(MAPPING_FILE) --set-mapping-staging; \
		else \
			$(SCRIPT_DIR)/konflux-bundle-overlay.sh --set-release-file $(RELEASE_FILE) --set-csv-file $(CSV_FILE) --set-mapping-file $(MAPPING_FILE) --set-mapping-production; \
		fi; \
	fi

.PHONY: help
help: ## Display available targets
	@echo "Bundle Scripts"
	@echo "=============="
	@echo ""
	@echo "This Makefile provides targets for bundle overlay operations."
	@echo ""
	@echo "Variables:"
	@echo "  BUNDLE_IMAGE    Bundle image to validate (required for konflux-validate-bundle-labels-match-annotations-file)"
	@echo "  PINNING_FILE    Path to image pinning file (default: $(PINNING_FILE))"
	@echo "  RELEASE_FILE    Path to release configuration file (default: $(RELEASE_FILE))"
	@echo "  MAPPING_FILE    Path to registry mapping file (default: $(MAPPING_FILE))"
	@echo "  CSV_FILE        Path to CSV file (default: $(CSV_FILE))"
	@echo "  MAPPING_TARGET  Registry mapping target: staging|production (default: $(MAPPING_TARGET))"
	@echo ""
	@echo "Examples:"
	@echo "  make konflux-validate-bundle-labels-match-annotations-file BUNDLE_IMAGE=quay.io/example/bundle:latest"
	@echo "  make bundle-overlay                                      # Basic overlay with defaults"
	@echo "  make bundle-overlay-with-mapping MAPPING_TARGET=production  # Overlay with production mapping"
	@echo "  make bundle-overlay CSV_FILE=my-operator.csv             # Use custom CSV file"
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-25s %s\n", $$1, $$2}' $(SCRIPT_DIR)/Makefile
	@echo ""
	@echo "For detailed script help:"
	@echo "  $(SCRIPT_DIR)/konflux-bundle-overlay.sh --help"
	@echo "  $(SCRIPT_DIR)/konflux-validate-bundle-labels-match-annotations-file.sh <bundle-image>"
