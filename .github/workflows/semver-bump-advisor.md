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
  copilot-requests: write
tools:
  github:
    mode: gh-proxy
    toolsets: [pull_requests]
safe-outputs:
  add-comment:
    max: 1
    replace-older-comments: true
    issues: false
---

# Semver Bump Advisor

Analyze pull request #${{ github.event.pull_request.number }} and recommend a semantic-versioning
bump for each plugin under `plugins/*/` that this PR touches.

This workflow is scoped to `plugins/**` via its `paths:` filter, so it only runs when a push's diff
touches a plugin. `semver-bump-advisor-cleanup.md` is a separate, unfiltered workflow that handles the
opposite transition — a later push that removes all plugin changes from a PR that previously had an
advisory comment — since this workflow's path filter means it can't see that case itself.

## Task

1. Discover plugins on **both** revisions of this PR, not just the head:
   - Head: list directories matching `plugins/*/` (at the PR head) that contain a
     `.claude-plugin/plugin.json`, and read each one's `version`.
   - Base: do the same against the PR's base ref (e.g. `gh api
     repos/{owner}/{repo}/contents/plugins?ref=<base-sha>`, or check out/diff against
     `${{ github.event.pull_request.base.sha }}`).
   - Match plugins across base and head by directory name, and also detect renames (a plugin
     directory that disappeared at one path and an equivalent plugin appeared at another path in the
     same diff — treat that as the same plugin, not a deletion plus an addition).
   - A plugin whose directory or manifest exists at the base but is gone at the head (deleted, not
     renamed) is still in scope: use the base manifest's `version` as "Current Version" and classify
     it as **major** (removing a plugin breaks installation for anyone using it).
2. Get the full diff for this PR (e.g. `gh pr diff ${{ github.event.pull_request.number }}`) and the
   list of changed files (`gh pr diff ${{ github.event.pull_request.number }} --name-only`).
3. Group the changed files by plugin directory (`plugins/<name>/**`, matched/renamed per step 1).
4. For each plugin, ignore commit messages entirely and classify the bump by reading the actual
   content of the diff for that plugin's files. The question at every level is whether the change is
   observable by someone *using* the plugin (installing it, invoking one of its skills/commands,
   reading its manifest) — not whether some file changed:
   - **major**: a skill, command, or other user-invocable capability the plugin publicly exposed was
     removed or renamed; such a capability's documented inputs, outputs, or invocation contract
     changed in a way that would break an existing caller; `plugin.json` dropped or incompatibly
     changed a field other callers rely on (e.g. `name`); or the whole plugin was deleted (see step 1).
     Removing or renaming files that aren't part of the plugin's public surface — internal helpers,
     placeholder files like `.gitkeep`, docs, tests, comments — is NOT major on its own.
   - **minor**: a new user-invocable capability was added (a new skill, command, or similarly exposed
     feature), or an existing capability was extended in a backward-compatible way, with nothing
     removed or changed incompatibly. Adding non-capability files (docs, config scaffolding, internal
     helpers, `.gitkeep` placeholders) is NOT minor on its own — judge by the capability added, not by
     the file count.
   - **patch**: everything else — wording, documentation, formatting, internal implementation,
     dependency bumps, or other changes that don't add or remove a capability and don't alter
     behavior any caller could observe. A docs-only or placeholder-file-only change to a plugin is
     patch.
   - If the diff mixes categories for one plugin, take the highest severity present (major > minor >
     patch).
5. Plugins with no changed files on either revision get **none** — do not list them in the output.
6. Post one PR comment (via the comment safe output) containing a single Markdown table:

   | Plugin | Current Version | Suggested Bump | Reasoning |
   |---|---|---|---|

   - "Current Version" is the `version` from that plugin's base-revision `plugin.json` (or head, if
     the plugin is new in this PR).
   - "Suggested Bump" is `major`, `minor`, or `patch`.
   - "Reasoning" is one short sentence describing the actual capability-level change that drove the
     decision (e.g. "adds a new recall skill" or "deletes the plugin, breaking existing installs").

   If no plugin under `plugins/*/` has any changed files in this PR (on either revision), call `noop`
   with a short reason instead of posting a comment.
