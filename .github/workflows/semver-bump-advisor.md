---
description: Suggests a semver bump per plugin based on the content of this PR's changes and comments a summary table; retracts the recommendation if plugin changes are later removed.
on:
  pull_request:
    types: [opened, synchronize, reopened]
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

This workflow intentionally has **no `paths:` filter** and runs on every push to the PR. An earlier
design split this into two workflows — one filtered to `plugins/**` for the analysis, one unfiltered
for retracting a stale recommendation when a later push reverted all plugin changes. That split had
real bugs: the two workflows used separate concurrency groups, so a stale analysis run could still
post its comment after a newer push's cleanup run had already decided there was nothing to clean up;
and the cleanup workflow's own "is any plugin still affected?" check was a cruder path-prefix test
than this workflow's real base/head manifest discovery, so it could disagree with this workflow about
whether a plugin was actually affected. Running everything here, once, under one concurrency group (so
a new push cancels an in-flight run for the same PR) and one shared discovery step removes both
problems.

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
3. Group the changed files by the plugins discovered in step 1 (match each changed path to the plugin
   directory, matched/renamed per step 1, that actually contains it). A changed path under `plugins/`
   that isn't inside any discovered plugin's own directory (e.g. a stray `plugins/README.md`) doesn't
   count as affecting a plugin.
4. If no plugin from step 1 has any changed files attributed to it in step 3, this PR currently has no
   plugin impact — go to step 7 (retraction path). Otherwise, continue to step 5 for each affected
   plugin.
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
6. Post one PR comment (via the comment safe output) containing a single Markdown table, then stop
   (do not continue to step 7):

   | Plugin | Current Version | Suggested Bump | Reasoning |
   |---|---|---|---|

   - "Current Version" is the `version` from that plugin's base-revision `plugin.json` (or head, if
     the plugin is new in this PR).
   - "Suggested Bump" is `major`, `minor`, or `patch`.
   - "Reasoning" is one short sentence describing the actual capability-level change that drove the
     decision (e.g. "adds a new recall skill" or "deletes the plugin, breaking existing installs").
7. **Retraction path** (only reached from step 4, when no plugin is currently affected): check whether
   a previous recommendation from this exact workflow is still showing on this PR. List this PR's
   comments (e.g.
   `gh api repos/{owner}/{repo}/issues/${{ github.event.pull_request.number }}/comments`) and look
   for one that is both:
   - authored by this workflow's own posting identity (the automation actor used for safe-output
     writes, e.g. `github-actions[bot]` — not an arbitrary human or other bot), **and**
   - contains this workflow's table header (`| Plugin | Current Version | Suggested Bump |
     Reasoning |`).

   A comment that merely quotes or discusses that header without being authored by this workflow's
   own posting identity does not count, and must not be touched.

   - If no such comment exists, there is nothing to retract: call `noop` with a short reason and stop.
   - If one exists, replace its content (via the comment safe output — the same call used in step 6,
     which updates that existing comment in place rather than creating a new one) with a short note
     that no plugin is currently affected by this PR and the previous recommendation no longer
     applies. Do not hide or minimize the comment: a hidden comment stays hidden even after a later
     push's content update, so if this PR's plugin changes are reintroduced afterward, a hidden
     comment would never become visible again.
