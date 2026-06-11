<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Copilot Instructions: Agent Skills and Context

Use `AGENTS.md` as the repository context catalog and `skills/*/SKILL.md` as execution contracts.

## How To Select a Skill
1. Parse the user request for desired outcome.
2. Match against skill trigger phrases.
3. Ask for missing required inputs before running commands.

For skill execution order, see [AGENTS.md](AGENTS.md#skill-execution-order-must-follow-for-all-skills).

## Sudo Handling (MUST follow before any `sudo` command)
Before running any `sudo` command in any skill or task:
1. Probe with `sudo -n true` and capture the exit code.
2. If exit is non-zero, **do not** run the privileged command. Tell the user to run `sudo -v` in their own terminal (or add a scoped `NOPASSWD` entry in `/etc/sudoers.d/` for the specific binary), then re-trigger the skill.
3. Never collect a password via prompts, env vars, scripts, or logs.

Full rules: [AGENTS.md#sudo-handling-must-follow-for-all-skills-that-invoke-sudo](AGENTS.md#sudo-handling-must-follow-for-all-skills-that-invoke-sudo).

## Supported Skill
- `create-image` at `skills/create-image/SKILL.md`
- `create-usb-installation-files` at `skills/create-usb-installation-files/SKILL.md`
- `validate-platform-config` at `skills/validate-platform-config/SKILL.md`
- `tune-platform-power` at `skills/tune-platform-power/SKILL.md`
- `update-install-packages`at `skills/update-install-packages/SKILL.md`

## Completion Criteria for Skill Runs
A run is complete only when Copilot returns:
- precondition results
- validation status
- build status (if executed)
- artifact paths and names
- troubleshooting notes when failures occur
