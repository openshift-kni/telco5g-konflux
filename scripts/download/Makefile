# Download Scripts Makefile
# =========================
# This Makefile provides targets for downloading common tools using parameterizable scripts.

SCRIPT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# Default tool versions
DOWNLOAD_YQ_VERSION ?= v4.45.4
DOWNLOAD_OPM_VERSION ?= v1.52.0
DOWNLOAD_JQ_VERSION ?= 1.7.1
DOWNLOAD_OPENSHIFT_VERSION ?= 4.12

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
download-operator-sdk: ## Download operator-sdk from OpenShift mirror (use DOWNLOAD_OPENSHIFT_VERSION and DOWNLOAD_INSTALL_DIR to customize)
	@echo "Downloading operator-sdk for OpenShift $(DOWNLOAD_OPENSHIFT_VERSION) to $(DOWNLOAD_INSTALL_DIR)"
	OPENSHIFT_VERSION=$(DOWNLOAD_OPENSHIFT_VERSION) $(SCRIPT_DIR)/download-operator-sdk.sh --install-dir $(DOWNLOAD_INSTALL_DIR)

.PHONY: download-all
download-all: download-yq download-opm download-jq download-operator-sdk ## Download all tools (yq, opm, jq, operator-sdk)
	@echo "All tools downloaded successfully to $(DOWNLOAD_INSTALL_DIR)"

.PHONY: clean
clean: ## Remove downloaded tools from install directory
	@echo "Cleaning downloaded tools from $(DOWNLOAD_INSTALL_DIR)"
	rm -f $(DOWNLOAD_INSTALL_DIR)/yq
	rm -f $(DOWNLOAD_INSTALL_DIR)/opm
	rm -f $(DOWNLOAD_INSTALL_DIR)/jq
	rm -f $(DOWNLOAD_INSTALL_DIR)/operator-sdk

.PHONY: help
help: ## Display available targets
	@echo "Download Scripts"
	@echo "================"
	@echo ""
	@echo "This Makefile provides targets for downloading common tools."
	@echo ""
	@echo "Variables:"
	@echo "  DOWNLOAD_YQ_VERSION         yq version (current: $(DOWNLOAD_YQ_VERSION))"
	@echo "  DOWNLOAD_OPM_VERSION        opm version (current: $(DOWNLOAD_OPM_VERSION))"
	@echo "  DOWNLOAD_JQ_VERSION         jq version (current: $(DOWNLOAD_JQ_VERSION))"
	@echo "  DOWNLOAD_OPENSHIFT_VERSION  OpenShift version for operator-sdk (current: $(DOWNLOAD_OPENSHIFT_VERSION))"
	@echo "  DOWNLOAD_INSTALL_DIR        Install directory (current: $(DOWNLOAD_INSTALL_DIR))"
	@echo ""
	@echo "Examples:"
	@echo "  make download-all                                        # Download all tools with defaults"
	@echo "  make download-yq DOWNLOAD_YQ_VERSION=v4.44.2             # Download specific yq version"
	@echo "  make download-operator-sdk DOWNLOAD_OPENSHIFT_VERSION=4.12.76 # Download operator-sdk for specific OpenShift version"
	@echo "  make download-all DOWNLOAD_INSTALL_DIR=/usr/local/bin    # Download to custom directory"
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(SCRIPT_DIR)/Makefile
	@echo ""
	@echo "For detailed script help:"
	@echo "  $(SCRIPT_DIR)/download-yq.sh --help"
	@echo "  $(SCRIPT_DIR)/download-opm.sh --help"
	@echo "  $(SCRIPT_DIR)/download-jq.sh --help"
	@echo "  $(SCRIPT_DIR)/download-operator-sdk.sh --help"
