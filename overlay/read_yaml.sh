#!/usr/bin/env bash

# Usage example:
# . read_yaml.sh; read_yaml_variables "variables.yaml"

read_yaml_variables() {
    local yaml_file="$1"

    if [[ ! -f "$yaml_file" ]]; then
        echo "Error: YAML file '$yaml_file' not found." >&2
        exit 1
    fi

    # Array of variable names to read
    local variables=("display_name" "description" "version" "name" "name_version" "manager" "skip_range" "replaces" "min_kube_version")

    # Read each variable
    for var in "${variables[@]}"; do
        has_var=$(yq "has(\"$var\")" "$yaml_file")
        echo $has_var
        sleep 2
        if [[ $has_var == "true" ]]; then
            value=$(yq e ".$var" "$yaml_file")
            echo "Read $var: $value"
            local  "$var=$value"
        else
            echo "Warning: $var not set in $yaml_file" >&2
            # declare -g "$var="
        fi
    done

    echo "display name: $display_name"
    # [[ -n "$display_name" ]] && echo "Using display_name: $display_name"
    # [[ ! -v "$display_name" ]] && echo "display name is NOT declared"

    # this checks it has not been declared not to apply any logic
    if [[ -v "display_name" ]]; then
        echo "display name is declared"
    fi

    echo "fin2"
}

