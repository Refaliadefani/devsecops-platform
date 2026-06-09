#!/bin/bash
# ==============================================================================
# Docker Build Helper Script
# ==============================================================================
# Builds a Docker image with standardized labels and build arguments.
# Usage: ./docker-build.sh <image-name> <image-tag> [dockerfile] [context]
# ==============================================================================

set -euo pipefail

IMAGE_NAME="${1:?ERROR: Image name required}"
IMAGE_TAG="${2:?ERROR: Image tag required}"
DOCKERFILE="${3:-Dockerfile}"
BUILD_CONTEXT="${4:-.}"

echo "============================================"
echo "Docker Build"
echo "============================================"
echo "Image:      ${IMAGE_NAME}:${IMAGE_TAG}"
echo "Dockerfile: ${DOCKERFILE}"
echo "Context:    ${BUILD_CONTEXT}"
echo "============================================"

# Validate Dockerfile exists
if [ ! -f "${DOCKERFILE}" ]; then
  echo "ERROR: Dockerfile not found at ${DOCKERFILE}"
  exit 1
fi

# Build with OCI labels
docker build \
  --label "org.opencontainers.image.created=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --label "org.opencontainers.image.revision=${GIT_COMMIT:-unknown}" \
  --label "org.opencontainers.image.source=${GIT_URL:-unknown}" \
  --label "org.opencontainers.image.version=${IMAGE_TAG}" \
  --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --build-arg VCS_REF="${GIT_COMMIT:0:7}" \
  --build-arg VERSION="${IMAGE_TAG}" \
  --tag "${IMAGE_NAME}:${IMAGE_TAG}" \
  --file "${DOCKERFILE}" \
  "${BUILD_CONTEXT}"

echo "============================================"
echo "Build successful: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "============================================"
