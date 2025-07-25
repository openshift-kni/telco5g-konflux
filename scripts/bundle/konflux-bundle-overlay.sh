#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# set -x
# Debug mode off by default
DEBUG=false

SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

MAP_STAGING="staging"
MAP_PRODUCTION="production"
MANAGER_KEY="manager"

# release yaml variables allowed
RELEASE_VARIABLES_ALLOWED=(
    "annotations"
    "alm_examples"
    "containerImage"
    "description"
    "display_name"
    "manager_version"
    "min_kube_version"
    "recert_image"
    "subscription_badges"
    "version"
)

print_log() {
    echo "[$SCRIPT_NAME] $1"
}

print_log_debug() {
    if [ "$DEBUG" = true ]; then
        print_log "[DEBUG] $1"
    fi
}

check_preconditions() {
    print_log "Checking pre-conditions..."

    # yq must be installed
    command -v yq >/dev/null 2>&1 || { print_log "Error: yq seems not to be installed." >&2; exit 1; }
    print_log "Checking pre-conditions completed!"
    return 0
}

pin_images() {
    print_log "Pinning images (sha256)..."

    local i=0
    for image_name in "${IMAGE_TO_SOURCE_KEYS[@]}"; do
        local source_image="${IMAGE_TO_SOURCE_VALUES[$i]}"
        local target_image="${IMAGE_TO_TARGET_VALUES[$i]}"
        print_log "Replacing: image_name: $image_name, source: $source_image, target: $target_image"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s,$source_image,$target_image,g" "$ARG_CSV_FILE"
        else
            sed -i "s,$source_image,$target_image,g" "$ARG_CSV_FILE"
        fi
        i=$((i + 1))
    done

    print_log "Pinning images completed!"
    return 0
}

add_related_images() {
    print_log "Adding related images..."

    # remove the existing section
    print_log "Removing .spec.relatedImages"
    yq e -i 'del(.spec.relatedImages)' "$ARG_CSV_FILE"

    # create a new section from scratch
    local i=0
    for image_name in "${IMAGE_TO_SOURCE_KEYS[@]}"; do
        local source_image="${IMAGE_TO_SOURCE_VALUES[$i]}"
        local target_image="${IMAGE_TO_TARGET_VALUES[$i]}"
        print_log "Adding related image: name: $image_name source: $source_image, image: $target_image"
        yq e -i ".spec.relatedImages[$i].name=\"$image_name\" | .spec.relatedImages[$i].image=\"$target_image\"" "$ARG_CSV_FILE"
        i=$((i + 1))
    done

    print_log "Adding related images completed!"
    return 0
}

