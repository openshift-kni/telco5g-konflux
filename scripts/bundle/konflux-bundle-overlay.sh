#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# set -x
# Debug mode off by default
DEBUG=false

SCRIPT_NAME=$(basename "$(readlink -f "${BASH_SOURCE[0]}")")

MAP_STAGING="staging"
MAP_PRODUCTION="production"
MANAGER_KEY="manager"

# release yaml variables allowed
declare -A RELEASE_VARIABLES_ALLOWED=(
    ["annotations"]=true
    ["alm_examples"]=true
    ["containerImage"]=true
    ["description"]=true
    ["display_name"]=true
    ["manager_version"]=true
    ["min_kube_version"]=true
    ["recert_image"]=true
    ["subscription_badges"]=true
    ["version"]=true
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

    for image_name in "${!IMAGE_TO_SOURCE[@]}"; do
        print_log "Replacing: image_name: $image_name, source: ${IMAGE_TO_SOURCE[$image_name]}, target: ${IMAGE_TO_TARGET[$image_name]}"
        sed -i "s,${IMAGE_TO_SOURCE[$image_name]},${IMAGE_TO_TARGET[$image_name]},g" "$ARG_CSV_FILE"
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
    declare -i index=0
    for image_name in "${!IMAGE_TO_SOURCE[@]}"; do
        print_log "Adding related image: name: $image_name source: ${IMAGE_TO_SOURCE[$image_name]}, image: ${IMAGE_TO_TARGET[$image_name]}"
        yq e -i ".spec.relatedImages[$index].name=\"$image_name\" |
                .spec.relatedImages[$index].image=\"${IMAGE_TO_TARGET[$image_name]}\"" "$ARG_CSV_FILE"
        index=$((index + 1))
    done

    print_log "Adding related images completed!"
    return 0
}

