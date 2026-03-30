#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# set -x

SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

check_preconditions() {
    echo "Checking pre-conditions..."

    command -v yq >/dev/null 2>&1 || { echo "Error: yq seems not to be installed." >&2; exit 1; }

    echo "Checking pre-conditions completed!"
    return 0
}

parse_args() {
    echo "Parsing args..."

    ARG_TEMPLATE_INPUT_FILE=""
    ARG_TEMPLATE_OUTPUT_FILE=""
    ARG_DEFAULT_CHANNEL=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                usage
                exit
                ;;
            --set-template-file)
                if [ -z "${2:-}" ]; then
                    echo "Error: --set-template-file requires a file." >&2
                    exit 1
                fi

                ARG_TEMPLATE_INPUT_FILE="$2"
                if [[ ! -f "$ARG_TEMPLATE_INPUT_FILE" ]]; then
                    echo "Error: file '$ARG_TEMPLATE_INPUT_FILE' does not exist." >&2
                    exit 1
                fi

                shift 2
                ;;
            --set-template-input-file)
                if [ -z "${2:-}" ]; then
                    echo "Error: --set-template-input-file requires a file." >&2
                    exit 1
                fi

                ARG_TEMPLATE_INPUT_FILE="$2"
                if [[ ! -f "$ARG_TEMPLATE_INPUT_FILE" ]]; then
                    echo "Error: file '$ARG_TEMPLATE_INPUT_FILE' does not exist." >&2
                    exit 1
                fi

                shift 2
                ;;
            --set-template-output-file)
                if [ -z "${2:-}" ]; then
                    echo "Error: --set-template-output-file requires a file." >&2
                    exit 1
                fi

                ARG_TEMPLATE_OUTPUT_FILE="$2"
                shift 2
                ;;
            --set-default-channel)
                if [ -z "${2:-}" ]; then
                    echo "Error: --set-default-channel requires a value." >&2
                    exit 1
                fi

                ARG_DEFAULT_CHANNEL="$2"
                shift 2
                ;;
            *)
                echo "Error: unexpected option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    if [ -z "$ARG_TEMPLATE_INPUT_FILE" ]; then
        echo "Error: --set-template-file or --set-template-input-file is required" >&2
        exit 1
    fi

    if [ -z "$ARG_TEMPLATE_OUTPUT_FILE" ]; then
        ARG_TEMPLATE_OUTPUT_FILE="$ARG_TEMPLATE_INPUT_FILE"
    fi

    echo "Parsing args completed!"
    return 0
}

apply_default_channel_override() {
    if [[ -z "$ARG_DEFAULT_CHANNEL" ]]; then
        return 0
    fi

    local escaped_default_channel
    escaped_default_channel="$(printf '%s' "$ARG_DEFAULT_CHANNEL" | sed 's/[\/&]/\\&/g')"

    local tmp_output
    tmp_output="$(mktemp)"
    sed 's|\${default_channel}|'"$escaped_default_channel"'|g' "$ARG_TEMPLATE_OUTPUT_FILE" > "$tmp_output"
    mv "$tmp_output" "$ARG_TEMPLATE_OUTPUT_FILE"

    echo "Applied default channel override: $ARG_DEFAULT_CHANNEL"
    return 0
}

validate_template_file() {
    echo "Validating resources template input file..."

    if ! yq e -e '.resources | type == "!!seq"' "$ARG_TEMPLATE_INPUT_FILE" >/dev/null 2>&1; then
        echo "Error: .resources in $ARG_TEMPLATE_INPUT_FILE is not a valid array." >&2
        exit 1
    fi

    local resources_count
    resources_count=$(yq e '.resources | length' "$ARG_TEMPLATE_INPUT_FILE")
    if [[ "$resources_count" -eq 0 ]]; then
        echo "Error: .resources in $ARG_TEMPLATE_INPUT_FILE is empty." >&2
        exit 1
    fi

    echo "Validating resources template input file completed!"
    return 0
}

