#!/usr/bin/env bash
set -euo pipefail

BUILD_MODE="development"
VERIFY=false
for argument in "$@"; do
  case "${argument}" in
    --release)
      BUILD_MODE="release"
      ;;
    --verify)
      VERIFY=true
      ;;
    *)
      echo "Usage: bash scripts/build.sh [--release] [--verify]" >&2
      exit 64
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/.build"
SOURCE="${SCRIPT_DIR}/computer-use-workspace.swift"
BINARY="${BUILD_DIR}/computer-use-workspace-cli"
MODULE_CACHE="${BUILD_DIR}/module-cache"
SOURCE_FINGERPRINT="${BUILD_DIR}/source.sha256"
BUILD_MODE_FILE="${BUILD_DIR}/mode"

mkdir -p "${BUILD_DIR}" "${MODULE_CACHE}"
OPTIMIZATION="-Onone"
if [[ "${BUILD_MODE}" == "release" ]]; then
  OPTIMIZATION="-O"
fi
swiftc "${OPTIMIZATION}" -module-cache-path "${MODULE_CACHE}" -o "${BINARY}" "${SOURCE}"
shasum -a 256 "${SOURCE}" | awk '{print $1}' > "${SOURCE_FINGERPRINT}"
printf '%s\n' "${BUILD_MODE}" > "${BUILD_MODE_FILE}"
printf 'Built %s (%s)\n' "${BINARY}" "${BUILD_MODE}"

if [[ "${VERIFY}" == true ]]; then
  bash "${SCRIPT_DIR}/../tests/test.sh"
fi
