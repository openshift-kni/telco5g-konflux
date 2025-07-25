# Download Scripts Makefile
# =========================
# This Makefile provides targets for downloading common tools using parameterizable scripts.

SCRIPT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# Default tool versions
DOWNLOAD_YQ_VERSION ?= v4.45.4
DOWNLOAD_OPM_VERSION ?= v1.52.0
DOWNLOAD_JQ_VERSION ?= 1.7.1
DOWNLOAD_OPERATOR_SDK_VERSION ?= 1.40.0
DOWNLOAD_YAMLLINT_VERSION ?= 1.37.1
DOWNLOAD_GOLANGCI_LINT_VERSION ?= v1.64.8
DOWNLOAD_SHELLCHECK_VERSION ?= v0.10.0
DOWNLOAD_BASHATE_VERSION ?= 2.1.1

# Default installation directory
DOWNLOAD_INSTALL_DIR ?= ./bin

.PHONY: download-yq
download-yq: ## Download yq YAML processor (use DOWNLOAD_YQ_VERSION and DOWNLOAD_INSTALL_DIR to customize)
	@echo "Downloading yq version $(DOWNLOAD_YQ_VERSION) to $(DOWNLOAD_INSTALL_DIR)"
	$(SCRIPT_DIR)/download-yq.sh --install-dir $(DOWNLOAD_INSTALL_DIR) $(DOWNLOAD_YQ_VERSION)

.PHONY: download-opm
download-opm: ## Download opm (Operator Package Manager) (use DOWNLOAD_OPM_VERSION and DOWNLOAD_INSTALL_DIR to customize)
	@echo "Downloading opm version $(DOWNLOAD_OPM_VERSION) to $(DOWNLOAD_INSTALL_DIR)"
	$(SCRIPT_DIR)/download-opm.sh --install-dir $(DOWNLOAD_INSTALL_DIR) $(DOWNLOAD_OPM_VERSION)

.PHONY: download-jq
download-jq: ## Download jq JSON processor (use DOWNLOAD_JQ_VERSION and DOWNLOAD_INSTALL_DIR to customize)
	@echo "Downloading jq version $(DOWNLOAD_JQ_VERSION) to $(DOWNLOAD_INSTALL_DIR)"
	$(SCRIPT_DIR)/download-jq.sh --install-dir $(DOWNLOAD_INSTALL_DIR) $(DOWNLOAD_JQ_VERSION)

.PHONY: download-operator-sdk
download-operator-sdk: ## Download operator-sdk from GitHub releases (use DOWNLOAD_OPERATOR_SDK_VERSION and DOWNLOAD_INSTALL_DIR to customize)
	@echo "Downloading operator-sdk version $(DOWNLOAD_OPERATOR_SDK_VERSION) to $(DOWNLOAD_INSTALL_DIR)"
	$(SCRIPT_DIR)/download-operator-sdk.sh --install-dir $(DOWNLOAD_INSTALL_DIR) $(DOWNLOAD_OPERATOR_SDK_VERSION)

.PHONY: download-yamllint
download-yamllint: ## Download yamllint YAML linter (use DOWNLOAD_YAMLLINT_VERSION and DOWNLOAD_INSTALL_DIR to customize)
	@echo "Downloading yamllint version $(DOWNLOAD_YAMLLINT_VERSION) to $(DOWNLOAD_INSTALL_DIR)"
	$(SCRIPT_DIR)/download-yamllint.sh --install-dir $(DOWNLOAD_INSTALL_DIR) $(DOWNLOAD_YAMLLINT_VERSION)

.PHONY: download-golangci-lint
download-golangci-lint: ## Download golangci-lint Go linter (use DOWNLOAD_GOLANGCI_LINT_VERSION and DOWNLOAD_INSTALL_DIR to customize)
	@echo "Downloading golangci-lint version $(DOWNLOAD_GOLANGCI_LINT_VERSION) to $(DOWNLOAD_INSTALL_DIR)"
	$(SCRIPT_DIR)/download-golangci-lint.sh --install-dir $(DOWNLOAD_INSTALL_DIR) $(DOWNLOAD_GOLANGCI_LINT_VERSION)