resolve_resource_path() {
    local resource="$1"
    local template_dir="$2"

    if [[ "$resource" = /* ]]; then
        printf '%s\n' "$resource"
    else
        printf '%s\n' "$template_dir/$resource"
    fi
}

build_catalog_file() {
    echo "Building catalog output file..."

    local template_dir
    template_dir="$(dirname "$ARG_TEMPLATE_INPUT_FILE")"

    local temp_resources_list
    temp_resources_list="$(mktemp)"
    trap 'rm -f "${temp_resources_list:-}"' EXIT

    local resource
    while IFS= read -r resource; do
        if [[ -z "$resource" || "$resource" == "null" ]]; then
            echo "Error: found an empty/null resource path in $ARG_TEMPLATE_INPUT_FILE." >&2
            exit 1
        fi

        local resolved_resource
        resolved_resource="$(resolve_resource_path "$resource" "$template_dir")"
        if [[ ! -f "$resolved_resource" ]]; then
            echo "Error: resource file '$resolved_resource' does not exist." >&2
            exit 1
        fi

        if yq e -e '.entries | type == "!!seq"' "$resolved_resource" >/dev/null 2>&1; then
            :
        elif yq e -e 'type == "!!seq"' "$resolved_resource" >/dev/null 2>&1; then
            :
        else
            echo "Error: resource file '$resolved_resource' must be either a YAML sequence or contain an .entries array." >&2
            exit 1
        fi

        printf '%s\n' "$resolved_resource" >> "$temp_resources_list"
    done < <(yq e -r '.resources[]' "$ARG_TEMPLATE_INPUT_FILE")

    local resources_count
    resources_count=$(wc -l < "$temp_resources_list")
    if [[ "$resources_count" -eq 0 ]]; then
        echo "Error: no valid resource files resolved from $ARG_TEMPLATE_INPUT_FILE." >&2
        exit 1
    fi

    local final_schema
    final_schema="$(yq e -r '.schema // ""' "$ARG_TEMPLATE_INPUT_FILE")"
    if [[ -z "$final_schema" || "$final_schema" == "null" ]]; then
        final_schema="olm.template.basic"
    fi

    yq e -n '.entries = [] | .schema = ""' > "$ARG_TEMPLATE_OUTPUT_FILE"
    yq e -i ".schema = \"$final_schema\"" "$ARG_TEMPLATE_OUTPUT_FILE"

    local current_resource
    while IFS= read -r current_resource; do
        if yq e -e 'type == "!!seq"' "$current_resource" >/dev/null 2>&1; then
            yq ea -i '
                select(fileIndex == 0).entries += select(fileIndex == 1) |
                select(fileIndex == 0)
            ' "$ARG_TEMPLATE_OUTPUT_FILE" "$current_resource"
        else
            yq ea -i '
                select(fileIndex == 0).entries += select(fileIndex == 1).entries |
                select(fileIndex == 0)
            ' "$ARG_TEMPLATE_OUTPUT_FILE" "$current_resource"
        fi
    done < "$temp_resources_list"

    apply_default_channel_override

    echo "Built catalog output file: $ARG_TEMPLATE_OUTPUT_FILE using $resources_count resource file(s)."
    echo "Building catalog output file completed!"
    return 0
}

main() {
    check_preconditions
    parse_args "$@"
    validate_template_file
    build_catalog_file
}

usage() {
   cat << EOF
NAME
   $SCRIPT_NAME - build a catalog YAML from a resources template file
SYNOPSIS
   $SCRIPT_NAME --set-template-file FILE
   $SCRIPT_NAME --set-template-input-file FILE --set-template-output-file FILE
   $SCRIPT_NAME --set-template-input-file FILE --set-template-output-file FILE --set-default-channel CHANNEL
EXAMPLES
   - Build in place (backward compatibility style):
     $ $SCRIPT_NAME --set-template-file openshift-4-20-template.in.yaml
   - Build using separate input and output files:
     $ $SCRIPT_NAME --set-template-input-file openshift-4-20-template.in.yaml --set-template-output-file openshift-4-20.yaml
   - Build and replace \${default_channel} placeholder:
     $ $SCRIPT_NAME --set-template-input-file openshift-4-20-template.in.yaml --set-template-output-file openshift-4-20.yaml --set-default-channel pre-ga-0.2
DESCRIPTION
   The input template must contain a .resources array with YAML file paths.
   Each referenced file must either:
     - contain an .entries array, or
     - be a YAML sequence (treated as entries directly).
   The script concatenates all entries in order and writes a final YAML:
     entries: [...]
     schema: olm.template.basic (or .schema from input template if present)
ARGS
   --set-template-file FILE
      Set the resources template file (input and output, for in-place update).
   --set-template-input-file FILE
      Set the input resources template file.
   --set-template-output-file FILE
      Set the output catalog file.
   --set-default-channel CHANNEL
      Replace all \${default_channel} placeholders in the generated output with CHANNEL.
   --help
      Display this help and exit.
EOF
}

main "$@"
