# Catalog Scripts Makefile
# ========================
# This Makefile provides targets for running catalog management scripts.

SCRIPT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# Tool installation directory
TOOL_DIR ?= ./bin

# Container engine
ENGINE ?= docker

# Tool binaries
YQ ?= $(TOOL_DIR)/yq
OPM ?= $(TOOL_DIR)/opm
OPERATOR_SDK ?= $(TOOL_DIR)/operator-sdk

# Default file paths - can be overridden
CATALOG_TEMPLATE_FILE_INPUT ?= .konflux/catalog/catalog-template.in.yaml
CATALOG_TEMPLATE_FILE_OUTPUT ?= .konflux/catalog/catalog-template.out.yaml
BUNDLE_BUILDS_FILE ?= .konflux/catalog/bundle.builds.in.yaml
CATALOG_FILE ?= catalog.yaml

# Konflux-specific variables
CATALOG_TEMPLATE_KONFLUX_INPUT ?= $(CATALOG_TEMPLATE_FILE_INPUT)
CATALOG_TEMPLATE_KONFLUX_OUTPUT ?= $(CATALOG_TEMPLATE_FILE_OUTPUT)
CATALOG_KONFLUX ?= $(CATALOG_FILE)
PACKAGE_NAME_KONFLUX ?= telco5g-konflux

# For backwards compatibility, set the original targets to the input values
CATALOG_TEMPLATE_FILE ?= $(CATALOG_TEMPLATE_FILE_INPUT)
CATALOG_TEMPLATE_KONFLUX ?= $(CATALOG_TEMPLATE_KONFLUX_INPUT)

# Bundle image configuration - can be overridden for different operators
QUAY_TENANT_NAME ?= telco-5g-tenant
BUNDLE_NAME_SUFFIX ?= operator-bundle-4-20
PRODUCTION_NAMESPACE ?= openshift4
PRODUCTION_BUNDLE_NAME ?= operator-bundle

# Constructed bundle image names
QUAY_BUNDLE_IMAGE ?= quay.io/redhat-user-workloads/$(QUAY_TENANT_NAME)/$(PACKAGE_NAME_KONFLUX)-$(BUNDLE_NAME_SUFFIX)
PRODUCTION_BUNDLE_IMAGE ?= registry.redhat.io/$(PRODUCTION_NAMESPACE)/$(PACKAGE_NAME_KONFLUX)-$(PRODUCTION_BUNDLE_NAME)

# Tool versions for downloads
OPERATOR_SDK_VERSION ?= 1.40.0

# Catalog comparison configuration
UPSTREAM_FBC_IMAGE ?= quay.io/redhat-user-workloads/$(QUAY_TENANT_NAME)/$(PACKAGE_NAME_KONFLUX)-fbc-4-20:latest

# Download Makefile location
DOWNLOAD_MAKEFILE := $(SCRIPT_DIR)/../download/Makefile

.PHONY: yq
yq: ## Ensure yq is available
	@if [ ! -x "$(YQ)" ]; then \
		echo "Downloading yq..."; \
		$(MAKE) -f $(DOWNLOAD_MAKEFILE) download-yq DOWNLOAD_INSTALL_DIR=$(TOOL_DIR); \
	fi

.PHONY: opm
opm: ## Ensure opm is available
	@if [ ! -x "$(OPM)" ]; then \
		echo "Downloading opm..."; \
		$(MAKE) -f $(DOWNLOAD_MAKEFILE) download-opm DOWNLOAD_INSTALL_DIR=$(TOOL_DIR); \
	fi

.PHONY: operator-sdk
operator-sdk: ## Ensure operator-sdk is available
	@if [ ! -x "$(OPERATOR_SDK)" ]; then \
		echo "Downloading operator-sdk from GitHub releases..."; \
		$(MAKE) -f $(DOWNLOAD_MAKEFILE) download-operator-sdk DOWNLOAD_INSTALL_DIR=$(TOOL_DIR) DOWNLOAD_OPERATOR_SDK_VERSION=$(OPERATOR_SDK_VERSION); \
	fi

.PHONY: update-catalog-template
update-catalog-template: ## Update catalog template (use CATALOG_TEMPLATE_FILE and BUNDLE_BUILDS_FILE to specify files, or CATALOG_TEMPLATE_FILE_INPUT/OUTPUT for separate files)
	@echo "Updating catalog template..."
	echo "  Input template file: $(CATALOG_TEMPLATE_FILE_INPUT)" ;\
	echo "  Output template file: $(CATALOG_TEMPLATE_FILE_OUTPUT)" ;\
	echo "  Bundle builds file: $(BUNDLE_BUILDS_FILE)" ;\
	$(SCRIPT_DIR)/konflux-update-catalog-template.sh --set-catalog-template-input-file $(CATALOG_TEMPLATE_FILE_INPUT) --set-catalog-template-output-file $(CATALOG_TEMPLATE_FILE_OUTPUT) --set-bundle-builds-file $(BUNDLE_BUILDS_FILE) ;\

