#!/usr/bin/env bash
# Validate that bundle image labels and metadata/annotations.yaml match exactly.
#
# Dependencies: podman (or docker via CONTAINER_TOOL), jq, yq
# Optional: skopeo for remote image label inspection without pull (e.g. registry.redhat.io)
#
# Usage: ./konflux-validate-bundle-labels-match-annotations-file.sh <bundle-image>
# Example: ./konflux-validate-bundle-labels-match-annotations-file.sh quay.io/example/topology-aware-lifecycle-manager-bundle-4-22:latest

set -euo pipefail

BUNDLE_IMAGE="${1:?Usage: $0 <bundle-image>}"
CONTAINER_TOOL="${CONTAINER_TOOL:-podman}"
TEMP_DIR=""
CONTAINER_ID=""

cleanup() {
    if [[ -n "$CONTAINER_ID" ]]; then
        $CONTAINER_TOOL rm -f "$CONTAINER_ID" 2>/dev/null || true
    fi
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

echo "Validating bundle image: $BUNDLE_IMAGE"
echo ""

# Extract image labels (JSON) - prefer skopeo for remote images (no pull required)
echo "=== Image labels ==="
IMAGE_LABELS=""
if command -v skopeo &>/dev/null; then
    SKOPEO_JSON=$(skopeo inspect "docker://${BUNDLE_IMAGE}" 2>/dev/null) && \
        IMAGE_LABELS=$(echo "$SKOPEO_JSON" | jq -c '.Labels // .Config.Labels // .config.Labels // {}' 2>/dev/null)
fi
if [[ -z "$IMAGE_LABELS" || "$IMAGE_LABELS" == "null" ]]; then
    IMAGE_LABELS=$($CONTAINER_TOOL inspect "$BUNDLE_IMAGE" --format '{{json .Config.Labels}}' 2>/dev/null) || \
        IMAGE_LABELS=$($CONTAINER_TOOL inspect "$BUNDLE_IMAGE" --format '{{json .Labels}}' 2>/dev/null) || \
        IMAGE_LABELS=""
fi
if [[ -z "$IMAGE_LABELS" || "$IMAGE_LABELS" == "<no value>" || "$IMAGE_LABELS" == "null" ]]; then
    echo "ERROR: Could not extract labels from image."
    echo "  For registry.redhat.io images, ensure you are logged in: $CONTAINER_TOOL login registry.redhat.io"
    echo "  Alternatively install skopeo for remote image inspection without pull."
    exit 1
fi
echo "$IMAGE_LABELS" | jq -r 'to_entries[] | "  \(.key): \(.value)"' 2>/dev/null || echo "$IMAGE_LABELS"
echo ""

# Extract annotations.yaml from image (requires pull for remote images)
TEMP_DIR=$(mktemp -d)
CONTAINER_ID=$($CONTAINER_TOOL create "$BUNDLE_IMAGE" 2>/dev/null) || {
    echo "ERROR: Could not create container from image (pull may have failed)."
    echo "  For registry.redhat.io: $CONTAINER_TOOL login registry.redhat.io"
    exit 1
}
$CONTAINER_TOOL cp "$CONTAINER_ID:/metadata/annotations.yaml" "$TEMP_DIR/annotations.yaml"
$CONTAINER_TOOL rm -f "$CONTAINER_ID" >/dev/null 2>/dev/null
CONTAINER_ID=""

echo "=== metadata/annotations.yaml ==="
cat "$TEMP_DIR/annotations.yaml"
echo ""

# Compare all annotations against image labels
ERRORS=0
CHECKED=0
while IFS= read -r LABEL; do
    [[ -z "$LABEL" ]] && continue
    LABEL_VALUE=$(echo "$IMAGE_LABELS" | jq -r --arg k "$LABEL" '.[$k] // empty')
    ANNOTATION_VALUE=$(yq -r ".annotations[\"$LABEL\"] // \"\"" "$TEMP_DIR/annotations.yaml")

    CHECKED=$((CHECKED + 1))
    if [[ "$LABEL_VALUE" != "$ANNOTATION_VALUE" ]]; then
        echo "MISMATCH: $LABEL"
        echo "  Image label:     '$LABEL_VALUE'"
        echo "  annotations.yaml: '$ANNOTATION_VALUE'"
        ERRORS=$((ERRORS + 1))
    else
        echo "OK: $LABEL = '$LABEL_VALUE'"
        if [[ "$LABEL" == "operators.operatorframework.io.bundle.channels.v1" && "$LABEL_VALUE" == *"alpha"* ]]; then
            echo "  WARNING: channel contains 'alpha' (consider using stable channel)"
        elif [[ "$LABEL" == "operators.operatorframework.io.bundle.channels.default.v1" && "$LABEL_VALUE" == "alpha" ]]; then
            echo "  WARNING: default channel is 'alpha' (consider using stable)"
        fi
    fi
done < <(yq -r '.annotations | keys | .[]' "$TEMP_DIR/annotations.yaml")

echo ""
if [[ $CHECKED -eq 0 ]]; then
    echo "ERROR: No annotations found in metadata/annotations.yaml"
    exit 1
fi
if [[ $ERRORS -gt 0 ]]; then
    echo "Validation FAILED: $ERRORS mismatch(es) of $CHECKED annotation(s)"
    exit 1
fi
echo "Validation PASSED: all $CHECKED annotation(s) match image labels"
