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
