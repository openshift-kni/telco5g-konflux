# Telco5G Konflux CI/CD Targets
# ================================
# This Makefile can be used standalone or as a submodule in other operator repositories.
#
# SUBMODULE USAGE:
# 1. Add as submodule: git submodule add https://github.com/openshift-kni/telco5g-konflux.git konflux
# 2. Include in your Makefile: include konflux/Makefile
# 3. Configure variables: TELCO5G_KONFLUX_PACKAGE_NAME = my-operator
# 4. Customize bundle names: TELCO5G_KONFLUX_DEV_BUNDLE_NAME = my-operator-bundle-v1.0
# 5. Use prefixed targets: telco5g-konflux-lint, konflux-generate-catalog, etc.
#
# See SUBMODULE_USAGE.md for detailed documentation.
# ================================

# venv python integration derived from https://venthur.de/2021-03-31-python-makefiles.html
export SHELL := /usr/bin/env bash

# Submodule compatibility: Get the directory of this Makefile
# This allows the Makefile to work when imported as a submodule
export TELCO5G_KONFLUX_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# Get the root directory for make (current working directory when make is called)
export ROOT_DIR := $(shell pwd)

# Host python is used to setup venv
export PY ?= python3
export TELCO5G_KONFLUX_VENV := $(TELCO5G_KONFLUX_DIR)/venv
export TELCO5G_KONFLUX_BIN := $(TELCO5G_KONFLUX_VENV)/bin

# Konflux catalog configuration - make paths configurable for parent projects
TELCO5G_KONFLUX_PACKAGE_NAME ?= telco5g-konflux
TELCO5G_KONFLUX_CATALOG_TEMPLATE ?= $(TELCO5G_KONFLUX_DIR)/.konflux/catalog/catalog-template.in.yaml
TELCO5G_KONFLUX_CATALOG ?= $(TELCO5G_KONFLUX_DIR)/.konflux/catalog/$(TELCO5G_KONFLUX_PACKAGE_NAME)/catalog.yaml
TELCO5G_KONFLUX_BUNDLE_BUILDS ?= $(TELCO5G_KONFLUX_DIR)/.konflux/catalog/bundle.builds.in.yaml

# Bundle image naming configuration - customizable for different operators
TELCO5G_KONFLUX_DEV_BUNDLE_NAME ?= $(TELCO5G_KONFLUX_PACKAGE_NAME)-operator-bundle-4-20
TELCO5G_KONFLUX_PROD_BUNDLE_NAME ?= $(TELCO5G_KONFLUX_PACKAGE_NAME)-operator-bundle

# Build pipeline paths - configurable for parent projects
TELCO5G_KONFLUX_BUILD_PIPELINE ?= $(TELCO5G_KONFLUX_DIR)/.tekton/build-pipeline.yaml
TELCO5G_KONFLUX_FBC_PIPELINE ?= $(TELCO5G_KONFLUX_DIR)/.tekton/fbc-pipeline.yaml

# By default we build the same architecture we are running
# Override this by specifying a different GOARCH in your environment
HOST_ARCH ?= $(shell uname -m)

# Convert from uname format to GOARCH format
ifeq ($(HOST_ARCH),aarch64)
	HOST_ARCH=arm64
endif
ifeq ($(HOST_ARCH),x86_64)
	HOST_ARCH=amd64
endif

# Define GOARCH as HOST_ARCH if not otherwise defined
ifndef GOARCH
	GOARCH=$(HOST_ARCH)
endif

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Setting SHELL to bash allows bash commands to be executed by recipes.
# This is a requirement for 'setup-envtest.sh' in the test target.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
export PATH  := $(PATH):$(PWD)/bin
GOFLAGS := -mod=mod
SHELL = /usr/bin/env GOFLAGS=$(GOFLAGS) bash -o pipefail

.SHELLFLAGS = -ec

# The 'all' target is the default goal.
all: telco5g-konflux-lint
	@echo "All build tasks completed successfully."

.PHONY: telco5g-konflux-venv
telco5g-konflux-venv: $(TELCO5G_KONFLUX_VENV)

# This rule creates the Python virtual environment if it doesn't exist
# or if the requirements file has been updated.
$(TELCO5G_KONFLUX_VENV): $(TELCO5G_KONFLUX_DIR)/requirements.txt
	$(PY) -m venv $(TELCO5G_KONFLUX_VENV)
	$(TELCO5G_KONFLUX_BIN)/pip install --upgrade -r $(TELCO5G_KONFLUX_DIR)/requirements.txt
	touch $(TELCO5G_KONFLUX_VENV)

# The 'lint' target runs all available linters.
.PHONY: telco5g-konflux-lint
telco5g-konflux-lint: telco5g-konflux-yamllint telco5g-konflux-shellcheck telco5g-konflux-bashate telco5g-konflux-filter-unused-repos ## Run all linters
	@echo "All linters passed."

# Legacy target for backward compatibility
.PHONY: lint
lint: telco5g-konflux-lint

