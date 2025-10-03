# RPM Lock Scripts Makefile
# ==========================
# This Makefile provides targets for generating RPM lock files and filtering repositories.

# Get the directory of the current makefile
# Trim any trailing slash from the directory path as we will add if when necessary later
PROJECT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# Path for the filter-unused-repos target
REPO_FILE ?= redhat.repo

# Target directory for the lock scripts
# This should be configured by the caller of the Makefile
LOCK_SCRIPT_TARGET_DIR ?= $(PROJECT_DIR)

# The version of rpm-lockfile-prototype to use.
# Valid values are "main" or a commit hash.
RPM_LOCKFILE_PROTOTYPE_VERSION ?= main

# RHEL8 and RHEL9 here refer to the collective of RHEL and UBI images for the respective versions.
# These scripts can be used freely with rhel-els or ubi images as required.

# The following variables are used for registering the system with Red Hat
# These should be configured by the caller of the Makefile if you need to use RHSM
RHEL9_ACTIVATION_KEY ?= ""
RHEL9_ORG_ID ?= ""
RHEL8_ACTIVATION_KEY ?= ""
RHEL8_ORG_ID ?= ""

# Container images - can be overridden from the command line
# By default, we use the UBI images as they do not require RHSM registration.
RHEL9_IMAGE ?= registry.access.redhat.com/ubi9/ubi
RHEL9_MINIMAL_IMAGE ?= registry.access.redhat.com/ubi9/ubi-minimal
RHEL9_RELEASE ?= 9.4

RHEL8_IMAGE ?= registry.access.redhat.com/ubi8/ubi
RHEL8_MINIMAL_IMAGE ?= registry.access.redhat.com/ubi8/ubi-minimal
RHEL8_RELEASE ?= 8.10

# We use these images to run the scripts inside containers
RHEL9_EXECUTION_IMAGE ?= $(RHEL9_IMAGE):$(RHEL9_RELEASE)
RHEL8_EXECUTION_IMAGE ?= $(RHEL8_IMAGE):$(RHEL8_RELEASE)

# These are the images that the packages will be installed into
RHEL9_IMAGE_TO_LOCK ?= $(RHEL9_MINIMAL_IMAGE):$(RHEL9_RELEASE)
RHEL8_IMAGE_TO_LOCK ?= $(RHEL8_MINIMAL_IMAGE):$(RHEL8_RELEASE)

# The registry auth file is mounted into the container to allow for private registry pulls.
# This is automatically detected and mounted into the container if it exists on the host.
# If it does not exist, a warning is printed and the registry pulls may fail if not public.
# This can be set from the command line if the default is not correct for your environment.
REGISTRY_AUTH_FILE ?= $(shell echo $${XDG_RUNTIME_DIR:-/run/user/$$(id -u)})/containers/auth.json

# === Targets ===
.PHONY: all
all: help ## Run the default target (prints help).

.PHONY: filter-unused-repos
filter-unused-repos: ## Filter unused repositories from redhat.repo files (use REPO_FILE=path)
	@echo "Filtering unused repositories from $(REPO_FILE)..."
	$(PROJECT_DIR)/konflux-filter-unused-repos.sh $(REPO_FILE) > $(REPO_FILE).tmp && mv $(REPO_FILE).tmp $(REPO_FILE)

.PHONY: test-integration
test-integration: ## Run integration tests for both RHEL 8 and RHEL 9 scripts (UBI mode)
	@echo "Running integration tests in UBI mode..."
	@cd $(PROJECT_DIR)/tests && ./run-integration-tests.sh $(if $(VERBOSE),--verbose)

.PHONY: test-integration-rhsm
test-integration-rhsm: ## Run integration tests with RHSM credentials (requires valid credentials)
	@echo "Running integration tests in RHSM mode..."
	@echo "Note: This requires valid RHEL activation keys and organization IDs"
	@export \
		RHEL8_ACTIVATION_KEY=$(RHEL8_ACTIVATION_KEY) \
		RHEL8_ORG_ID=$(RHEL8_ORG_ID) \
		RHEL9_ACTIVATION_KEY=$(RHEL9_ACTIVATION_KEY) \
		RHEL9_ORG_ID=$(RHEL9_ORG_ID) \
		RPM_LOCKFILE_PROTOTYPE_VERSION=$(RPM_LOCKFILE_PROTOTYPE_VERSION); \
	cd $(PROJECT_DIR)/tests && ./run-integration-tests.sh $(if $(VERBOSE),--verbose)

.PHONY: test-rhel8-only
test-rhel8-only: ## Run RHEL 8 integration test only (UBI mode)
	@echo "Running RHEL 8 integration test in UBI mode..."
	@cd $(PROJECT_DIR)/tests && ./run-integration-tests.sh --rhel8-only $(if $(VERBOSE),--verbose)

.PHONY: test-rhel9-only
test-rhel9-only: ## Run RHEL 9 integration test only (UBI mode)
	@echo "Running RHEL 9 integration test in UBI mode..."
	@cd $(PROJECT_DIR)/tests && ./run-integration-tests.sh --rhel9-only $(if $(VERBOSE),--verbose)

