---
description: Suggests a semver bump per plugin based on the content of this PR's changes and comments a summary table.
on:
  pull_request:
    types: [opened, synchronize, reopened]
    paths:
      - "plugins/**"
permissions:
  contents: read
  pull-requests: read
tools:
  github:
    mode: gh-proxy
    toolsets: [pull_requests]
safe-outputs:
  add-comment:
    max: 1
    hide-older-comments: true
    issues: false
---

# Semver Bump Advisor

Analyze pull request #${{ github.event.pull_request.number }} and recommend a semantic-versioning
bump for each plugin under `plugins/*/` that this PR touches.

## Task

1. Discover plugins: list directories matching `plugins/*/` that contain a `.claude-plugin/plugin.json`.
   Read each one's current `version` field.
2. Get the full diff for this PR (e.g. `gh pr diff ${{ github.event.pull_request.number }}`) and the
   list of changed files (`gh pr diff ${{ github.event.pull_request.number }} --name-only`).
3. Group the changed files by plugin directory (`plugins/<name>/**`).
4. For each plugin, ignore commit messages entirely and classify the bump by reading the actual
   content of the diff for that plugin's files:
   - **major**: a file, skill, command, or config key that previously existed was removed or renamed;
     an existing skill/command's documented inputs, outputs, or invocation contract changed in a way
     that would break an existing user/caller; `plugin.json` dropped or incompatibly changed a field
     other callers rely on.
   - **minor**: new files were added (e.g. a new skill, command, or capability) or existing
     functionality was extended in a backward-compatible way — nothing existing was removed or
     changed incompatibly.
   - **patch**: only wording, documentation, formatting, internal implementation, or other changes
     that don't add or remove any capability and don't alter behavior any caller could observe.
   - If the diff mixes categories for one plugin, take the highest severity present (major > minor >
     patch).
5. Plugins with no changed files get **none** — do not list them in the output.
6. Post one PR comment (via the comment safe output) containing a single Markdown table:

   | Plugin | Current Version | Suggested Bump | Reasoning |
   |---|---|---|---|

   - "Current Version" is the `version` from that plugin's `plugin.json`.
   - "Suggested Bump" is `major`, `minor`, or `patch`.
   - "Reasoning" is one short sentence describing the actual content change that drove the decision
     (e.g. "adds a new recall skill" or "removes the `search` command, breaking existing callers").

   If no plugin under `plugins/*/` has any changed files in this PR, call `noop` with a short reason
   instead of posting a comment.
