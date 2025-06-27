# venv python integration derived from https://venthur.de/2021-03-31-python-makefiles.html
export SHELL := /usr/bin/env bash

# Get the root directory for make
export ROOT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

# Host python is used to setup venv
export PY ?= python3
export VENV := $(ROOT_DIR)/venv
export BIN := $(VENV)/bin

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
lint: yamllint shellcheck bashate ## Run all linters
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