parse_mapping_images_file() {
    print_log "Parsing mapping image file..."

    # Extract keys and images using a loop for portability
    local keys staging_images production_images
    keys=()
    staging_images=()
    production_images=()

    # Read arrays line by line using a more portable approach
    while IFS= read -r line; do
        [[ -n "$line" ]] && keys+=("$line")
    done < <(yq eval '.[].key' "$ARG_MAPPING_FILE")

    while IFS= read -r line; do
        [[ -n "$line" ]] && staging_images+=("$line")
    done < <(yq eval '.[].staging' "$ARG_MAPPING_FILE")

    while IFS= read -r line; do
        [[ -n "$line" ]] && production_images+=("$line")
    done < <(yq eval '.[].production' "$ARG_MAPPING_FILE")

    local entries=${#keys[@]}

    # Use indexed arrays to simulate associative arrays for portability
    IMAGE_TO_STAGING_KEYS=()
    IMAGE_TO_STAGING_VALUES=()
    IMAGE_TO_PRODUCTION_KEYS=()
    IMAGE_TO_PRODUCTION_VALUES=()

    local i=0
    for ((; i<entries; i++)); do
        local key="${keys[i]}"
        IMAGE_TO_STAGING_KEYS+=("$key")
        IMAGE_TO_STAGING_VALUES+=("${staging_images[i]}")
        IMAGE_TO_PRODUCTION_KEYS+=("$key")
        IMAGE_TO_PRODUCTION_VALUES+=("${production_images[i]}")
    done

    print_log "Parsing mapping image file completed!"
    return 0
}

map_images() {

    if [[ ! -f "$ARG_MAPPING_FILE" ]]; then
        print_log "Skipping images mapping!"
        return 0
    fi

    print_log "Mapping images ..."

    parse_mapping_images_file

    local i=0
    for image_name in "${IMAGE_TO_TARGET_KEYS[@]}"; do
        local image_name_target="${IMAGE_TO_TARGET_VALUES[$i]}"

        # requires an image already pinned, sha256 format: '...@sha256:..."
        local image_name_target_trimmed="${image_name_target%@*}"

        local image_name_target_trimmed_mapped=""
        if [[ "$ARG_MAP" == "$MAP_STAGING" ]]; then
            local j=0
            for key in "${IMAGE_TO_STAGING_KEYS[@]}"; do
                if [[ "$key" == "$image_name" ]]; then
                    image_name_target_trimmed_mapped="${IMAGE_TO_STAGING_VALUES[$j]}"
                    break
                fi
                j=$((j + 1))
            done

            if [[ -z "$image_name_target_trimmed_mapped" ]]; then
                print_log "Warning: no staging image mapped for: $image_name" >&2
                i=$((i + 1))
                continue
            fi

        elif [[ "$ARG_MAP" == "$MAP_PRODUCTION" ]]; then
            local j=0
            for key in "${IMAGE_TO_PRODUCTION_KEYS[@]}"; do
                if [[ "$key" == "$image_name" ]]; then
                    image_name_target_trimmed_mapped="${IMAGE_TO_PRODUCTION_VALUES[$j]}"
                    break
                fi
                j=$((j + 1))
            done

            if [[ -z "$image_name_target_trimmed_mapped" ]]; then
                print_log "Warning: no production image mapped for: $image_name" >&2
                i=$((i + 1))
                continue
            fi
        fi

        print_log "Replacing: image_name: $image_name, original: $image_name_target_trimmed, mapped: $image_name_target_trimmed_mapped"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s,$image_name_target_trimmed,$image_name_target_trimmed_mapped,g" "$ARG_CSV_FILE"
        else
            sed -i "s,$image_name_target_trimmed,$image_name_target_trimmed_mapped,g" "$ARG_CSV_FILE"
        fi
        i=$((i + 1))
    done

    print_log "Mapping images completed!"
}

parse_pinning_images_file() {
    local ARG_PINNING_FILE="$1"
    print_log "Parsing pinning file..."

    if [[ ! -f "$ARG_PINNING_FILE" ]]; then
        print_log "Error: File '$ARG_PINNING_FILE' not found. " >&2
        exit 1
    fi

    # Extract keys and images using a loop for portability
    local keys sources targets
    keys=()
    sources=()
    targets=()

    # Read arrays line by line using a more portable approach
    while IFS= read -r line; do
        [[ -n "$line" ]] && keys+=("$line")
    done < <(yq eval '.[].key' "$ARG_PINNING_FILE")

    while IFS= read -r line; do
        [[ -n "$line" ]] && sources+=("$line")
    done < <(yq eval '.[].source' "$ARG_PINNING_FILE")

    while IFS= read -r line; do
        [[ -n "$line" ]] && targets+=("$line")
    done < <(yq eval '.[].target' "$ARG_PINNING_FILE")

    local entries=${#keys[@]}

    # Use indexed arrays to simulate associative arrays for portability
    IMAGE_TO_SOURCE_KEYS=()
    IMAGE_TO_SOURCE_VALUES=()
    IMAGE_TO_TARGET_KEYS=()
    IMAGE_TO_TARGET_VALUES=()

    local i=0
    for ((; i<entries; i++)); do
        local key="${keys[i]}"
        IMAGE_TO_SOURCE_KEYS+=("$key")
        IMAGE_TO_SOURCE_VALUES+=("${sources[i]}")
        IMAGE_TO_TARGET_KEYS+=("$key")
        IMAGE_TO_TARGET_VALUES+=("${targets[i]}")
    done

    if [ "$DEBUG" = true ]; then
        local i=0
        for key in "${IMAGE_TO_SOURCE_KEYS[@]}"; do
            print_log "- key: $key"
            print_log "  source: ${IMAGE_TO_SOURCE_VALUES[$i]}"
            print_log "  target: ${IMAGE_TO_TARGET_VALUES[$i]}"
            i=$((i + 1))
        done
    fi

    print_log "Parsing pinning file completed!"
    return 0
}


# Global variables for script arguments
ARG_MAPPING_FILE=""
ARG_PINNING_FILE=""
ARG_CSV_FILE=""
ARG_MAP=""
ARG_RELEASE_FILE=""

parse_args() {
    print_log "Parsing args..."

    local map_staging=0
    local map_production=0

    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                usage
                exit 0
                ;;
            --set-csv-file)
                ARG_CSV_FILE="$2"
                shift
                shift
                ;;
            --set-pinning-file)
                ARG_PINNING_FILE="$2"
                shift
                shift
                ;;
            --set-mapping-file)
                ARG_MAPPING_FILE="$2"
                shift
                shift
                ;;
            --set-mapping-staging)
                map_staging=1
                ARG_MAP=$MAP_STAGING
                shift
                ;;
            --set-mapping-production)
                map_production=1
                ARG_MAP=$MAP_PRODUCTION
                shift
                ;;
            --set-release-file)
                ARG_RELEASE_FILE="$2"
                shift
                shift
                ;;
            *)
                print_log "Error: unexpected option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    # validate images file
    if [[ -n "$ARG_PINNING_FILE" && ! -f "$ARG_PINNING_FILE" ]]; then
        print_log "Error: file '$ARG_PINNING_FILE' does not exist." >&2
        exit 1
    fi

    # validate release file
    if [[ -n "$ARG_RELEASE_FILE" && ! -f "$ARG_RELEASE_FILE" ]]; then
        print_log "Error: file '$ARG_RELEASE_FILE' does not exist." >&2
        exit 1
    fi

    # validate csv file
    if [[ -n "$ARG_CSV_FILE" && ! -f "$ARG_CSV_FILE" ]]; then
        print_log "Error: file '$ARG_CSV_FILE' does not exist." >&2
        exit 1
    fi

    # validate map options
    if [[ $map_staging -eq 1 && $map_production -eq 1 ]]; then
        print_log "Error: cannot specify both '--set-mapping-staging' and '--set-mapping-production'." >&2
        exit 1
    fi

    if [[ $map_staging -eq 1 || $map_production -eq 1 ]]; then
        if [[ -z "$ARG_MAPPING_FILE" ]]; then
            print_log "Error: specify '--set-mapping-file' to use a container registry map file." >&2
            exit 1
        fi

        if [[ ! -f "$ARG_MAPPING_FILE" ]]; then
            print_log "Error: file '$ARG_MAPPING_FILE' does not exist." >&2
            exit 1
        fi
    fi

    if [[ -n "$ARG_MAPPING_FILE" ]]; then
        if [[ $map_staging -eq 0 && $map_production -eq 0 ]]; then
            print_log "Error: specify '--set-mapping-staging' or '--set-mapping-production'." >&2
            exit 1
        fi
    fi

    print_log "Parsing args completed!"
}

