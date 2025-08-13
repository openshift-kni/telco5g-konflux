#!/usr/bin/env bash

# Step 1: Check that we received a renovate.json file path as an argument
if [[ -z "$1" ]]; then
    echo "Error: No renovate.json file path provided"
    exit 1
fi

# Step 2: Check that we received a renovate version as an argument
if [[ -z "$2" ]]; then
    echo "Error: No renovate version provided"
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

# Step 4: Check that the file is a valid JSON file
if ! jq . "$1" > /dev/null 2>&1; then
    echo "Error: File $1 is not a valid JSON file"
    exit 1
fi

# Step 5: Check if npx is installed
if ! command -v npx &> /dev/null; then
    echo "Error: npx could not be found"
    exit 1
fi

# Step 6: Run npx renovate-config-validator
output=$(npx --yes --package "renovate@$2" -- renovate-config-validator "$1")

# Step 7: Check the output
if [[ -z "$output" ]]; then
    echo "ERROR: Output is empty"
    exit 1
fi

# Step 8: Print the output
echo "$output"

# Step 9: If the output contains errors, exit with an error code
if [[ "$output" == *"ERROR"* ]]; then
    echo "ERROR: Output contains errors"
    exit 1
fi

# Step 10: If the output contains warnings, print the warnings
if [[ "$output" == *"WARN"* ]]; then
    echo "WARNING: Output contains warnings"
fi
