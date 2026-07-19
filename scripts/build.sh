#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/.build"
SOURCE="${SCRIPT_DIR}/computer-use-workspace.swift"
BINARY="${BUILD_DIR}/computer-use-workspace-cli"
MODULE_CACHE="${BUILD_DIR}/module-cache"

mkdir -p "${BUILD_DIR}" "${MODULE_CACHE}"
swiftc -O -module-cache-path "${MODULE_CACHE}" -o "${BINARY}" "${SOURCE}"
printf 'Built %s\n' "${BINARY}"