.PHONY: validate-production-images
validate-production-images: ## Validate related images for production (use CATALOG_FILE to specify file)
	@echo "Validating related images for production..."
	@echo "  Catalog file: $(CATALOG_FILE)"
	$(SCRIPT_DIR)/konflux-validate-related-images-production.sh --set-catalog-file $(CATALOG_FILE)

.PHONY: konflux-validate-catalog-template-bundle
konflux-validate-catalog-template-bundle: yq operator-sdk ## Validate the last bundle entry on the catalog template file
	@{ \
	set -e ;\
	echo "copying unmodified catalog template from $(CATALOG_TEMPLATE_KONFLUX_INPUT) to $(CATALOG_TEMPLATE_KONFLUX_OUTPUT)" ;\
	cp $(CATALOG_TEMPLATE_KONFLUX_INPUT) $(CATALOG_TEMPLATE_KONFLUX_OUTPUT) ;\
	echo "updating template data in $(CATALOG_TEMPLATE_KONFLUX_OUTPUT)"
	bundle=$$($(YQ) ".entries[-1].image" $(CATALOG_TEMPLATE_KONFLUX_OUTPUT)) ;\
	echo "validating the last bundle entry: $${bundle} on catalog template: $(CATALOG_TEMPLATE_KONFLUX_OUTPUT)" ;\
	$(OPERATOR_SDK) bundle validate --image-builder=$(ENGINE) $${bundle} ;\
	}

.PHONY: konflux-validate-catalog
konflux-validate-catalog: opm ## Validate the current catalog file
	@echo "validating catalog: $(dir $(CATALOG_KONFLUX))"
	$(OPM) validate $(dir $(CATALOG_KONFLUX))

.PHONY: konflux-generate-catalog
konflux-generate-catalog: yq opm ## Generate a quay.io catalog for OCP 4.17 and newer
	$(SCRIPT_DIR)/konflux-update-catalog-template.sh --set-catalog-template-input-file $(CATALOG_TEMPLATE_KONFLUX_INPUT) --set-catalog-template-output-file $(CATALOG_TEMPLATE_KONFLUX_OUTPUT) --set-bundle-builds-file $(BUNDLE_BUILDS_FILE)
	touch $(CATALOG_KONFLUX)
	$(OPM) alpha render-template basic --output yaml --migrate-level bundle-object-to-csv-metadata $(CATALOG_TEMPLATE_KONFLUX_OUTPUT) > $(CATALOG_KONFLUX)

.PHONY: konflux-generate-catalog-legacy
konflux-generate-catalog-legacy: yq opm ## Generate a quay.io catalog for OCP 4.16 and older
	$(SCRIPT_DIR)/konflux-update-catalog-template.sh --set-catalog-template-input-file $(CATALOG_TEMPLATE_KONFLUX_INPUT) --set-catalog-template-output-file $(CATALOG_TEMPLATE_KONFLUX_OUTPUT) --set-bundle-builds-file $(BUNDLE_BUILDS_FILE)
	touch $(CATALOG_KONFLUX)
	$(OPM) alpha render-template basic --output yaml $(CATALOG_TEMPLATE_KONFLUX_OUTPUT) > $(CATALOG_KONFLUX)

.PHONY: konflux-generate-catalog-production
konflux-generate-catalog-production: konflux-generate-catalog ## Generate a registry.redhat.io catalog for OCP 4.17 and newer
	@echo "Overlaying bundle image for production..."
	@echo "  From: $(QUAY_BUNDLE_IMAGE)"
	@echo "  To: $(PRODUCTION_BUNDLE_IMAGE)"
	# overlay the bundle image for production
	if [ "$$(uname)" = "Darwin" ]; then \
		sed -i '' 's|$(QUAY_BUNDLE_IMAGE)\(@sha256:[a-f0-9]*\)|$(PRODUCTION_BUNDLE_IMAGE)\1|g' $(CATALOG_KONFLUX); \
	else \
		sed -i 's|$(QUAY_BUNDLE_IMAGE)\(@sha256:[a-f0-9]*\)|$(PRODUCTION_BUNDLE_IMAGE)\1|g' $(CATALOG_KONFLUX); \
	fi
	# From now on, all the related images must reference production (registry.redhat.io) exclusively
	$(SCRIPT_DIR)/konflux-validate-related-images-production.sh --set-catalog-file $(CATALOG_KONFLUX)

.PHONY: konflux-generate-catalog-production-legacy
konflux-generate-catalog-production-legacy: konflux-generate-catalog-legacy ## Generate a registry.redhat.io catalog for OCP 4.16 and older
	@echo "Overlaying bundle image for production..."
	@echo "  From: $(QUAY_BUNDLE_IMAGE)"
	@echo "  To: $(PRODUCTION_BUNDLE_IMAGE)"
	# overlay the bundle image for production
	if [ "$$(uname)" = "Darwin" ]; then \
		sed -i '' 's|$(QUAY_BUNDLE_IMAGE)\(@sha256:[a-f0-9]*\)|$(PRODUCTION_BUNDLE_IMAGE)\1|g' $(CATALOG_KONFLUX); \
	else \
		sed -i 's|$(QUAY_BUNDLE_IMAGE)\(@sha256:[a-f0-9]*\)|$(PRODUCTION_BUNDLE_IMAGE)\1|g' $(CATALOG_KONFLUX); \
	fi
	# From now on, all the related images must reference production (registry.redhat.io) exclusively
	$(SCRIPT_DIR)/konflux-validate-related-images-production.sh --set-catalog-file $(CATALOG_KONFLUX)

