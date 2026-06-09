#!/bin/bash
# ==============================================================================
# Trivy Container Image Scan Script
# ==============================================================================
# Scans a Docker image for vulnerabilities using Trivy.
# Fails pipeline if CRITICAL or HIGH vulnerabilities are found.
# Usage: ./trivy-scan.sh <image-name:tag> [severity] [exit-code]
# ==============================================================================

set -euo pipefail

IMAGE="${1:?ERROR: Image name:tag required}"
SEVERITY="${2:-CRITICAL,HIGH}"
EXIT_CODE="${3:-1}"
OUTPUT_DIR="${TRIVY_OUTPUT_DIR:-./trivy-reports}"

echo "============================================"
echo "Trivy Image Vulnerability Scan"
echo "============================================"
echo "Image:    ${IMAGE}"
echo "Severity: ${SEVERITY}"
echo "Output:   ${OUTPUT_DIR}"
echo "============================================"

mkdir -p "${OUTPUT_DIR}"

# Run scan with JSON output for CI integration
echo "Running vulnerability scan..."
trivy image \
  --severity "${SEVERITY}" \
  --format json \
  --output "${OUTPUT_DIR}/trivy-results.json" \
  --ignore-unfixed \
  "${IMAGE}" || true

# Run scan with table output for human readability
trivy image \
  --severity "${SEVERITY}" \
  --format table \
  --ignore-unfixed \
  "${IMAGE}" | tee "${OUTPUT_DIR}/trivy-report.txt"

# Check for vulnerabilities and exit accordingly
VULN_COUNT=$(trivy image \
  --severity "${SEVERITY}" \
  --format json \
  --ignore-unfixed \
  --quiet \
  "${IMAGE}" | grep -c '"VulnerabilityID"' || echo "0")

echo "============================================"
echo "Vulnerabilities found: ${VULN_COUNT}"
echo "============================================"

if [ "${VULN_COUNT}" -gt 0 ] && [ "${EXIT_CODE}" -eq 1 ]; then
  echo "FAILED: ${VULN_COUNT} vulnerabilities found with severity ${SEVERITY}"
  echo "Review the report at: ${OUTPUT_DIR}/trivy-report.txt"
  exit 1
fi

echo "PASSED: No blocking vulnerabilities found"
exit 0
