---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: update-install-packages 
description: Update Ubuntu package configuration files for package add and delete operations.
---

## Trigger Phrases
- update install packages
- add package to curate-host-packages.sh
- delete package from ict template
- modify ubuntu package list
- update-install-packages
- add missing packages
- install hardware packages
- add hardware drivers
- install device drivers
- manage system packages
- configure package list
- add kernel drivers
- install missing dependencies
- update handheld package list
- update server package list
- update companion compute package list
- update uav package list

## Required Inputs
- enib_home: absolute path to this repository root
- package_operation: `add|delete`
- packages_list: comma-separated package names
- target_config_file: `curate-host-packages|ict-template|both`

All derived paths use defaults — never prompt for them unless the user explicitly overrides:
- `ict_template`: auto-resolve from user intent text using these rules (identical to the `create-image` skill):
   - If text includes any server intent phrase (`server`, `uav`, `companion`, `companion server`, `uav companion`), use `infrastructure/host-os/ict/generic-companion-os-server-template.yml`
   - If text includes handheld intent phrase (`handheld`, `backpack`), use `infrastructure/host-os/ict/generic-handheld-os-template.yml`
   - If no specific server intent is detected, fall back to `infrastructure/host-os/ict/generic-handheld-os-template.yml`
- `curate_host_packages`: auto-resolve from the same intent using the matching Docker-build curation script:
   - Server intent → `infrastructure/host-os/curate-host-packages-server.sh`
   - Handheld intent (default) → `infrastructure/host-os/curate-host-packages.sh`

### Variant compatibility (target_config_file × resolved intent)

| Resolved intent | `curate-host-packages` → resolved file | `ict-template` → resolved file |
|---|---|---|
| handheld (default) | `infrastructure/host-os/curate-host-packages.sh` | `infrastructure/host-os/ict/generic-handheld-os-template.yml` |
| server / uav / companion | `infrastructure/host-os/curate-host-packages-server.sh` | `infrastructure/host-os/ict/generic-companion-os-server-template.yml` |

- `target_config_file=both` updates both the resolved curation script and the resolved ICT template for that intent.

## Preconditions
- [ ] Repository exists and is writable: `test -d <enib_home> && test -w <enib_home>`
- [ ] Resolved `ict_template` file exists: `test -f <enib_home>/<ict_template>`
- [ ] If `target_config_file` includes `curate-host-packages`, the resolved `curate_host_packages` file exists: `test -f <enib_home>/<curate_host_packages>`
- [ ] `package_operation` is one of `add|delete`.
- [ ] `target_config_file` is one of `curate-host-packages|ict-template|both`.
- [ ] `packages_list` is not empty.
- [ ] Validate each package name format (letters, digits, `.`, `+`, `-`) and reject invalid tokens.
- [ ] **MANDATORY**: Verify package availability in Ubuntu OS version 24.04 repositories for each requested package using `apt-cache show <package_name>`. If package is not found, use `apt-cache search <keyword>` to find alternatives and present to user for selection.
- [ ] Create backup copies before modifying configuration files.
- [ ] Prompt for `sudo` confirmation only before privileged or destructive operations.
- [ ] Sudo probe (MANDATORY before any privileged step such as sudo apt update/sudo apt install): run sudo -n true. If exit is non-zero, stop and instruct the user to run sudo -v in their terminal (or add a scoped NOPASSWD entry in /etc/sudoers.d/ for the specific binary), then re-trigger the skill. If sudo -v was already run but sudo -n true still fails, the user must make sudo timestamps global (tty_tickets issue): echo 'Defaults timestamp_type=global' | sudo tee /etc/sudoers.d/agent-timestamp && sudo chmod 0440 /etc/sudoers.d/agent-timestamp && sudo visudo -c. See AGENTS.md. 

## Steps
1. Collect required inputs:
  - `package_operation`, `packages_list`, and `target_config_file`.
  - Split and normalize `packages_list` into individual package names.
  - Optionally collect hardware details (e.g., device name, model, and vendor).
2. Resolve the effective paths from user intent text using the rules in Required Inputs — same pattern as the `create-image` skill:
  - `ict_template` → handheld or server ICT `.yml`
  - `curate_host_packages` → `curate-host-packages.sh` (handheld) or `curate-host-packages-server.sh` (server)
