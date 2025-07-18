# Telco5G Konflux Linting Targets
# ================================
# This Makefile provides linting targets for shell scripts and YAML files.
# ================================

# venv python integration derived from https://venthur.de/2021-03-31-python-makefiles.html
export SHELL := /usr/bin/env bash

# Get the directory of this Makefile
export TELCO5G_KONFLUX_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# Host python is used to setup venv
export PY ?= python3
export TELCO5G_KONFLUX_VENV := $(TELCO5G_KONFLUX_DIR)/venv
export TELCO5G_KONFLUX_BIN := $(TELCO5G_KONFLUX_VENV)/bin

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail

.SHELLFLAGS = -ec

# The 'all' target is the default goal.
all: lint
	@echo "All linting and testing tasks completed successfully."

.PHONY: venv
venv: $(TELCO5G_KONFLUX_VENV)

# This rule creates the Python virtual environment if it doesn't exist
# or if the requirements file has been updated.
$(TELCO5G_KONFLUX_VENV): $(TELCO5G_KONFLUX_DIR)/requirements.txt
	$(PY) -m venv $(TELCO5G_KONFLUX_VENV)
	$(TELCO5G_KONFLUX_BIN)/pip install --upgrade -r $(TELCO5G_KONFLUX_DIR)/requirements.txt
	touch $(TELCO5G_KONFLUX_VENV)

# The 'lint' target runs all available linters.
.PHONY: lint
lint: yamllint shellcheck bashate ## Run all linters
	@echo "All linters passed."

# The 'yamllint' target depends on the virtual environment to ensure
# the linter is installed before being run.
.PHONY: yamllint
yamllint: venv
	cd $(TELCO5G_KONFLUX_DIR) && $(TELCO5G_KONFLUX_BIN)/yamllint -c $(TELCO5G_KONFLUX_DIR)/.yamllint.yaml .

# The 'shellcheck' target runs the shellcheck linter on all .sh files.
# It depends on the venv, assuming shellcheck-py is listed in requirements.txt.
# NOTE: shellcheck does not check for line length; it focuses on shell syntax and correctness.
.PHONY: shellcheck
shellcheck: venv
	cd $(TELCO5G_KONFLUX_DIR) && $(TELCO5G_KONFLUX_BIN)/shellcheck --severity=error $(shell find $(TELCO5G_KONFLUX_DIR) -path $(TELCO5G_KONFLUX_VENV) -prune -o -type f -name "*.sh" -size +0c -print)

# The 'bashate' target runs the bashate linter on all .sh files.
# It depends on the venv, assuming bashate is listed in requirements.txt.
# NOTE: bashate has a hardcoded 80-character limit that cannot be changed.
# The E006 error for long lines has been ignored.
.PHONY: bashate
bashate: venv
	cd $(TELCO5G_KONFLUX_DIR) && $(TELCO5G_KONFLUX_BIN)/bashate --ignore=E006 $(shell find $(TELCO5G_KONFLUX_DIR) -path $(TELCO5G_KONFLUX_VENV) -prune -o -type f -name "*.sh" -print)

# The 'clean' target removes generated artifacts like the virtual environment,
# the 'bin' directory for downloaded tools, and Python cache files.
.PHONY: clean
clean:
	rm -rf $(TELCO5G_KONFLUX_VENV)
	rm -rf $(TELCO5G_KONFLUX_DIR)/bin
	find $(TELCO5G_KONFLUX_DIR) -type f -name "*.pyc" -delete
	find $(TELCO5G_KONFLUX_DIR) -type d -name "__pycache__" -delete

.PHONY: help
help: ## Display this help message
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
