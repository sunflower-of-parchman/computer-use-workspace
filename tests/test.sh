#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${REPO_DIR}/scripts/computer-use-workspace.swift"
TEST_DIR="$(mktemp -d /private/tmp/computer-use-workspace-test.XXXXXX)"

cleanup() {
  rm -rf "${TEST_DIR}"
}
trap cleanup EXIT

bash -n \
  "${REPO_DIR}/scripts/computer-use-workspace" \
  "${REPO_DIR}/scripts/build.sh" \
  "${REPO_DIR}/tests/test.sh"

swiftc -typecheck -module-cache-path "${TEST_DIR}/module-cache" "${SOURCE}"
swiftc -O -module-cache-path "${TEST_DIR}/module-cache" -o "${TEST_DIR}/computer-use-workspace-cli" "${SOURCE}"

SELF_TEST_OUTPUT="$("${TEST_DIR}/computer-use-workspace-cli" self-test)"
printf '%s\n' "${SELF_TEST_OUTPUT}"
printf '%s\n' "${SELF_TEST_OUTPUT}" | grep -q '"ok" : true'
printf '%s\n' "${SELF_TEST_OUTPUT}" | grep -q '"status" : "passed"'
printf '%s\n' "${SELF_TEST_OUTPUT}" | grep -q '10 placement and cleanup scenarios passed'

grep -q '^name: computer-use-workspace$' "${REPO_DIR}/SKILL.md"
grep -q '\$computer-use-workspace' "${REPO_DIR}/agents/openai.yaml"

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
