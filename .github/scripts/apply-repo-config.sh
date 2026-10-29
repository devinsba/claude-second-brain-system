#!/usr/bin/env bash
# Applies .github/repo-settings.json and .github/branch-protection-ruleset.json
# to the current repo via the GitHub API. Requires `gh` authenticated with
# admin access to the repo.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

echo "Applying repo settings to ${REPO}..."
gh api "repos/${REPO}" -X PATCH --input .github/repo-settings.json >/dev/null
echo "Repo settings applied."

RULESET_NAME="$(jq -r .name .github/branch-protection-ruleset.json)"
EXISTING_ID="$(gh api "repos/${REPO}/rulesets" --jq ".[] | select(.name == \"${RULESET_NAME}\") | .id" || true)"

if [[ -n "${EXISTING_ID}" ]]; then
  echo "Updating existing ruleset '${RULESET_NAME}' (id ${EXISTING_ID}) on ${REPO}..."
  gh api "repos/${REPO}/rulesets/${EXISTING_ID}" -X PUT --input .github/branch-protection-ruleset.json >/dev/null
else
  echo "Creating ruleset '${RULESET_NAME}' on ${REPO}..."
  gh api "repos/${REPO}/rulesets" -X POST --input .github/branch-protection-ruleset.json >/dev/null
fi
echo "Ruleset applied."