.PHONY: test-rhel8-rhsm
test-rhel8-rhsm: ## Run RHEL 8 integration test with RHSM credentials
	@echo "Running RHEL 8 integration test in RHSM mode..."
	@export \
		RHEL8_ACTIVATION_KEY=$(RHEL8_ACTIVATION_KEY) \
		RHEL8_ORG_ID=$(RHEL8_ORG_ID) \
		RHEL9_ACTIVATION_KEY=$(RHEL9_ACTIVATION_KEY) \
		RHEL9_ORG_ID=$(RHEL9_ORG_ID) \
		RPM_LOCKFILE_PROTOTYPE_VERSION=$(RPM_LOCKFILE_PROTOTYPE_VERSION); \
	cd $(PROJECT_DIR)/tests && ./run-integration-tests.sh --rhel8-only $(if $(VERBOSE),--verbose)

.PHONY: test-rhel9-rhsm
test-rhel9-rhsm: ## Run RHEL 9 integration test with RHSM credentials
	@echo "Running RHEL 9 integration test in RHSM mode..."
	@export \
		RHEL9_ACTIVATION_KEY=$(RHEL9_ACTIVATION_KEY) \
		RHEL9_ORG_ID=$(RHEL9_ORG_ID) \
		RPM_LOCKFILE_PROTOTYPE_VERSION=$(RPM_LOCKFILE_PROTOTYPE_VERSION); \
	cd $(PROJECT_DIR)/tests && ./run-integration-tests.sh --rhel9-only $(if $(VERBOSE),--verbose)

.PHONY: generate-rhel9-locks
generate-rhel9-locks: ## Generate RHEL 9 lock files. Override images with RHEL9_IMAGE, RHEL9_MINIMAL_IMAGE.
	@echo "Running RHEL 9 lock file generation script..."
	@export \
		REGISTRY_AUTH_FILE=$(REGISTRY_AUTH_FILE) \
		RHEL9_IMAGE_TO_LOCK=$(RHEL9_IMAGE_TO_LOCK) \
		RPM_LOCKFILE_PROTOTYPE_VERSION=$(RPM_LOCKFILE_PROTOTYPE_VERSION) \
		\
		RHEL9_EXECUTION_IMAGE=$(RHEL9_EXECUTION_IMAGE) \
		RHEL9_RELEASE=$(RHEL9_RELEASE) \
		RHEL9_ACTIVATION_KEY=$(RHEL9_ACTIVATION_KEY) \
		RHEL9_ORG_ID=$(RHEL9_ORG_ID) \
		; \
	$(PROJECT_DIR)/generate-rhel9-locks.sh $(LOCK_SCRIPT_TARGET_DIR)

.PHONY: generate-rhel8-locks
generate-rhel8-locks: ## Generate RHEL 8 lock files. Override images with UBI8_IMAGE, UBI9_IMAGE, etc.
	@echo "Running RHEL 8 lock file generation script (workaround)..."
	@export \
		RHEL8_IMAGE_TO_LOCK=$(RHEL8_IMAGE_TO_LOCK) \
		REGISTRY_AUTH_FILE=$(REGISTRY_AUTH_FILE) \
		RPM_LOCKFILE_PROTOTYPE_VERSION=$(RPM_LOCKFILE_PROTOTYPE_VERSION) \
		\
		RHEL8_EXECUTION_IMAGE=$(RHEL8_EXECUTION_IMAGE) \
		RHEL8_RELEASE=$(RHEL8_RELEASE) \
		RHEL8_ACTIVATION_KEY=$(RHEL8_ACTIVATION_KEY) \
		RHEL8_ORG_ID=$(RHEL8_ORG_ID) \
		\
		RHEL9_EXECUTION_IMAGE=$(RHEL9_EXECUTION_IMAGE) \
		RHEL9_RELEASE=$(RHEL9_RELEASE) \
		RHEL9_ACTIVATION_KEY=$(RHEL9_ACTIVATION_KEY) \
		RHEL9_ORG_ID=$(RHEL9_ORG_ID) \
		; \
	$(PROJECT_DIR)/generate-rhel8-locks.sh $(LOCK_SCRIPT_TARGET_DIR)

