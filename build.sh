#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults — override via environment or flags
IMAGE_NAME="${IMAGE_NAME:-aider-vllm}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-quay.io/danclark}"
CONTAINER_CMD="${CONTAINER_CMD:-}"

usage() {
    cat <<EOF
Build the Aider + vLLM container image.

Usage:
  ./build.sh [OPTIONS]

Options:
  -n, --name NAME        Image name          (default: aider-vllm)
  -t, --tag TAG          Image tag           (default: latest)
  -r, --registry REG     Registry prefix     (e.g. quay.io/myorg)
  -p, --push             Push after building
  -h, --help             Show this help

Environment variables:
  IMAGE_NAME             Same as --name
  IMAGE_TAG              Same as --tag
  REGISTRY               Same as --registry
  CONTAINER_CMD          Force podman or docker (auto-detected if unset)

Examples:
  ./build.sh                                          # local build
  ./build.sh -r quay.io/myorg -p                      # build and push
  ./build.sh -t v1.0.0 -r quay.io/myorg --push        # tagged release
  IMAGE_NAME=my-aider CONTAINER_CMD=docker ./build.sh  # use docker
EOF
    exit 0
}

PUSH=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--name)     IMAGE_NAME="$2"; shift 2 ;;
        -t|--tag)      IMAGE_TAG="$2"; shift 2 ;;
        -r|--registry) REGISTRY="$2"; shift 2 ;;
        -p|--push)     PUSH=true; shift ;;
        -h|--help)     usage ;;
        *)             echo "Unknown option: $1"; usage ;;
    esac
done

# Auto-detect container runtime
if [[ -z "${CONTAINER_CMD}" ]]; then
    if command -v podman &>/dev/null; then
        CONTAINER_CMD="podman"
    elif command -v docker &>/dev/null; then
        CONTAINER_CMD="docker"
    else
        echo "ERROR: Neither podman nor docker found." >&2
        exit 1
    fi
fi

# Build the full image reference
if [[ -n "${REGISTRY}" ]]; then
    REGISTRY="${REGISTRY%/}"
    FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
else
    FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
fi

echo "============================================================"
echo "  Runtime  : ${CONTAINER_CMD}"
echo "  Image    : ${FULL_IMAGE}"
echo "  Context  : ${SCRIPT_DIR}"
echo "============================================================"
echo ""

# Build
${CONTAINER_CMD} build \
    -f "${SCRIPT_DIR}/Containerfile" \
    -t "${FULL_IMAGE}" \
    "${SCRIPT_DIR}"

echo ""
echo "Build complete: ${FULL_IMAGE}"

# Report size
SIZE=$(${CONTAINER_CMD} image inspect "${FULL_IMAGE}" \
    --format '{{.Size}}' 2>/dev/null || true)
if [[ -n "${SIZE}" ]]; then
    SIZE_MB=$(( SIZE / 1024 / 1024 ))
    echo "Image size: ~${SIZE_MB} MB"
fi

# Push if requested
if [[ "${PUSH}" == "true" ]]; then
    if [[ -z "${REGISTRY}" ]]; then
        echo "ERROR: --push requires --registry" >&2
        exit 1
    fi
    echo ""
    echo "Pushing ${FULL_IMAGE} ..."
    ${CONTAINER_CMD} push "${FULL_IMAGE}"
    echo "Push complete."
fi

echo ""
echo "Run locally:"
echo "  ${CONTAINER_CMD} run -it --rm \\"
echo "    -v \$PWD:/work:Z \\"
echo "    -e VLLM_ENDPOINT=http://your-vllm-host:8000 \\"
echo "    ${FULL_IMAGE}"
