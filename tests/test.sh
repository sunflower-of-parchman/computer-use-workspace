#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${REPO_DIR}/scripts/computer-use-workspace.swift"
BINARY="${REPO_DIR}/scripts/.build/computer-use-workspace-cli"
SOURCE_FINGERPRINT="${REPO_DIR}/scripts/.build/source.sha256"

bash -n \
  "${REPO_DIR}/scripts/computer-use-workspace" \
  "${REPO_DIR}/scripts/build.sh" \
  "${REPO_DIR}/tests/test.sh"

if [[ ! -x "${BINARY}" || ! -f "${SOURCE_FINGERPRINT}" ]]; then
  echo "Build the helper before testing: bash scripts/build.sh" >&2
  exit 70
fi

EXPECTED_FINGERPRINT="$(shasum -a 256 "${SOURCE}" | awk '{print $1}')"
ACTUAL_FINGERPRINT="$(<"${SOURCE_FINGERPRINT}")"
if [[ "${EXPECTED_FINGERPRINT}" != "${ACTUAL_FINGERPRINT}" ]]; then
  echo "The built helper does not match the current Swift source. Run bash scripts/build.sh." >&2
  exit 70
fi

SELF_TEST_OUTPUT="$("${BINARY}" self-test)"
printf '%s\n' "${SELF_TEST_OUTPUT}"
printf '%s\n' "${SELF_TEST_OUTPUT}" | grep -q '"ok" : true'
printf '%s\n' "${SELF_TEST_OUTPUT}" | grep -q '"status" : "passed"'
printf '%s\n' "${SELF_TEST_OUTPUT}" | grep -q '59 placement and cleanup scenarios passed'

grep -q '^name: computer-use-workspace$' "${REPO_DIR}/SKILL.md"
grep -q '\$computer-use-workspace' "${REPO_DIR}/agents/openai.yaml"
grep -q '^# Security Policy$' "${REPO_DIR}/SECURITY.md"

SOCIAL_PREVIEW="${REPO_DIR}/.github/social-preview.jpg"
test -f "${SOCIAL_PREVIEW}"
test "$(sips -g pixelWidth "${SOCIAL_PREVIEW}" | awk '/pixelWidth/ {print $2}')" = "1280"
test "$(sips -g pixelHeight "${SOCIAL_PREVIEW}" | awk '/pixelHeight/ {print $2}')" = "640"
test "$(stat -f%z "${SOCIAL_PREVIEW}")" -lt 1000000

OLD_NAME="computer-use-smart""-launch"
if rg -n "${OLD_NAME}" \
  "${REPO_DIR}/SKILL.md" \
  "${REPO_DIR}/agents" \
  "${REPO_DIR}/scripts" \
  "${REPO_DIR}/tests"; then
  echo "Found the retired skill name in runtime files" >&2
  exit 1
fi

printf 'Project verification passed.\n'
