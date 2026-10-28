---
description: Hides the semver bump advisor's table comment when a later push removes all plugins/** changes from the PR.
on:
  pull_request:
    types: [synchronize]
permissions:
  contents: read
  pull-requests: read
  copilot-requests: write
tools:
  github:
    mode: gh-proxy
    toolsets: [pull_requests]
safe-outputs:
  hide-comment:
    max: 1
    allowed-reasons: [outdated]
---

# Semver Bump Advisor Cleanup

This workflow intentionally has **no `paths:` filter**, unlike `semver-bump-advisor.md`. That
advisor only fires when the push's diff touches `plugins/**`, so if a PR had plugin changes (and an
advisory comment), then a later push reverts all of them while keeping other unrelated changes, the
advisor's path filter means it never runs again — and its stale table would stay visible forever with
nothing to retract it. This workflow runs on every `synchronize` to catch exactly that transition, and
does the minimum work needed to detect and handle it.

## Task

1. Get the current list of files changed in pull request #${{ github.event.pull_request.number }}
   (e.g. `gh pr diff ${{ github.event.pull_request.number }} --name-only`).
2. If any changed file path starts with `plugins/`, there is nothing to clean up — the filtered
   `semver-bump-advisor` workflow owns this PR's current state. Call `noop` with a short reason and
   stop.
3. Otherwise, the PR's diff no longer touches any plugin. Look for an existing bump-advisor comment
   on this PR (e.g. list comments via
   `gh api repos/{owner}/{repo}/issues/${{ github.event.pull_request.number }}/comments`) by finding
   one whose body contains the advisor's table header
   (`| Plugin | Current Version | Suggested Bump | Reasoning |`).
4. If such a comment exists, hide it (via the comment-hiding safe output) with reason `outdated` —
   the recommendation no longer applies since no plugin is affected by this PR anymore.
5. If no such comment exists, there is nothing to clean up: call `noop` with a short reason instead.