parse_release_file()
{
    print_log "Parsing release file..."

    # release yaml variables configured
    RELEASE_VARIABLES_CONFIGURED_KEYS=()
    RELEASE_VARIABLES_CONFIGURED_VALUES=()

    # compose RELEASE_VARIABLES_CONFIGURED
    local var_keys
    var_keys=()

    # Read array line by line using a more portable approach
    while IFS= read -r line; do
        [[ -n "$line" ]] && var_keys+=("$line")
    done < <(yq e '.variables | keys | .[]' "$ARG_RELEASE_FILE")

    for var in "${var_keys[@]}"; do
        if [[ -n "$var" ]]; then
            # Get the value for this variable
            local value
            value=$(yq e ".variables.$var" "$ARG_RELEASE_FILE")

            # Check if the variable is allowed
            local allowed=false
            for allowed_key in "${RELEASE_VARIABLES_ALLOWED[@]}"; do
                if [[ "$allowed_key" == "$var" ]]; then
                    allowed=true
                    break
                fi
            done

            if [[ "$allowed" == "false" ]]; then
                print_log "Error: Variable '$var' is not allowed in $ARG_RELEASE_FILE" >&2
                exit 1
            else
                # Store in indexed arrays
                RELEASE_VARIABLES_CONFIGURED_KEYS+=("$var")
                RELEASE_VARIABLES_CONFIGURED_VALUES+=("$value")
            fi

            print_log_debug "RELEASE_VARIABLES_CONFIGURED, key: $var, value: $value"
        fi
    done

    print_log "Parsing release file completed!"
    return 0
}

