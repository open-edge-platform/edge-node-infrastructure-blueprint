---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: create-usb-installation-files
description: Package bootable USB installation artifacts (HookOS, host image, deployment scripts) from an ICT image, Ubuntu ISO, or previously built image.
---

## Trigger Phrases
- create usb installation files
- build usb-installation-files.tar.gz
- package usb artifacts
- create bootable usb bundle
- build artifacts from ict image
- image from tool
- image composer
- from iso
- iso url

## Required Inputs
- enib_home: absolute path to this repository root
- build_mode: `image-from-iso|image-from-tool|reuse-image` (auto-infer when possible)
- Inputs collected only after mode is confirmed (collect only those relevant to the selected mode):
  - `image-from-tool`: `ict_img` — absolute path to `.raw.gz` or `.raw.img.gz` image (optional when `create-image` is run in same session)
  - `image-from-iso`: `iso_url` — Ubuntu ISO URL
  - `reuse-image`: no extra inputs required
- Additional inputs for `image-from-tool` only when `ict_img` is not already provided:
  - `create_image_first`: `yes|no`
  - `work_template`: ICT working template name
  - `target_template`: source ICT template path (default: `infrastructure/host-os/ict/ubuntu24-x86_64-minimal-ptl.yml`)
  - `os_image_composer_repo`: clone path for image-composer-tool (example: `<enib_home>/tools/image-composer-tool`)
- run_ven_deployment_check: `yes|no` (ask user whether to run `sudo ./ven-deployment.sh` after artifact creation)

## Preconditions
- [ ] Repository exists and is writable: `test -d <enib_home> && test -w <enib_home>`
- [ ] Build entrypoints exist:
  - `test -f <enib_home>/Makefile`
  - `test -f <enib_home>/infrastructure/build-artifacts/build-installation-artifacts.sh`
- [ ] If `ict_img` provided, verify it exists and has valid extension:
  - `test -f <ict_img>`
  - extension matches `*.raw.gz|*.raw.img.gz`
- [ ] Infer `build_mode` from user input when unambiguous:
  - mentions `ict`, `image from tool`, or `image composer` -> `image-from-tool`
  - mentions `from iso` or provides an ISO URL/path (`*.iso`, `http(s)://...*.iso`) -> `image-from-iso`
- [ ] Ask user to choose mode only when inference is ambiguous or conflicting.
- [ ] If `build_mode=image-from-tool` and `create_image_first=yes`, run all preconditions from `create-image` skill.
- [ ] If `build_mode=image-from-tool` and `ict_img` was NOT already provided:
  - probe for existing images at the expected first-time ICT output location (`<os_image_composer_repo>/workspace/ubuntu-ubuntu24-x86_64/imagebuild/<config-name>/`)
  - capture timestamps with `stat` and ask user one informed question to reuse or rebuild.
- [ ] If `build_mode=image-from-tool` and `ict_img` was already provided: skip reuse/rebuild prompt and use the given path directly.
- [ ] Prompt for `sudo` confirmation only before destructive operations: disk wipe, partition table changes, or build commands that overwrite the output directory. Do not prompt for non-destructive `sudo` commands such as `apt install`.
- [ ] **Sudo probe (MANDATORY before any step that runs `sudo`, including `sudo tar`, `sudo ./ven-deployment.sh`, or any privileged `make build` substep):** run `sudo -n true`. If exit is non-zero, stop and instruct the user to run `sudo -v` in their terminal (or add a scoped `NOPASSWD` entry in `/etc/sudoers.d/` for the specific binary), then re-trigger the skill. If `sudo -v` was already run but `sudo -n true` still fails, the user must make sudo timestamps global (tty_tickets issue): `echo 'Defaults timestamp_type=global' | sudo tee /etc/sudoers.d/agent-timestamp && sudo chmod 0440 /etc/sudoers.d/agent-timestamp && sudo visudo -c`. See [AGENTS.md](../../AGENTS.md#sudo-handling-must-follow-for-all-skills-that-invoke-sudo).

## Steps
1. Collect required inputs and determine flow:
  - Infer `build_mode` from user wording when possible (`ict`/`image from tool`/`image composer` => `image-from-tool`; `from iso` or ISO URL => `image-from-iso`).
  - Ask user to choose mode only if no unambiguous inference is possible.
  - Once mode is confirmed, collect only inputs required for that mode (do not ask for unrelated inputs).
  - Flow A (`build_mode=image-from-tool`):
    - If `ict_img` was already provided by the user: use it directly without any reuse/rebuild prompt.
    - If `ict_img` was NOT provided: probe expected ICT output path, show found image(s) with timestamps, ask one question to reuse or rebuild.
    - If rebuilding or no image found and `create_image_first=yes`: run `create-image` skill, then collect artifact path.
  - Flow B (`build_mode=image-from-iso`): ask only for `iso_url`, then build.
  - Flow C (`build_mode=reuse-image`): no additional inputs; proceed directly to build.
2. If Flow A requires image creation, run `create-image` skill to generate a host image and collect artifact path.
3. Set build command arguments:
  - `build_mode=image-from-tool`: `make build MODE=image-from-tool ICT_IMG="<ICT_IMG>"`
  - `build_mode=image-from-iso`: `make build MODE=image-from-iso ISO_URL="<ISO_URL>"`
  - `build_mode=reuse-image`: `make build MODE=reuse-image`
4. Build USB installation artifacts from repository root:
   - `cd <enib_home>`
  - execute selected build command from Step 3
5. Capture generated output path:
   - `<enib_home>/infrastructure/build-artifacts/out/usb-installation-files.tar.gz`
6. Ask user whether to try VEN deployment script:
  - `cd <enib_home>/infrastructure/build-artifacts/out`
  - `sudo tar -xzf usb-installation-files.tar.gz`
  - `printf 'y\ny\n' | sudo ./ven-deployment.sh`

## Validation
- Build command exits with code 0.
- Output file exists:
  - `<enib_home>/infrastructure/build-artifacts/out/usb-installation-files.tar.gz`
- Archive contains expected entries:
  - `bootable-usb-prepare.sh`
  - `config-file`
  - `usb-bootable-files.tar.gz`
  - `ven-deployment.sh`
- Validate only top-level archive entries for this skill (do not require inner archive extraction checks).

## Rollback
- Remove packaged output if user requests cleanup:
  - `rm -f <enib_home>/infrastructure/build-artifacts/out/usb-installation-files.tar.gz`
- Remove intermediate output directory if user approves:
  - `rm -rf <enib_home>/infrastructure/build-artifacts/out`
- If image was created in this run and user wants cleanup, apply rollback guidance from `create-image` skill.

## Safety Rules
- Ask for `sudo` confirmation only before destructive operations (disk wipe, partition table changes, overwriting output directories). Do not prompt for routine `sudo` use such as `apt install` or read-only commands.
- Never infer credentials, certificates, SSH keys, or secrets.
- Stop on precondition or validation failure and provide next-action guidance.
- Do not overwrite ICT source template; always copy to working template.

## Expected Result Summary
Return:
- whether preconditions passed
- whether `create-image` was executed
- selected build mode and effective command
- discovered older image paths and timestamps
- whether user approved reuse of an older image or requested rebuild
- packaging build status
- artifact file names and absolute paths
- validation results for archive contents
- whether user opted to run VEN deployment check
- troubleshooting hints when build fails (for example proxy/sudo/dependency issues)

## Troubleshooting Notes
- If `/dev/nbd0` is already attached from a previous run, clean up the stale NBD connection before retrying VEN deployment.