.PHONY: download-shellcheck
download-shellcheck: ## Download shellcheck shell script linter (use DOWNLOAD_SHELLCHECK_VERSION and DOWNLOAD_INSTALL_DIR to customize)
	@echo "Downloading shellcheck version $(DOWNLOAD_SHELLCHECK_VERSION) to $(DOWNLOAD_INSTALL_DIR)"
	$(SCRIPT_DIR)/download-shellcheck.sh --install-dir $(DOWNLOAD_INSTALL_DIR) $(DOWNLOAD_SHELLCHECK_VERSION)

.PHONY: download-bashate
download-bashate: ## Download bashate bash style checker (use DOWNLOAD_BASHATE_VERSION and DOWNLOAD_INSTALL_DIR to customize)
	@echo "Downloading bashate version $(DOWNLOAD_BASHATE_VERSION) to $(DOWNLOAD_INSTALL_DIR)"
	$(SCRIPT_DIR)/download-bashate.sh --install-dir $(DOWNLOAD_INSTALL_DIR) $(DOWNLOAD_BASHATE_VERSION)

.PHONY: download-all
download-all: download-yq download-opm download-jq download-operator-sdk download-yamllint download-golangci-lint download-shellcheck download-bashate ## Download all tools (yq, opm, jq, operator-sdk, yamllint, golangci-lint, shellcheck, bashate)
	@echo "All tools downloaded successfully to $(DOWNLOAD_INSTALL_DIR)"

.PHONY: clean
clean: ## Remove downloaded tools from install directory
	@echo "Cleaning downloaded tools from $(DOWNLOAD_INSTALL_DIR)"
	rm -f $(DOWNLOAD_INSTALL_DIR)/yq
	rm -f $(DOWNLOAD_INSTALL_DIR)/opm
	rm -f $(DOWNLOAD_INSTALL_DIR)/jq
	rm -f $(DOWNLOAD_INSTALL_DIR)/operator-sdk
	rm -f $(DOWNLOAD_INSTALL_DIR)/yamllint
	rm -rf $(DOWNLOAD_INSTALL_DIR)/.yamllint-venv
	rm -f $(DOWNLOAD_INSTALL_DIR)/golangci-lint
	rm -f $(DOWNLOAD_INSTALL_DIR)/shellcheck
	rm -f $(DOWNLOAD_INSTALL_DIR)/bashate
	rm -rf $(DOWNLOAD_INSTALL_DIR)/.bashate-venv

.PHONY: test-containerized
test-containerized: ## Run tests for all download scripts
	@echo "Running download script tests in UBI9 container..."
	@echo "=================================================="
	podman run --rm -v $(SCRIPT_DIR):/workspace -w /workspace \
		registry.access.redhat.com/ubi9/ubi:latest \
		/bin/bash -c "set -e && \
		dnf install -y xz && \
		./tests/test-download-opm.sh && \
		./tests/test-download-operator-sdk.sh && \
		./tests/test-download-yq.sh && \
		./tests/test-download-jq.sh && \
		./tests/test-download-yamllint.sh && \
		./tests/test-download-golangci-lint.sh && \
		./tests/test-download-shellcheck.sh && \
		./tests/test-download-bashate.sh"
	@echo "All download script tests completed successfully."

.PHONY: test-local
test-local: ## Run tests locally (may be affected by system-installed tools)
	@echo "Running download script tests locally..."
	@echo "========================================"
	@set -e && \
	$(SCRIPT_DIR)/tests/test-download-opm.sh && \
	$(SCRIPT_DIR)/tests/test-download-operator-sdk.sh && \
	$(SCRIPT_DIR)/tests/test-download-yq.sh && \
	$(SCRIPT_DIR)/tests/test-download-jq.sh && \
	$(SCRIPT_DIR)/tests/test-download-yamllint.sh && \
	$(SCRIPT_DIR)/tests/test-download-golangci-lint.sh && \
	$(SCRIPT_DIR)/tests/test-download-shellcheck.sh && \
	$(SCRIPT_DIR)/tests/test-download-bashate.sh
	@echo "All download script tests completed successfully."

