#!/usr/bin/env bash

# Step 1: Check that we received a renovate.json file path as an argument
if [[ -z "$1" ]]; then
    echo "Error: No renovate.json file path provided"
    exit 1
fi

# Step 2: Check that the file exists
if [[ ! -f "$1" ]]; then
    echo "Error: File $1 does not exist"
    exit 1
fi

# Step 3: Check that jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq could not be found"
    exit 1
fi

# Step 4: Check that sponge is installed
if ! command -v sponge &> /dev/null; then
    echo "Error: sponge could not be found"
    exit 1
fi

# Step 5: Format the file
cat "$1" | jq --indent 4 --sort-keys | sponge "$1"

# Step 6: Print the output
cat "$1"