.PHONY: help
help: ## Display available targets and variables.
	@echo "RPM Lock Scripts"
	@echo "==============="
	@echo ""
	@echo "This Makefile provides targets for generating RPM lock files and filtering repositories."
	@echo ""
	@echo "Variables:"
	@echo "  LOCK_SCRIPT_TARGET_DIR    The project directory to run the scripts against (default: .)"
	@echo "  REGISTRY_AUTH_FILE        Path to registry auth file for private registry pulls (default: ~/.config/containers/auth.json)"
	@echo "  REPO_FILE                 Path to redhat.repo file for filtering (default: redhat.repo)"
	@echo "  RHEL8_ACTIVATION_KEY      Red Hat Activation Key for RHEL8 (default: '')"
	@echo "  RHEL8_EXECUTION_IMAGE     Image and tag for UBI8 generation (default: \$$RHEL8_IMAGE:\$$RHEL8_RELEASE)"
	@echo "  RHEL8_IMAGE               Image for UBI8 generation (default: registry.access.redhat.com/ubi8/ubi)"
	@echo "  RHEL8_IMAGE_TO_LOCK       Image and tag for UBI8 minimal runtime (default: \$$RHEL8_MINIMAL_IMAGE:\$$RHEL8_RELEASE)"
	@echo "  RHEL8_MINIMAL_IMAGE       Image for UBI8 minimal runtime (default: registry.access.redhat.com/ubi8/ubi-minimal)"
	@echo "  RHEL8_ORG_ID              Red Hat Organization ID for RHEL8 (default: '')"
	@echo "  RHEL8_RELEASE             Release for UBI8 generation (default: 8.10)"
	@echo "  RHEL9_ACTIVATION_KEY      Red Hat Activation Key for RHEL9 (default: '')"
	@echo "  RHEL9_EXECUTION_IMAGE     Image and tag for UBI9 generation (default: \$$RHEL9_IMAGE:\$$RHEL9_RELEASE)"
	@echo "  RHEL9_IMAGE               Image for UBI9 generation (default: registry.access.redhat.com/ubi9/ubi)"
	@echo "  RHEL9_IMAGE_TO_LOCK       Image and tagfor UBI9 minimal runtime (default: \$$RHEL9_MINIMAL_IMAGE:\$$RHEL9_RELEASE)"
	@echo "  RHEL9_MINIMAL_IMAGE       Image for UBI9 minimal runtime (default: registry.access.redhat.com/ubi9/ubi-minimal)"
	@echo "  RHEL9_ORG_ID              Red Hat Organization ID for RHEL9 (default: '')"
	@echo "  RHEL9_RELEASE             Release for RHEL9 generation (default: 9.4)"
	@echo ""
	@echo "Examples:"
	@echo "  make generate-rhel9-locks \\"
	@echo "       LOCK_SCRIPT_TARGET_DIR=/path/to/project \\"
	@echo "       RHEL9_ACTIVATION_KEY=1234567890 RHEL9_ORG_ID=my-org-key \\"
	@echo "       REGISTRY_AUTH_FILE=/path/to/auth.json"
	@echo ""
	@echo "  make generate-rhel9-locks \\"
	@echo "       RHEL9_IMAGE=my-registry/rhel9 \\"
	@echo "       RHEL9_MINIMAL_IMAGE=my-registry/rhel9-minimal \\"
	@echo "       RHEL9_RELEASE=9.4 \\"
	@echo "       RHEL9_ACTIVATION_KEY=1234567890 RHEL9_ORG_ID=my-org-key \\"
	@echo "       REGISTRY_AUTH_FILE=/path/to/auth.json"
	@echo ""
	@echo "  make generate-rhel8-locks \\"
	@echo "       LOCK_SCRIPT_TARGET_DIR=/path/to/project \\"
	@echo "       RHEL8_ACTIVATION_KEY=1234567890 RHEL8_ORG_ID=my-org-key \\"
	@echo "       RHEL9_ACTIVATION_KEY=1234567890 RHEL9_ORG_ID=my-org-key \\"
	@echo "       REGISTRY_AUTH_FILE=/path/to/auth.json"
	@echo ""
	@echo "  make generate-rhel8-locks \\"
	@echo "       RHEL8_IMAGE=my-registry/ubi8-minimal \\"
	@echo "       RHEL8_RELEASE=8.10 \\"
	@echo "       RHEL9_IMAGE=my-registry/ubi9-minimal \\"
	@echo "       RHEL9_RELEASE=9.4 \\"
	@echo "       RHEL8_ACTIVATION_KEY=1234567890 RHEL8_ORG_ID=my-org-key \\"
	@echo "       RHEL9_ACTIVATION_KEY=1234567890 RHEL9_ORG_ID=my-org-key \\"
	@echo "       REGISTRY_AUTH_FILE=/path/to/auth.json"
	@echo ""
	@echo "  make filter-unused-repos REPO_FILE=/path/to/file"
	@echo ""
	@echo "  # Test targets"
	@echo "  make test-integration                    # Run integration tests (UBI mode)"
	@echo "  make test-integration-rhsm               # Run integration tests (RHSM mode)"
	@echo "  make test-rhel8-only                     # Run RHEL 8 test only (UBI mode)"
	@echo "  make test-rhel9-only                     # Run RHEL 9 test only (UBI mode)"
	@echo "  make test-rhel8-rhsm                     # Run RHEL 8 test (RHSM mode)"
	@echo "  make test-rhel9-rhsm                     # Run RHEL 9 test (RHSM mode)"
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-22s %s\n", $$1, $$2}' $(PROJECT_DIR)/Makefile