parse_mapping_images_file() {
    print_log "Parsing mapping image file..."

    # Extract keys and images using mapfile/readarray for better shellcheck compliance
    local keys staging_images production_images
    mapfile -t keys < <(yq eval '.[].key' "$ARG_MAPPING_FILE")
    mapfile -t staging_images < <(yq eval '.[].staging' "$ARG_MAPPING_FILE")
    mapfile -t production_images < <(yq eval '.[].production' "$ARG_MAPPING_FILE")
    local entries=${#keys[@]}

    # Declare associative arrays
    declare -gA IMAGE_TO_STAGING=()
    declare -gA IMAGE_TO_PRODUCTION=()

    declare -i i=0
    for ((; i<entries; i++)); do
        # Store in associative arrays
        local key=${keys[i]}
        IMAGE_TO_STAGING["$key"]="${staging_images[i]}"
        IMAGE_TO_PRODUCTION["$key"]="${production_images[i]}"
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

    for image_name in "${!IMAGE_TO_TARGET[@]}"; do
        local image_name_target="${IMAGE_TO_TARGET[$image_name]}"

        # requires an image already pinned, sha256 format: '...@sha256:..."
        local image_name_target_trimmed="${image_name_target%@*}"

        local image_name_target_trimmed_mapped=""
        if [[ "$ARG_MAP" == "$MAP_STAGING" ]]; then
            if [[ -z "${IMAGE_TO_STAGING[$image_name]-}" ]]; then
                print_log "Warning: no staging image mapped for: $image_name" >&2
                continue
            fi

            image_name_target_trimmed_mapped="${IMAGE_TO_STAGING[$image_name]}"

        elif [[ "$ARG_MAP" == "$MAP_PRODUCTION" ]]; then
            if [[ -z "${IMAGE_TO_PRODUCTION[$image_name]-}" ]]; then
                print_log "Warning: no production image mapped for: $image_name" >&2
                continue
            fi

            image_name_target_trimmed_mapped="${IMAGE_TO_PRODUCTION[$image_name]}"

        fi

        print_log "Replacing: image_name: $image_name, original: $image_name_target_trimmed, mapped: $image_name_target_trimmed_mapped"
        sed -i "s,$image_name_target_trimmed,$image_name_target_trimmed_mapped,g" "$ARG_CSV_FILE"
    done

    print_log "Mapping images completed!"
}

parse_pinning_images_file() {
    print_log "Parsing pinning file..."

    if [[ ! -f "$ARG_PINNING_FILE" ]]; then
        print_log "Error: File '$ARG_PINNING_FILE' not found. " >&2
        exit 1
    fi

    # Extract keys and images using mapfile/readarray for better shellcheck compliance
    local keys sources targets
    mapfile -t keys < <(yq eval '.[].key' "$ARG_PINNING_FILE")
    mapfile -t sources < <(yq eval '.[].source' "$ARG_PINNING_FILE")
    mapfile -t targets < <(yq eval '.[].target' "$ARG_PINNING_FILE")
    local entries=${#keys[@]}

    # Declare associative arrays
    declare -gA IMAGE_TO_SOURCE=()
    declare -gA IMAGE_TO_TARGET=()

    declare -i i=0
    for ((; i<entries; i++)); do
        # Store in associative arrays
        local key=${keys[i]}
        IMAGE_TO_SOURCE["$key"]="${sources[i]}"
        IMAGE_TO_TARGET["$key"]="${targets[i]}"
    done

    if [ "$DEBUG" = true ]; then
        for key in "${!IMAGE_TO_SOURCE[@]}"; do
            print_log "- key: $key"
            print_log "  source: ${IMAGE_TO_SOURCE[$key]}"
            print_log "  target: ${IMAGE_TO_TARGET[$key]}"
        done
    fi

    print_log "Parsing pinning file completed!"
    return 0
}

parse_args() {
    print_log "Parsing args..."

    # command line options
    local options=
    local long_options="set-pinning-file:,set-mapping-file:,set-release-file:,set-csv-file:,set-mapping-staging,set-mapping-production,help"

    local parsed
    parsed=$(getopt --options="$options" --longoptions="$long_options" --name "$SCRIPT_NAME" -- "$@")
    eval set -- "$parsed"

    local map_staging=0
    local map_production=0
    declare -g ARG_MAPPING_FILE=""
    declare -g ARG_PINNING_FILE=""
    declare -g ARG_CSV_FILE=""
    declare -g ARG_MAP=""
    declare -g ARG_RELEASE_FILE=""

    while true; do
        case $1 in
            --help)
                usage
                exit 0
                ;;
            --set-csv-file)
                ARG_CSV_FILE=$2
                shift 2
                ;;
            --set-pinning-file)
                ARG_PINNING_FILE=$2
                shift 2
                ;;
            --set-mapping-file)
                ARG_MAPPING_FILE=$2
                shift 2
                ;;
            --set-mapping-staging)
                map_staging=1
                ARG_MAP=$MAP_STAGING
                shift 1
                ;;
            --set-mapping-production)
                map_production=1
                ARG_MAP=$MAP_PRODUCTION
                shift 1
                ;;
            --set-release-file)
                ARG_RELEASE_FILE=$2
                shift 2
                ;;
            --)
                shift
                break
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
    declare -gA RELEASE_VARIABLES_CONFIGURED

    # compose RELEASE_VARIABLES_CONFIGURED
    local var_keys
    var_keys=$(yq e '.variables | keys | .[]' "$ARG_RELEASE_FILE")

    while IFS= read -r var; do
        if [[ -n "$var" ]]; then
            # Get the value for this variable
            local value
            value=$(yq e ".variables.$var" "$ARG_RELEASE_FILE")

            # Check if the variable is allowed
            if [[ -z "${RELEASE_VARIABLES_ALLOWED[$var]+_}" ]]; then
                print_log "Error: Variable '$var' is not allowed in $ARG_RELEASE_FILE" >&2
                exit 1
            else
                # Store in associative array
                RELEASE_VARIABLES_CONFIGURED["$var"]="$value"
            fi

            print_log_debug "RELEASE_VARIABLES_CONFIGURED, key: $var, value: $value"
        fi
    done <<< "$var_keys"

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

    for key in "${!RELEASE_VARIABLES_CONFIGURED[@]}"; do
        local value=${RELEASE_VARIABLES_CONFIGURED[$key]}
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
                    value=${IMAGE_TO_TARGET["$MANAGER_KEY"]:-}
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
                    value=${IMAGE_TO_TARGET["$key"]:-}
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
    done

    print_log "Overlaying release completed!"
    return 0
}

main() {
    check_preconditions
    parse_args "$@"
    parse_pinning_images_file
    pin_images
    add_related_images
    overlay_release
    map_images    # this MUST always be the last action
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