overlay_release()
{
    if [[ ! -f "$ARG_RELEASE_FILE" ]]; then
        print_log "Skipping release overlay!"
        return 0
    fi
    parse_release_file

    print_log "Overlaying release..."

    # remove  the  existing  'skip_range' and 'replaces' from  the  upstream csv:
    # the new values won't be applied by this overlay but managed via the catalog
    # template (catalog-template.in.yaml)
    print_log "Removing '.spec.replaces' and '.metadata.annotations[\"olm.skipRange\"]'"
    yq e -i 'del(.spec.replaces)' "$ARG_CSV_FILE"
    yq e -i 'del(.metadata.annotations["olm.skipRange"])' "$ARG_CSV_FILE"

    local i=0
    for key in "${RELEASE_VARIABLES_CONFIGURED_KEYS[@]}"; do
        local value="${RELEASE_VARIABLES_CONFIGURED_VALUES[$i]}"
        local value_error=0

        print_log_debug "RELEASE_VARIABLES_CONFIGURED, Key: $key, Value: $value"

        case "$key" in
            "alm_examples")
                VALUE_ENV=$value yq e -i '.metadata.annotations["alm-examples"] = strenv(VALUE_ENV)' "$ARG_CSV_FILE" || value_error=1
                ;;
            "annotations")
                yq e -i ".metadata.annotations += load(\"/dev/stdin\")" "$ARG_CSV_FILE" <<< "$value" || value_error=1
                ;;
            "containerImage")
                if [[ "$value" == PLACEHOLDER_CONTAINER_IMAGE ]]; then
                    local j=0
                    for image_key in "${IMAGE_TO_TARGET_KEYS[@]}"; do
                        if [[ "$image_key" == "$MANAGER_KEY" ]]; then
                            value="${IMAGE_TO_TARGET_VALUES[$j]}"
                            break
                        fi
                        j=$((j + 1))
                    done
                    if [[ -z "$value" ]]; then
                        print_log "Error: no manager image pinned for key: $MANAGER_KEY. Check the pinning file: $ARG_PINNING_FILE" >&2
                        value_error=1
                    fi
                fi

                if [[ $value_error == 0 ]]; then
                    VALUE_ENV=$value yq e -i '.metadata.annotations["containerImage"] = strenv(VALUE_ENV)' "$ARG_CSV_FILE" || value_error=1
                fi
                ;;
            "description")
                VALUE_ENV=$value yq e -i '.spec.description = strenv(VALUE_ENV) | .spec.description style="literal"' "$ARG_CSV_FILE" || value_error=1
                ;;
            "display_name")
                VALUE_ENV=$value yq e -i '.spec.displayName = strenv(VALUE_ENV)' "$ARG_CSV_FILE" || value_error=1
                ;;
            "manager_version")
                VALUE_ENV=$value yq e -i '.metadata.name = strenv(VALUE_ENV)' "$ARG_CSV_FILE" || value_error=1
                ;;
            "subscription_badges")
                VALUE_ENV=$value yq e -i '.metadata.annotations["operators.openshift.io/valid-subscription"] = strenv(VALUE_ENV)' "$ARG_CSV_FILE" || value_error=1
                ;;
            "version")
                VALUE_ENV=$value yq e -i '.spec.version = strenv(VALUE_ENV)' "$ARG_CSV_FILE" || value_error=1
                ;;
            "min_kube_version")
                VALUE_ENV=$value yq e -i '.spec.minKubeVersion = strenv(VALUE_ENV)' "$ARG_CSV_FILE" || value_error=1
                ;;
            "recert_image")
                if [[ "$value" == PLACEHOLDER_RECERT_IMAGE ]]; then
                    local j=0
                    for image_key in "${IMAGE_TO_TARGET_KEYS[@]}"; do
                        if [[ "$image_key" == "$key" ]]; then
                            value="${IMAGE_TO_TARGET_VALUES[$j]}"
                            break
                        fi
                        j=$((j + 1))
                    done
                    if [[ -z "$value" ]]; then
                        print_log "Error: no recert image pinned for key: $key. Check the pinning file: $ARG_PINNING_FILE" >&2
                        value_error=1
                    fi
                fi

                if [[ $value_error == 0 ]]; then
                    VALUE_ENV=$value yq e -i '.spec.install.spec.deployments[0].spec.template.spec.containers[0].env += {"name": "RELATED_IMAGE_RECERT_IMAGE", "value": "'"$value"'"}' "$ARG_CSV_FILE" || value_error=1
                fi
                ;;
            *)
                print_log "Error: no yq handler defined for release variable: $key" >&2
                value_error=1
                ;;
            esac

        if [[ $value_error -ne 0 ]]; then
            print_log "Error: failed to set release variable: $key with value: $value on $ARG_CSV_FILE" >&2
            exit 1
        fi
        i=$((i + 1))
    done

    print_log "Overlaying release completed!"
    return 0
}

