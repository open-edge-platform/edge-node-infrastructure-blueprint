---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: update-install-packages 
description: Update Ubuntu package configuration files for package add/delete operations.
---

## Trigger Phrases
- update install packages
- add package to auto-install-pkgs
- delete package from ict template
- modify ubuntu package list
- update-install-packages

## Required Inputs
- enib_home: absolute path to this repository root
- package_operation: `add|delete`
- packages_list: comma-separated package names
- target_config_file: `auto-install-pkgs|ict-template|both`

## Preconditions
- [ ] Repository exists and is writable: `test -d <enib_home> && test -w <enib_home>`
- [ ] Target files exist:
  - `test -f <enib_home>/infrastructure/host-os/auto-install-pkgs.yaml`
  - `test -f <enib_home>/infrastructure/host-os/ict/ubuntu24-x86_64-minimal-ptl.yml`
- [ ] `package_operation` is one of `add|delete`.
- [ ] `target_config_file` is one of `auto-install-pkgs|ict-template|both`.
- [ ] `packages_list` is not empty.
- [ ] Validate each package name format (letters, digits, `.`, `+`, `-`) and reject invalid tokens.
- [ ] Verify package availability in Ubuntu 24.04 repositories for each requested package.
- [ ] Create backup copies before modifying configuration files.
- [ ] Prompt for `sudo` confirmation only before privileged or destructive operations.
- [ ] **Sudo probe (MANDATORY before any privileged step such as `sudo apt update`/`sudo apt install`):** run `sudo -n true`. If exit is non-zero, stop and instruct the user to run `sudo -v` in their terminal (or add a scoped `NOPASSWD` entry in `/etc/sudoers.d/` for the specific binary), then re-trigger the skill. See [AGENTS.md](../../AGENTS.md#sudo-handling-must-follow-for-all-skills-that-invoke-sudo).

## Steps
1. Collect required inputs:
  - `package_operation`, `packages_list`, and `target_config_file`.
  - Split and normalize `packages_list` into individual package names.
2. Validate operation and package list:
  - Reject invalid operation/target values.
  - Reject invalid package name formats.
  - Verify package availability in Ubuntu 24.04 repositories.
3. Run preconditions and create backups:
  - Backup `infrastructure/host-os/auto-install-pkgs.yaml` and/or `infrastructure/host-os/ict/ubuntu24-x86_64-minimal-ptl.yml` before modification.
4. Update target configuration files based on `target_config_file`:
  - `auto-install-pkgs`: update `host-os/auto-install-pkgs.yaml`.
  - `ict-template`: update `host-os/ict/ubuntu24-x86_64-minimal-ptl.yml`.
  - `both`: update both files.
5. If adding more packages in `host-os/auto-install-pkgs.yaml`, add only the cumulative package size to existing `DISK_SIZE` in `host-os/prepare-host-img.sh` when cumulative package size exceeds 1GB. Do not increment disk size for packages under 1GB (existing disk allocation already includes future headroom).
6. For packages that depend on kernel (performance tools, kernel drivers, or userspace packages with kernel dependencies), create symbolic links to the custom Intel kernel inside `infrastructure/installation-scripts/setup-kernel-depended-pkgs.sh` as a workaround. Do not start `setup-kernel-depended-pkgs.sh` if updated as part of `auto-install-pkgs.yaml` and `ubuntu24-x86_64-minimal-ptl.yml`; this script will start during the provisioning process separately.
7. Validate updated YAML syntax for modified files.
8. Summarize package update results for each modified file.
9. If user asks for artifact packaging, hand off to the dedicated packaging skill.

## Validation
- Configuration update summary is complete for add/delete operations.
- Updated YAML files parse successfully.
- Backup files exist for each modified config file.

## Rollback
- Restore modified configuration files from backups if update or validation fails.

## Safety Rules
- Stop on failed preconditions.
- Backup configuration files before modification.
- Validate YAML syntax after updates.
- Ask before privileged or destructive actions.
- Ask for `sudo` confirmation only before privileged or destructive operations.
- Never infer credentials, certificates, SSH keys, or secrets.
- Stop on precondition or validation failure and provide next-action guidance.
- Do not overwrite ICT source template; always copy to working template.
- Verify package availability in Ubuntu 24.04 repositories.

## Expected Result Summary
Return:
- whether preconditions passed
- requested package operation and normalized package list
- target files selected and backup file paths
- per-file package change results (added/deleted/already-present/not-found)
- YAML validation status
- whether packaging handoff was requested
- troubleshooting hints when package update fails (for example validation, permissions, or repository metadata issues)

## Troubleshooting Notes
- If package validation fails, confirm package names against Ubuntu 24.04 repository metadata and retry.
- If YAML validation fails, restore from backup and reapply package updates with corrected formatting.
- If file update fails, verify write permissions for target files and backup paths.