# The 'yamllint' target depends on the virtual environment to ensure
# the linter is installed before being run.
# NOTE: To set line length to 120, add the following to your .yamllint.yaml file:
# rules:
#   line-length:
#     max: 120
.PHONY: telco5g-konflux-yamllint
telco5g-konflux-yamllint: telco5g-konflux-venv
	cd $(TELCO5G_KONFLUX_DIR) && $(TELCO5G_KONFLUX_BIN)/yamllint -c $(TELCO5G_KONFLUX_DIR)/.yamllint.yaml .

# Legacy target for backward compatibility
.PHONY: yamllint
yamllint: telco5g-konflux-yamllint

# The 'shellcheck' target runs the shellcheck linter on all .sh files.
# It depends on the venv, assuming shellcheck-py is listed in requirements.txt.
# NOTE: shellcheck does not check for line length; it focuses on shell syntax and correctness.
.PHONY: telco5g-konflux-shellcheck
telco5g-konflux-shellcheck: telco5g-konflux-venv
	cd $(TELCO5G_KONFLUX_DIR) && $(TELCO5G_KONFLUX_BIN)/shellcheck $(shell find $(TELCO5G_KONFLUX_DIR) -path $(TELCO5G_KONFLUX_VENV) -prune -o -type f -name "*.sh" -print)

# Legacy target for backward compatibility
.PHONY: shellcheck
shellcheck: telco5g-konflux-shellcheck

# The 'bashate' target runs the bashate linter on all .sh files.
# It depends on the venv, assuming bashate is listed in requirements.txt.
# NOTE: bashate has a hardcoded 80-character limit that cannot be changed.
# The E006 error for long lines has been ignored.
.PHONY: telco5g-konflux-bashate
telco5g-konflux-bashate: telco5g-konflux-venv
	cd $(TELCO5G_KONFLUX_DIR) && $(TELCO5G_KONFLUX_BIN)/bashate --ignore=E006 $(shell find $(TELCO5G_KONFLUX_DIR) -path $(TELCO5G_KONFLUX_VENV) -prune -o -type f -name "*.sh" -print)

# Legacy target for backward compatibility
.PHONY: bashate
bashate: telco5g-konflux-bashate

# The 'clean' target removes generated artifacts like the virtual environment,
# the 'bin' directory for downloaded tools, and Python cache files.
.PHONY: telco5g-konflux-clean
telco5g-konflux-clean:
	rm -rf $(TELCO5G_KONFLUX_VENV)
	rm -rf $(TELCO5G_KONFLUX_DIR)/bin
	find $(TELCO5G_KONFLUX_DIR) -type f -name "*.pyc" -delete
	find $(TELCO5G_KONFLUX_DIR) -type d -name "__pycache__" -delete

# Legacy target for backward compatibility
.PHONY: clean
clean: telco5g-konflux-clean

# Konflux targets

