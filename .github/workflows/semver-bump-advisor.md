---
description: Suggests a semver bump per plugin based on this PR's commits and comments a summary table.
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
2. Get this PR's changed files (`gh pr diff ${{ github.event.pull_request.number }} --name-only`) and
   its commits (`gh pr view ${{ github.event.pull_request.number }} --json commits`).
3. For each plugin, determine which of the PR's commits touched files under that plugin's directory
   (`plugins/<name>/**`, excluding the plugin's own `plugin.json` version field churn). A commit may
   need `gh api repos/{owner}/{repo}/commits/{sha}` to see its file list when the PR-level diff isn't
   enough to attribute a change to one plugin.
4. Classify each relevant commit using Conventional Commits conventions found in its message/body:
   - **major**: a `!` after the type/scope (e.g. `feat!:`), or a `BREAKING CHANGE:` footer, or the
     message otherwise clearly describes a backward-incompatible change (removed/renamed
     skill, command, or config the plugin exposes).
   - **minor**: type `feat` (new skill, command, or capability) without a breaking change.
   - **patch**: type `fix`, `perf`, `refactor`, `docs`, `chore`, `style`, `test`, `build`, or `ci`, or
     any other change that doesn't qualify as major or minor.
   - Commits that don't follow Conventional Commits: infer intent from the diff and message; default
     to **patch** when genuinely ambiguous.
5. For each plugin touched by the PR, take the highest-severity bump among its attributed commits
   (major > minor > patch). Plugins with no attributed commits get **none** — do not list them.
6. Post one PR comment (via the comment safe output) containing a single Markdown table:

   | Plugin | Current Version | Suggested Bump | Reasoning |
   |---|---|---|---|

   - "Current Version" is the `version` from that plugin's `plugin.json`.
   - "Suggested Bump" is `major`, `minor`, or `patch`.
   - "Reasoning" is one short sentence citing the deciding commit type(s)/message(s) (e.g.
     "feat: add recall skill" or "fix!: correct marketplace entry path (breaking)").

   If no plugin under `plugins/*/` is affected by this PR's commits, call `noop` with a short reason
   instead of posting a comment.