# Sort YAML keys for consistent output
sort_yaml_keys() {
    print_log "Sorting YAML keys for consistent output..."

    # Create a temporary file for the sorted output
    local temp_file
    temp_file=$(mktemp)

    # Sort keys recursively at all levels and maintain formatting
    if yq e -P '.. |= sort_keys(.)' "$ARG_CSV_FILE" > "$temp_file"; then
        mv "$temp_file" "$ARG_CSV_FILE"
        print_log "YAML keys sorted successfully!"
    else
        print_log "Warning: Failed to sort YAML keys, continuing with unsorted output" >&2
        rm -f "$temp_file"
    fi

    return 0
}

main() {
    check_preconditions
    parse_args "$@"
    parse_pinning_images_file "$ARG_PINNING_FILE"
    pin_images
    add_related_images
    overlay_release
    map_images    # mapping images must be done before sorting
    sort_yaml_keys    # this MUST always be the final action for consistent output
}

usage() {
   cat << EOF
NAME

   $SCRIPT_NAME - overlay operator csv

SYNOPSIS

   $SCRIPT_NAME --set-pinning-file FILE [--set-mapping-file FILE (--set-mapping-staging|--set-mapping-production)] [--set-release-file FILE] --set-csv-file FILE

EXAMPLES

   - Pin (sha256) images on 'oran-o2ims.clusterserviceversion.yaml' as per the configuration on 'pin_images.in.yaml',
     map them to the production registry according to the configuration on 'map_images.in.yaml' and overlay the release
     according to the configuration on 'release.in.yaml':

     $ $SCRIPT_NAME --set-pinning-file pin_images.in.yaml --set-mapping-file map_images.in.yaml --set-mapping-production --set-release-file release.in.yaml --set-csv-file oran-o2ims.clusterserviceversion.yaml

DESCRIPTION

   overlay operator csv

ARGS

   --set-pinning-file FILE
      Set the pinning file to pin image refs to sha256

   --set-mapping-file FILE
      Set the mapping file to map image refs to another container registry

      When used, it must be accompanied by either:

        --set-mapping-staging    map to 'registry.stage.redhat.io'
        --set-mapping-production map to 'registry.redhat.io'

   --set-release-file FILE
      Set the release file for the overlay

   --set-csv-file FILE
      Set the cluster service version file

   --help
      Display this help and exit

EOF
}

main "$@"