.PHONY: telco5g-konflux-opm
TELCO5G_KONFLUX_OPM ?= $(TELCO5G_KONFLUX_DIR)/bin/opm
telco5g-konflux-opm: ## Download opm locally if necessary.
ifeq (,$(wildcard $(TELCO5G_KONFLUX_OPM)))
ifeq (,$(shell which opm 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(TELCO5G_KONFLUX_OPM)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSLo $(TELCO5G_KONFLUX_OPM) https://github.com/operator-framework/operator-registry/releases/download/v1.52.0/$${OS}-$${ARCH}-opm ;\
	chmod +x $(TELCO5G_KONFLUX_OPM) ;\
	}
else
TELCO5G_KONFLUX_OPM = $(shell which opm)
endif
endif

# Legacy target for backward compatibility
.PHONY: opm
opm: telco5g-konflux-opm
	$(eval OPM := $(TELCO5G_KONFLUX_OPM))

.PHONY: telco5g-konflux-yq
TELCO5G_KONFLUX_YQ ?= $(TELCO5G_KONFLUX_DIR)/bin/yq
telco5g-konflux-yq: ## download yq if not in the path
ifeq (,$(wildcard $(TELCO5G_KONFLUX_YQ)))
ifeq (,$(shell which yq 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(TELCO5G_KONFLUX_YQ)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSLo $(TELCO5G_KONFLUX_YQ) https://github.com/mikefarah/yq/releases/download/v4.45.4/yq_$${OS}_$${ARCH} ;\
	chmod +x $(TELCO5G_KONFLUX_YQ) ;\
	}
else
TELCO5G_KONFLUX_YQ = $(shell which yq)
endif
endif

# Legacy target for backward compatibility
.PHONY: yq
yq: telco5g-konflux-yq
	$(eval YQ := $(TELCO5G_KONFLUX_YQ))

.PHONY: konflux-update-task-refs ## update task images
konflux-update-task-refs: telco5g-konflux-yq
	cd $(TELCO5G_KONFLUX_DIR) && $(TELCO5G_KONFLUX_DIR)/hack/konflux-update-task-refs.sh $(TELCO5G_KONFLUX_BUILD_PIPELINE)
	cd $(TELCO5G_KONFLUX_DIR) && $(TELCO5G_KONFLUX_DIR)/hack/konflux-update-task-refs.sh $(TELCO5G_KONFLUX_FBC_PIPELINE)

.PHONY: konflux-validate-catalog-template-bundle ## validate the last bundle entry on the catalog template file
konflux-validate-catalog-template-bundle: telco5g-konflux-yq operator-sdk
	@{ \
	set -e ;\
	bundle=$(shell $(TELCO5G_KONFLUX_YQ) ".entries[-1].image" $(TELCO5G_KONFLUX_CATALOG_TEMPLATE)) ;\
	echo "validating the last bundle entry: $${bundle} on catalog template: $(TELCO5G_KONFLUX_CATALOG_TEMPLATE)" ;\
	$(OPERATOR_SDK) bundle validate $${bundle} ;\
	}

.PHONY: konflux-validate-catalog
konflux-validate-catalog: telco5g-konflux-opm ## validate the current catalog file
	@echo "validating catalog: $(TELCO5G_KONFLUX_DIR)/.konflux/catalog/$(TELCO5G_KONFLUX_PACKAGE_NAME)"
	$(TELCO5G_KONFLUX_OPM) validate $(TELCO5G_KONFLUX_DIR)/.konflux/catalog/$(TELCO5G_KONFLUX_PACKAGE_NAME)/

.PHONY: konflux-generate-catalog ## generate a quay.io catalog
konflux-generate-catalog: telco5g-konflux-yq telco5g-konflux-opm
	cd $(TELCO5G_KONFLUX_DIR) && $(TELCO5G_KONFLUX_DIR)/hack/konflux-update-catalog-template.sh --set-catalog-template-file $(TELCO5G_KONFLUX_CATALOG_TEMPLATE) --set-bundle-builds-file $(TELCO5G_KONFLUX_BUNDLE_BUILDS)
	touch $(TELCO5G_KONFLUX_CATALOG)
	$(TELCO5G_KONFLUX_OPM) alpha render-template basic --output yaml --migrate-level bundle-object-to-csv-metadata $(TELCO5G_KONFLUX_CATALOG_TEMPLATE) > $(TELCO5G_KONFLUX_CATALOG)
	$(TELCO5G_KONFLUX_OPM) validate $(TELCO5G_KONFLUX_DIR)/.konflux/catalog/$(TELCO5G_KONFLUX_PACKAGE_NAME)/

.PHONY: konflux-generate-catalog-production ## generate a registry.redhat.io catalog
konflux-generate-catalog-production: konflux-generate-catalog
        # overlay the bundle image for production
	sed -i 's|quay.io/redhat-user-workloads/telco-5g-tenant/$(TELCO5G_KONFLUX_DEV_BUNDLE_NAME)|registry.redhat.io/openshift4/$(TELCO5G_KONFLUX_PROD_BUNDLE_NAME)|g' $(TELCO5G_KONFLUX_CATALOG)
        # From now on, all the related images must reference production (registry.redhat.io) exclusively
	cd $(TELCO5G_KONFLUX_DIR) && $(TELCO5G_KONFLUX_DIR)/hack/konflux-validate-related-images-production.sh --set-catalog-file $(TELCO5G_KONFLUX_CATALOG)
	$(TELCO5G_KONFLUX_OPM) validate $(TELCO5G_KONFLUX_DIR)/.konflux/catalog/$(TELCO5G_KONFLUX_PACKAGE_NAME)/

.PHONY: telco5g-konflux-filter-unused-repos ## filter unused repositories from redhat.repo files
telco5g-konflux-filter-unused-repos:
	@echo "Filtering unused repositories from redhat.repo files..."
	@repo_files=$$(find $(TELCO5G_KONFLUX_DIR) -name "redhat.repo" -type f | grep -v "$(TELCO5G_KONFLUX_VENV)"); \
	if [ -z "$$repo_files" ]; then \
		echo "No redhat.repo files found in the repository."; \
	else \
		for repo_file in $$repo_files; do \
			echo "Processing: $$repo_file"; \
			if [ -x "$(TELCO5G_KONFLUX_DIR)/hack/konflux-filter-unused-repos.sh" ]; then \
				enabled_count=$$($(TELCO5G_KONFLUX_DIR)/hack/konflux-filter-unused-repos.sh "$$repo_file" | grep -c "^\[.*\]$$" || echo "0"); \
				total_count=$$(grep -c "^\[.*\]$$" "$$repo_file" || echo "0"); \
				echo "  Found $$enabled_count enabled repositories out of $$total_count total repositories"; \
				echo "  Filtered output saved to: $${repo_file%.repo}.filtered.repo"; \
				$(TELCO5G_KONFLUX_DIR)/hack/konflux-filter-unused-repos.sh "$$repo_file" > "$${repo_file%.repo}.filtered.repo"; \
			else \
				echo "  ERROR: $(TELCO5G_KONFLUX_DIR)/hack/konflux-filter-unused-repos.sh not found or not executable"; \
				exit 1; \
			fi; \
		done; \
	fi

# Legacy target for backward compatibility
.PHONY: konflux-filter-unused-repos
konflux-filter-unused-repos: telco5g-konflux-filter-unused-repos