.PHONY: test-clean
test-clean: ## Clean test artifacts
	@echo "Cleaning test artifacts..."
	rm -rf $(SCRIPT_DIR)/tests/test_bin
	rm -f $(SCRIPT_DIR)/tests/test_results.log

.PHONY: help
help: ## Display available targets
	@echo "Download Scripts"
	@echo "================"
	@echo ""
	@echo "This Makefile provides targets for downloading common tools."
	@echo ""
	@echo "Variables:"
	@echo "  DOWNLOAD_YQ_VERSION           yq version (current: $(DOWNLOAD_YQ_VERSION))"
	@echo "  DOWNLOAD_OPM_VERSION          opm version (current: $(DOWNLOAD_OPM_VERSION))"
	@echo "  DOWNLOAD_JQ_VERSION           jq version (current: $(DOWNLOAD_JQ_VERSION))"
	@echo "  DOWNLOAD_OPERATOR_SDK_VERSION operator-sdk version (current: $(DOWNLOAD_OPERATOR_SDK_VERSION))"
	@echo "  DOWNLOAD_YAMLLINT_VERSION     yamllint version (current: $(DOWNLOAD_YAMLLINT_VERSION))"
	@echo "  DOWNLOAD_GOLANGCI_LINT_VERSION golangci-lint version (current: $(DOWNLOAD_GOLANGCI_LINT_VERSION))"
	@echo "  DOWNLOAD_SHELLCHECK_VERSION   shellcheck version (current: $(DOWNLOAD_SHELLCHECK_VERSION))"
	@echo "  DOWNLOAD_BASHATE_VERSION      bashate version (current: $(DOWNLOAD_BASHATE_VERSION))"
	@echo "  DOWNLOAD_INSTALL_DIR          Install directory (current: $(DOWNLOAD_INSTALL_DIR))"
	@echo ""
	@echo "Examples:"
	@echo "  make download-all                                            # Download all tools with defaults"
	@echo "  make download-yq DOWNLOAD_YQ_VERSION=v4.44.2                 # Download specific yq version"
	@echo "  make download-operator-sdk DOWNLOAD_OPERATOR_SDK_VERSION=1.39.0 # Download operator-sdk for specific version"
	@echo "  make download-yamllint DOWNLOAD_YAMLLINT_VERSION=1.35.1      # Download specific yamllint version"
	@echo "  make download-golangci-lint DOWNLOAD_GOLANGCI_LINT_VERSION=v1.55.0 # Download specific golangci-lint version"
	@echo "  make download-shellcheck DOWNLOAD_SHELLCHECK_VERSION=v0.9.0    # Download specific shellcheck version"
	@echo "  make download-bashate DOWNLOAD_BASHATE_VERSION=2.1.0          # Download specific bashate version"
	@echo "  make download-all DOWNLOAD_INSTALL_DIR=/usr/local/bin        # Download to custom directory"
	@echo "  make test                                                    # Run all download script tests in UBI9 container"
	@echo "  make test-local                                              # Run tests locally (faster, may be affected by system tools)"
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(SCRIPT_DIR)/Makefile
	@echo ""
	@echo "For detailed script help:"
	@echo "  $(SCRIPT_DIR)/download-yq.sh --help"
	@echo "  $(SCRIPT_DIR)/download-opm.sh --help"
	@echo "  $(SCRIPT_DIR)/download-jq.sh --help"
	@echo "  $(SCRIPT_DIR)/download-operator-sdk.sh --help"
	@echo "  $(SCRIPT_DIR)/download-yamllint.sh --help"
	@echo "  $(SCRIPT_DIR)/download-golangci-lint.sh --help"
	@echo "  $(SCRIPT_DIR)/download-shellcheck.sh --help"
	@echo "  $(SCRIPT_DIR)/download-bashate.sh --help"
