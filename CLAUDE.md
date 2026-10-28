# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Claude Code **plugin marketplace**: a thin JSON layer (`.claude-plugin/marketplace.json`) that points at one or more plugins, each living under `plugins/<name>/` with its own `.claude-plugin/plugin.json` manifest. There is no build system, package manager, or test suite — the "code" is marketplace/plugin metadata plus whatever skills, commands, agents, or hooks each plugin defines.

Currently there is a single plugin, `brain` (`plugins/brain/`), intended to become a "Second Brain System" built around Claude Code. It is still a skeleton: `plugins/brain/skills/` exists but is empty (only a `.gitkeep`).

## Architecture

- `.claude-plugin/marketplace.json` — the marketplace manifest. Lists each plugin's `name`, `source` (relative path), `description`, and `version`. Adding a new plugin means adding both the directory under `plugins/` and an entry here.
- `plugins/<plugin-name>/.claude-plugin/plugin.json` — per-plugin manifest (`name`, `description`, `version`, `author`). This is what Claude Code reads when a user runs `/plugin install <plugin-name>@<marketplace-name>`.
- `plugins/<plugin-name>/skills/` — where that plugin's skills live (one subdirectory per skill, each with a `SKILL.md`). A plugin can also define `commands/`, `agents/`, or `hooks/` directories following the same convention once those are introduced.
- Keep plugin and marketplace `version` fields in sync when bumping a plugin's version — the marketplace entry is not derived automatically from the plugin manifest.

## Installing / testing locally

Users consume this repo via:

```
/plugin marketplace add devinsba/claude-second-brain-system
/plugin install brain@claude-second-brain-system
```

To test changes locally before publishing, add the marketplace by local path instead of the GitHub slug (`/plugin marketplace add <local-path>`), then reinstall/reload the plugin to pick up changes.

There are no lint/build/test commands in this repo — validate changes by exercising the installed plugin's skills/commands directly in a Claude Code session.
