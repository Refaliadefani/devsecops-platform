#!/bin/bash
# ==============================================================================
# Semgrep SAST Scan Script
# ==============================================================================
# Standalone script untuk SAST (Static Application Security Testing).
# Bisa digunakan untuk:
#   - Local scan di developer machine sebelum push
#   - CI environment yang sudah install Semgrep
#   - Pre-commit hook integration
#
# Catatan: Jenkinsfile utama menjalankan Semgrep via Docker container.
#          Script ini untuk penggunaan langsung (Semgrep terinstall lokal).
#
# Usage: ./semgrep-scan.sh [rules] [target-dir]
# Example: ./semgrep-scan.sh auto ./src
# ==============================================================================

set -euo pipefail

RULES="${1:-auto}"
TARGET_DIR="${2:-.}"
OUTPUT_DIR="${SEMGREP_OUTPUT_DIR:-./semgrep-reports}"

echo "============================================"
echo "Semgrep SAST Scan"
echo "============================================"
echo "Rules:  ${RULES}"
echo "Target: ${TARGET_DIR}"
echo "Output: ${OUTPUT_DIR}"
echo "============================================"

mkdir -p "${OUTPUT_DIR}"

# Run Semgrep with JSON output
echo "Running SAST analysis..."
SCAN_RESULT=0
semgrep scan \
  --config "${RULES}" \
  --json \
  --output "${OUTPUT_DIR}/semgrep-results.json" \
  --severity ERROR \
  --severity WARNING \
  "${TARGET_DIR}" || SCAN_RESULT=$?

# Generate text report
semgrep scan \
  --config "${RULES}" \
  --severity ERROR \
  --severity WARNING \
  "${TARGET_DIR}" > "${OUTPUT_DIR}/semgrep-report.txt" 2>&1 || true

# Parse results
if [ -f "${OUTPUT_DIR}/semgrep-results.json" ]; then
  ERROR_COUNT=$(grep -c '"severity": "ERROR"' "${OUTPUT_DIR}/semgrep-results.json" || echo "0")
  WARNING_COUNT=$(grep -c '"severity": "WARNING"' "${OUTPUT_DIR}/semgrep-results.json" || echo "0")
  
  echo "============================================"
  echo "Results:"
  echo "  Errors:   ${ERROR_COUNT}"
  echo "  Warnings: ${WARNING_COUNT}"
  echo "============================================"
fi

if [ "${SCAN_RESULT}" -ne 0 ]; then
  echo "FAILED: Security issues detected"
  echo "Review the report at: ${OUTPUT_DIR}/semgrep-report.txt"
  exit 1
fi

echo "PASSED: No critical security issues found"
exit 0