.PHONY: konflux-compare-catalog
konflux-compare-catalog: ## Compare generated catalog with upstream FBC image
	$(SCRIPT_DIR)/konflux-compare-catalog.sh --catalog-path $(CATALOG_KONFLUX) --upstream-image $(UPSTREAM_FBC_IMAGE)

.PHONY: help
help: ## Display available targets
	@echo "Catalog Scripts"
	@echo "==============="
	@echo ""
	@echo "This Makefile provides targets for catalog management operations."
	@echo ""
	@echo "Variables:"
	@echo "  CATALOG_TEMPLATE_FILE_INPUT    Path to input catalog template file (default: $(CATALOG_TEMPLATE_FILE_INPUT))"
	@echo "  CATALOG_TEMPLATE_FILE_OUTPUT   Path to output catalog template file (default: $(CATALOG_TEMPLATE_FILE_OUTPUT))"
	@echo "  BUNDLE_BUILDS_FILE       Path to bundle builds file (default: $(BUNDLE_BUILDS_FILE))"
	@echo "  CATALOG_FILE             Path to catalog file (default: $(CATALOG_FILE))"
	@echo "  CATALOG_TEMPLATE_KONFLUX_INPUT   Input catalog template for Konflux operations (default: $(CATALOG_TEMPLATE_KONFLUX_INPUT))"
	@echo "  CATALOG_TEMPLATE_KONFLUX_OUTPUT  Output catalog template for Konflux operations (default: $(CATALOG_TEMPLATE_KONFLUX_OUTPUT))"
	@echo "  PACKAGE_NAME_KONFLUX     Package name for Konflux operations (default: $(PACKAGE_NAME_KONFLUX))"
	@echo "  TOOL_DIR                 Directory for downloaded tools (default: $(TOOL_DIR))"
	@echo "  OPERATOR_SDK_VERSION     Operator SDK version for downloads (default: $(OPERATOR_SDK_VERSION))"
	@echo "  UPSTREAM_FBC_IMAGE       Upstream FBC image for comparison (default: $(UPSTREAM_FBC_IMAGE))"
	@echo ""
	@echo "Bundle Image Configuration:"
	@echo "  QUAY_TENANT_NAME         Quay tenant name (default: $(QUAY_TENANT_NAME))"
	@echo "  BUNDLE_NAME_SUFFIX       Bundle name suffix (default: $(BUNDLE_NAME_SUFFIX))"
	@echo "  PRODUCTION_NAMESPACE     Production namespace (default: $(PRODUCTION_NAMESPACE))"
	@echo "  PRODUCTION_BUNDLE_NAME   Production bundle name (default: $(PRODUCTION_BUNDLE_NAME))"
	@echo "  QUAY_BUNDLE_IMAGE        Full quay bundle image (default: $(QUAY_BUNDLE_IMAGE))"
	@echo "  PRODUCTION_BUNDLE_IMAGE  Full production bundle image (default: $(PRODUCTION_BUNDLE_IMAGE))"
	@echo ""
	@echo "Examples:"
	@echo "  make update-catalog-template                              # Use default files"
	@echo "  make update-catalog-template CATALOG_TEMPLATE_FILE_INPUT=input.yaml CATALOG_TEMPLATE_FILE_OUTPUT=output.yaml  # Separate input/output files"
	@echo "  make validate-production-images CATALOG_FILE=my-catalog.yaml  # Use custom catalog"
	@echo "  make konflux-validate-catalog-template-bundle            # Validate using default input/output"
	@echo "  make konflux-validate-catalog-template-bundle CATALOG_TEMPLATE_KONFLUX_INPUT=input.yaml CATALOG_TEMPLATE_KONFLUX_OUTPUT=output.yaml  # Use custom input/output"
	@echo "  make konflux-generate-catalog                             # Generate quay.io catalog"
	@echo "  make konflux-generate-catalog-production                  # Generate registry.redhat.io catalog"
	@echo "  make konflux-compare-catalog                              # Compare generated catalog with upstream FBC"
	@echo "  make operator-sdk OPERATOR_SDK_VERSION=1.39.0           # Download operator-sdk for specific version"
	@echo ""
	@echo "Bundle Image Customization Examples:"
	@echo "  make konflux-generate-catalog-production PACKAGE_NAME_KONFLUX=my-operator"
	@echo "  make konflux-generate-catalog-production QUAY_TENANT_NAME=my-tenant"
	@echo "  make konflux-generate-catalog-production BUNDLE_NAME_SUFFIX=operator-bundle-4-21"
	@echo "  make konflux-generate-catalog-production PRODUCTION_NAMESPACE=ubi8"
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-35s %s\n", $$1, $$2}' $(SCRIPT_DIR)/Makefile
