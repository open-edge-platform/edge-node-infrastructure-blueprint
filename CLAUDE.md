<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Claude Skill Discovery and Execution Rules

Use this file with `AGENTS.md` as the source of truth for this repository.

## Skill Discovery
1. Discover skills from `skills/`.
2. Match user intent to trigger phrases in each `SKILL.md`.
3. If multiple skills could match, ask the user to choose.

> **Note for Claude Code `/skills`:** the canonical location is `skills/` at the repo root. `.claude/skills` is a symlink to `../skills` so the built-in `/skills` command can discover them. Do not add new skills under `.claude/skills` directly — add them under `skills/`.

For skill execution order, see [AGENTS.md](AGENTS.md#skill-execution-order-must-follow-for-all-skills).

## Sudo Handling (MUST follow before any `sudo` command)
Before running any `sudo` command in any skill or task:
1. Probe with `sudo -n true` and capture the exit code.
2. If exit is non-zero, **do not** run the privileged command. Tell the user to run `sudo -v` in their own terminal (or add a scoped `NOPASSWD` entry in `/etc/sudoers.d/` for the specific binary), then re-trigger the skill.
3. Never collect a password via prompts, env vars, scripts, or logs.

Full rules: [AGENTS.md#sudo-handling-must-follow-for-all-skills-that-invoke-sudo](AGENTS.md#sudo-handling-must-follow-for-all-skills-that-invoke-sudo).
