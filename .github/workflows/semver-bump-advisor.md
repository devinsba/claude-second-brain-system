---
description: Suggests a semver bump per plugin based on the content of this PR's changes and comments a summary table; retracts the recommendation if plugin changes are later removed.
on:
  pull_request:
    types: [opened, synchronize, reopened]
  workflow_dispatch:
    inputs:
      pr_number:
        description: "Pull request number to analyze (for manual pre-merge testing via gh aw run --ref)"
        required: true
        type: number
concurrency:
  job-discriminator: ${{ github.event.pull_request.number || inputs.pr_number || github.run_id }}
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

Analyze pull request #${{ github.event.pull_request.number || github.event.inputs.pr_number }} and recommend a semantic-versioning
bump for each plugin under `plugins/*/` that this PR touches. Runs on every push to the PR (no
`paths:` filter), since this same task also has to detect and retract its own recommendation when a
later push removes all plugin changes — see step 4/7 below.

## Task

1. Discover plugins on **both** revisions of this PR, not just the head:
   - Head: list directories matching `plugins/*/` (at the PR head) that contain a
     `.claude-plugin/plugin.json`, and read each one's `version`.
   - Base: do the same against the PR's base ref. Get the base SHA via
     `gh pr view ${{ github.event.pull_request.number || github.event.inputs.pr_number }} --json
     baseRefOid --jq .baseRefOid` (works whether this run was triggered by the PR itself or dispatched
     manually), then e.g. `gh api repos/{owner}/{repo}/contents/plugins?ref=<that-sha>`.
   - Match plugins across base and head by directory name, and also detect renames (a plugin
     directory that disappeared at one path and an equivalent plugin appeared at another path in the
     same diff — treat that as the same plugin, not a deletion plus an addition).
   - A plugin whose directory or manifest exists at the base but is gone at the head (deleted, not
     renamed) is still in scope: use the base manifest's `version` as "Current Version" and classify
     it as **major** (removing a plugin breaks installation for anyone using it).
2. Get the full diff for this PR (e.g. `gh pr diff ${{ github.event.pull_request.number || github.event.inputs.pr_number }}`) and the
   list of changed files (`gh pr diff ${{ github.event.pull_request.number || github.event.inputs.pr_number }} --name-only`).
3. Group the changed files by the plugins discovered in step 1 (match each changed path to the plugin
   directory, matched/renamed per step 1, that actually contains it). A changed path under `plugins/`
   that isn't inside any discovered plugin's own directory (e.g. a stray `plugins/README.md`) doesn't
   count as affecting a plugin.
4. Branch here, and do exactly one of the two branches below — never both:
   - **Branch A** (at least one plugin from step 1 has changed files attributed to it in step 3):
     continue to step 5, then step 6, and stop. Do not evaluate step 7.
   - **Branch B** (no plugin from step 1 has any changed files attributed to it in step 3 — this PR
     currently has no plugin impact): skip directly to step 7 and stop. Do not evaluate steps 5-6.
5. For each affected plugin, ignore commit messages entirely and classify the bump by reading the
   actual content of the diff for that plugin's files. The question at every level is whether the
   change is observable by someone *using* the plugin (installing it, invoking one of its
   skills/commands, reading its manifest) — not whether some file changed:
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
6. (Branch A only) Post one PR comment (via the comment safe output) containing a single Markdown
   table:

   | Plugin | Current Version | Suggested Bump | Reasoning |
   |---|---|---|---|

   - "Current Version" is the `version` from that plugin's base-revision `plugin.json` (or head, if
     the plugin is new in this PR).
   - "Suggested Bump" is `major`, `minor`, or `patch`.
   - "Reasoning" is one short sentence describing the actual capability-level change that drove the
     decision (e.g. "adds a new recall skill" or "deletes the plugin, breaking existing installs").
7. (Branch B only) **Retraction path**: check whether a previous recommendation from this exact
   workflow is still showing on this PR. List this PR's comments (e.g.
   `gh api repos/{owner}/{repo}/issues/${{ github.event.pull_request.number || github.event.inputs.pr_number }}/comments`) and look
   for one that is both:
   - authored by a bot account — the comment author's `login` ends in `[bot]` (the safe-output write
     path always posts as a bot identity, e.g. `github-actions[bot]`; never match a human account
     regardless of what the comment body says), **and**
   - contains this workflow's table header (`| Plugin | Current Version | Suggested Bump |
     Reasoning |`).

   A comment that merely quotes or discusses that header without being authored by a bot account does
   not count, and must not be touched.

   - If no such comment exists, there is nothing to retract: call `noop` with a short reason and stop.
   - If one exists, replace its content (via the comment safe output — the same call used in step 6,
     which updates that existing comment in place rather than creating a new one) with a short note
     that no plugin is currently affected by this PR and the previous recommendation no longer
     applies. Do not hide or minimize the comment: a hidden comment stays hidden even after a later
     push's content update, so if this PR's plugin changes are reintroduced afterward, a hidden
     comment would never become visible again.
