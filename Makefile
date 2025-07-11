# venv python integration derived from https://venthur.de/2021-03-31-python-makefiles.html
export SHELL := /usr/bin/env bash

# Get the root directory for make
export ROOT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

# Host python is used to setup venv
export PY ?= python3
export VENV := $(ROOT_DIR)/venv
export BIN := $(VENV)/bin

# Konflux catalog configuration
PACKAGE_NAME_KONFLUX = telco5g-konflux
CATALOG_TEMPLATE_KONFLUX = .konflux/catalog/catalog-template.in.yaml
CATALOG_KONFLUX = .konflux/catalog/$(PACKAGE_NAME_KONFLUX)/catalog.yaml

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
all: lint
	@echo "All build tasks completed successfully."

.PHONY: venv
venv: $(VENV)

# This rule creates the Python virtual environment if it doesn't exist
# or if the requirements file has been updated.
$(VENV): $(ROOT_DIR)/requirements.txt
	$(PY) -m venv $(VENV)
	$(BIN)/pip install --upgrade -r $(ROOT_DIR)/requirements.txt
	touch $(VENV)

# The 'lint' target runs all available linters.
.PHONY: lint
lint: yamllint shellcheck bashate konflux-filter-unused-repos ## Run all linters
	@echo "All linters passed."

# The 'yamllint' target depends on the virtual environment to ensure
# the linter is installed before being run.
# NOTE: To set line length to 120, add the following to your .yamllint.yaml file:
# rules:
#   line-length:
#     max: 120
.PHONY: yamllint
yamllint: venv
	$(BIN)/yamllint -c $(ROOT_DIR)/.yamllint.yaml .

# The 'shellcheck' target runs the shellcheck linter on all .sh files.
# It depends on the venv, assuming shellcheck-py is listed in requirements.txt.
# NOTE: shellcheck does not check for line length; it focuses on shell syntax and correctness.
.PHONY: shellcheck
shellcheck: venv
	$(BIN)/shellcheck $(shell find . -path ./venv -prune -o -type f -name "*.sh" -print)

# The 'bashate' target runs the bashate linter on all .sh files.
# It depends on the venv, assuming bashate is listed in requirements.txt.
# NOTE: bashate has a hardcoded 80-character limit that cannot be changed.
# The E006 error for long lines has been ignored.
.PHONY: bashate
bashate: venv
	$(BIN)/bashate --ignore=E006 $(shell find . -path ./venv -prune -o -type f -name "*.sh" -print)

# The 'clean' target removes generated artifacts like the virtual environment,
# the 'bin' directory for downloaded tools, and Python cache files.
clean:
	rm -rf $(VENV)
	rm -rf ./bin
	find . -type f -name *.pyc -delete
	find . -type d -name __pycache__ -delete

# Konflux targets

.PHONY: opm
OPM ?= ./bin/opm
opm: ## Download opm locally if necessary.
ifeq (,$(wildcard $(OPM)))
ifeq (,$(shell which opm 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(OPM)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSLo $(OPM) https://github.com/operator-framework/operator-registry/releases/download/v1.52.0/$${OS}-$${ARCH}-opm ;\
	chmod +x $(OPM) ;\
	}
else
OPM = $(shell which opm)
endif
endif

.PHONY: yq
YQ ?= ./bin/yq
yq: ## download yq if not in the path
ifeq (,$(wildcard $(YQ)))
ifeq (,$(shell which yq 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(YQ)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSLo $(YQ) https://github.com/mikefarah/yq/releases/download/v4.45.4/yq_$${OS}_$${ARCH} ;\
	chmod +x $(YQ) ;\
	}
else
YQ = $(shell which yq)
endif
endif

.PHONY: konflux-update-task-refs ## update task images
konflux-update-task-refs: yq
	hack/konflux-update-task-refs.sh .tekton/build-pipeline.yaml
	hack/konflux-update-task-refs.sh .tekton/fbc-pipeline.yaml

.PHONY: konflux-validate-catalog-template-bundle ## validate the last bundle entry on the catalog template file
konflux-validate-catalog-template-bundle: yq operator-sdk
	@{ \
	set -e ;\
	bundle=$(shell $(YQ) ".entries[-1].image" $(CATALOG_TEMPLATE_KONFLUX)) ;\
	echo "validating the last bundle entry: $${bundle} on catalog template: $(CATALOG_TEMPLATE_KONFLUX)" ;\
	$(OPERATOR_SDK) bundle validate $${bundle} ;\
	}

.PHONY: konflux-validate-catalog
konflux-validate-catalog: opm ## validate the current catalog file
	@echo "validating catalog: .konflux/catalog/$(PACKAGE_NAME_KONFLUX)"
	$(OPM) validate .konflux/catalog/$(PACKAGE_NAME_KONFLUX)/

.PHONY: konflux-generate-catalog ## generate a quay.io catalog
konflux-generate-catalog: yq opm
	hack/konflux-update-catalog-template.sh --set-catalog-template-file $(CATALOG_TEMPLATE_KONFLUX) --set-bundle-builds-file .konflux/catalog/bundle.builds.in.yaml
	touch $(CATALOG_KONFLUX)
	$(OPM) alpha render-template basic --output yaml --migrate-level bundle-object-to-csv-metadata $(CATALOG_TEMPLATE_KONFLUX) > $(CATALOG_KONFLUX)
	$(OPM) validate .konflux/catalog/$(PACKAGE_NAME_KONFLUX)/

.PHONY: konflux-generate-catalog-production ## generate a registry.redhat.io catalog
konflux-generate-catalog-production: konflux-generate-catalog
        # overlay the bundle image for production
	sed -i 's|quay.io/redhat-user-workloads/telco-5g-tenant/$(PACKAGE_NAME_KONFLUX)-operator-bundle-4-20|registry.redhat.io/openshift4/$(PACKAGE_NAME_KONFLUX)-operator-bundle|g' $(CATALOG_KONFLUX)
        # From now on, all the related images must reference production (registry.redhat.io) exclusively
	./hack/konflux-validate-related-images-production.sh --set-catalog-file $(CATALOG_KONFLUX)
	$(OPM) validate .konflux/catalog/$(PACKAGE_NAME_KONFLUX)/

.PHONY: konflux-filter-unused-repos ## filter unused repositories from redhat.repo files
konflux-filter-unused-repos:
	@echo "Filtering unused repositories from redhat.repo files..."
	@repo_files=$$(find . -name "redhat.repo" -type f | grep -v "./venv"); \
	if [[ -z "$$repo_files" ]]; then \
		echo "No redhat.repo files found in the repository."; \
	else \
		for repo_file in $$repo_files; do \
			echo "Processing: $$repo_file"; \
			if [[ -x "./hack/konflux-filter-unused-repos.sh" ]]; then \
				enabled_count=$$(./hack/konflux-filter-unused-repos.sh "$$repo_file" | grep -c "^\[.*\]$$" || echo "0"); \
				total_count=$$(grep -c "^\[.*\]$$" "$$repo_file" || echo "0"); \
				echo "  Found $$enabled_count enabled repositories out of $$total_count total repositories"; \
				echo "  Filtered output saved to: $${repo_file%.repo}.filtered.repo"; \
				./hack/konflux-filter-unused-repos.sh "$$repo_file" > "$${repo_file%.repo}.filtered.repo"; \
			else \
				echo "  ERROR: hack/konflux-filter-unused-repos.sh not found or not executable"; \
				exit 1; \
			fi; \
		done; \
	fi