3. Validate operation, target combination, and package list:
  - Reject invalid operation or target values.
  - Reject invalid package name formats.
  - **CRITICAL**: Verify package availability in Ubuntu OS version 24.04 repositories using `apt-cache show <package_name>`.
  - For `add` operations: **MANDATORY** - Query Ubuntu OS version 24.04 apt repositories using `apt-cache show <package_name>` to confirm that each package exists before adding to target_config_file. If a package is not found, suggest alternative package names using `apt-cache search <keyword>` and present options to the user. Reject any packages not found in official Ubuntu OS version 24.04 repositories after validation.
4. If hardware details are provided, search Ubuntu OS version 24.04 repositories:
  - Query repository metadata for corresponding userspace or kernel-space packages matching the hardware device.
  - Return matched packages to the user for confirmation before adding to `packages_list`.
  - Merge confirmed packages with the original `packages_list`.
5. Run preconditions and create backups:
  - Backup every resolved target file before modification. The resolved set is derived from `target_config_file` and the resolved intent (`ict_template` and, when `target_config_file` includes `curate-host-packages`, the resolved `curate_host_packages` script).
6. Update the resolved target file(s):
  - `curate-host-packages`: update the resolved `<curate_host_packages>` (`curate-host-packages.sh` for handheld, `curate-host-packages-server.sh` for server/UAV). Consumed by the Docker-based image build.
  - `ict-template`: update the resolved `<ict_template>` (`generic-handheld-os-template.yml` for handheld, `generic-companion-os-server-template.yml` for server/UAV). Consumed by the ICT-based advanced image build.
  - `both`: update both resolved files for the resolved intent.
7. When adding packages to a `curate-host-packages*.sh` script, add only the cumulative package size to the existing `IMG_SIZE` in the matching image-setup script (`host-os/custom-image-setup.sh` for handheld, `host-os/custom-image-setup-server.sh` for server) when cumulative package size exceeds 1GB. Do not increment disk size for packages under 1GB (existing disk allocation already includes future headroom).
8. For packages that depend on kernel (performance tools, kernel drivers, or userspace packages with kernel dependencies), create symbolic links to the custom Intel kernel inside `infrastructure/installation-scripts/setup-kernel-depended-pkgs.sh` as a workaround. Do not start `setup-kernel-depended-pkgs.sh` if updated as part of a curation script or any ICT template; this script will start during the provisioning process separately.
9. Validate updated file syntax for modified files:
  - For any `curate-host-packages*.sh`, run `bash -n` to check shell syntax.
  - For any ICT template `.yml`, validate YAML syntax.
10. Summarize package update results for each modified file, including the resolved intent (`handheld` or `server`) and the effective `curate_host_packages` and `ict_template` paths.
11. If the user asks for artifact packaging, hand off to the dedicated packaging skill.


## Validation
- Configuration update summary is complete for add and delete operations.
- Updated shell and YAML files parse successfully.
- Backup files exist for each modified configuration file.

## Rollback
- Restore modified configuration files from backups if update or validation fails.

## Safety Rules
- Stop on precondition or validation failure and provide next-action guidance.
- Backup configuration files before modification.
- Validate shell and YAML syntax after updates.
- Ask before privileged or destructive actions.
- Ask for `sudo` confirmation only before privileged or destructive operations.
- Never infer credentials, certificates, SSH keys, or secrets.
- Do not overwrite ICT source template; always copy to working template.
- Verify package availability in Ubuntu OS version 24.04 repositories.

## Expected Result Summary
Return:
- whether preconditions passed
- resolved intent (`handheld` or `server`) and effective `curate_host_packages` and `ict_template` paths
- requested package operation and normalized package list
- target files selected and backup file paths
- per-file package change results (added, deleted, already-present, or not-found)
- shell and YAML validation status
- whether packaging handoff was requested
- troubleshooting hints when package update fails (for example, validation, permissions, or repository metadata issues)

## Troubleshooting Notes
- **Package Not Found**: If `apt-cache show <package>` returns nothing, the package name is incorrect or the package does not exist. Use `apt-cache search <keyword>` to find the correct package name. Common issues:
  - Different naming conventions: check for suffixes like `-dev`, `-tools`, or version numbers
  - Package might be in a different repository [Intel overlay, third-party Personal Package Archive (PPA)]
- **Wrong curation script for intent**: `curate-host-packages.sh` targets the handheld/desktop Docker build; `curate-host-packages-server.sh` targets the server/UAV Docker build. If the resolved intent does not match the file the user names explicitly, ask which to keep and re-resolve.
- If package validation fails, confirm package names against Ubuntu OS version 24.04  repository metadata and retry.
- If shell or YAML validation fails, restore from backup and reapply package updates with corrected formatting.
- If file update fails, verify write permissions for target files and backup paths.
