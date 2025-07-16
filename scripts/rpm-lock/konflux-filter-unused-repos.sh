#!/bin/bash

# Script to filter unused yum repositories from redhat.repo file
# Usage: konflux-filter-unused-repos.sh <path-to-redhat.repo>

set -euo pipefail

# Function to display usage
usage() {
    echo "Usage: $0 <path-to-redhat.repo>"
    echo "Filters out unused yum repositories (enabled = 0) from a redhat.repo file"
    echo "and outputs only the enabled repositories (enabled = 1) to stdout."
    exit 1
}

# Check if argument is provided
if [[ $# -ne 1 ]]; then
    usage
fi

REPO_FILE="$1"

# Check if file exists
if [[ ! -f "$REPO_FILE" ]]; then
    echo "Error: File '$REPO_FILE' not found!" >&2
    exit 1
fi

# Use awk to filter the repo file
awk '
BEGIN {
    in_section = 0
    current_section = ""
    enabled = 0
}

# Start of a new section
/^\[.*\]$/ {
    # If we were in a section and it was enabled, print it
    if (in_section && enabled) {
        print current_section
    }

    # Start new section
    current_section = $0 "\n"
    in_section = 1
    enabled = 0
    next
}

# Inside a section
in_section {
    current_section = current_section $0 "\n"

    # Check if this line indicates the repository is enabled
    if ($0 ~ /^enabled = 1$/) {
        enabled = 1
    }

    # Check for empty line (end of section)
    if ($0 ~ /^[[:space:]]*$/) {
        # If this section was enabled, print it
        if (enabled) {
            print current_section
        }
        in_section = 0
        current_section = ""
        enabled = 0
    }
}

# Not in a section (header comments, etc.)
!in_section {
    # Only print header lines (comments at the beginning)
    if (NR <= 10 && ($0 ~ /^#/ || $0 ~ /^[[:space:]]*$/)) {
        print $0
    }
}

# Handle end of file
END {
    # If we were in a section and it was enabled, print it
    if (in_section && enabled) {
        print current_section
    }
}
' "$REPO_FILE"
