#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# set -x

SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

detect_file_type() {
    local file="$1"

    # Check by file extension first
    if [[ "$file" =~ \.(json|jsonl)$ ]]; then
        echo "json"
        return 0
    elif [[ "$file" =~ \.(yaml|yml)$ ]]; then
        echo "yaml"
        return 0
    fi

    # Check by content (first non-whitespace character)
    local first_char
    first_char=$(head -c 1 "$file" 2>/dev/null | tr -d '[:space:]' || echo "")

    if [[ "$first_char" == "{" ]]; then
        echo "json"
    elif [[ "$first_char" == "-" ]] || [[ "$first_char" == "#" ]]; then
        echo "yaml"
    else
        # Default to yaml if we can't determine
        echo "yaml"
    fi
}

check_preconditions() {
    echo "Checking pre-conditions..."

    # Check for required tools based on file type
    local file_type
    file_type=$(detect_file_type "$ARG_CATALOG_FILE")

    if [[ "$file_type" == "json" ]]; then
        command -v jq >/dev/null 2>&1 || { echo "Error: jq is required for JSON files but seems not to be installed." >&2; exit 1; }
    else
        command -v yq >/dev/null 2>&1 || { echo "Error: yq is required for YAML files but seems not to be installed." >&2; exit 1; }
    fi

    echo "Checking pre-conditions completed!"
    return 0
}

parse_args() {
    echo "Parsing args..."

    ARG_CATALOG_FILE=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                usage
                exit
                ;;
            --set-catalog-file)
                if [ -z "$2" ]; then
                    echo "Error: --set-catalog-file requires a file " >&2;
                    exit 1;
                fi

                ARG_CATALOG_FILE=$2
                if [[ ! -f "$ARG_CATALOG_FILE" ]]; then
                    echo "Error: file '$ARG_CATALOG_FILE' does not exist." >&2
                    exit 1
                fi

                shift 2
                ;;
            *)
                echo "Error: unexpected option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    if [ -z "$ARG_CATALOG_FILE" ]; then
        echo "Error: --set-catalog-file is required" >&2
        exit 1
    fi

    echo "Parsing args completed!"
    return 0
}

validate_related_images() {
    echo "Validating related images..."

    local file_type
    file_type=$(detect_file_type "$ARG_CATALOG_FILE")

    # Validate .relatedImages exists and extract images based on file type
    local images_parsed=()

    if [[ "$file_type" == "json" ]]; then
        # For JSON/JSONL files, use jq
        # jq can handle both regular JSON and JSONL (newline-delimited JSON) formats
        # First, check if relatedImages exists in the file
        if ! jq -e 'select(.relatedImages != null) | .relatedImages | type == "array"' "$ARG_CATALOG_FILE" >/dev/null 2>&1; then
            echo "Error: .relatedImages in $ARG_CATALOG_FILE is not a valid array or not found." >&2
            exit 1
        fi

        # Extract images from the JSON object(s) that contain relatedImages
        while IFS= read -r line; do
            if [[ -n "$line" ]] && [[ "$line" != "null" ]]; then
                images_parsed+=("$line")
            fi
        done < <(jq -r 'select(.relatedImages != null) | .relatedImages[]?.image // empty' "$ARG_CATALOG_FILE" 2>/dev/null)
    else
        # For YAML files, use yq
        if ! yq e '.relatedImages | type == "!!seq"' "$ARG_CATALOG_FILE" >/dev/null; then
            echo "Error: .relatedImages in $ARG_CATALOG_FILE is not a valid array." >&2
            exit 1
        fi

        while IFS= read -r line; do
            [[ -n "$line" ]] && images_parsed+=("$line")
        done < <(yq eval -r '.relatedImages | .[] | .image' "$ARG_CATALOG_FILE")
    fi

    entries=${#images_parsed[@]}

    if [[ $entries -eq 0 ]]; then
        echo "Error: No related images found in $ARG_CATALOG_FILE" >&2
        exit 1
    fi

    declare -i i=0
    for ((; i<entries; i++)); do
        local image="${images_parsed[i]}"
        # Only allow production (registry.redhat.io) images
        if [[ "$image" =~ ^registry\.redhat\.io/ ]]; then
            echo "Valid production image found: $image"
        else
            echo "Error: $image is not a valid image reference for production. Check bundle overlay." >&2
            exit 1
        fi
    done

    echo "Validating related images completed!"
    return 0
}


main() {
    parse_args "$@"
    check_preconditions
    validate_related_images
}

usage() {
   cat << EOF
NAME
   $SCRIPT_NAME - check the relatedImages section on a catalog file (JSON or YAML) is suitable for production
SYNOPSIS
   $SCRIPT_NAME --set-catalog-file FILE
EXAMPLES
   - Check the catalog template 'catalog.yaml'
     $ $SCRIPT_NAME --set-catalog-file catalog.yaml
   - Check the catalog JSON file 'catalog.json'
     $ $SCRIPT_NAME --set-catalog-file catalog.json
DESCRIPTION
ARGS
   --set-catalog-file FILE
      Set the catalog file.
   --help
      Display this help and exit.
EOF
}

main "$@"
