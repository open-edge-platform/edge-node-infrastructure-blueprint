---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: create-usb-installation-files
description: Package bootable USB installation artifacts (HookOS, host image, deployment scripts) from a standard Docker build, an ICT image, or a previously built image.
---

## Trigger Phrases
- create usb installation files
- build usb-installation-files.tar.gz
- package usb artifacts
- create bootable usb bundle
- build artifacts from ict image
- image from tool
- image composer
- default usb image build
- server image build
- headless usb image build
- server image build
- headless usb image build

## Required Inputs
- enib_home: absolute path to this repository root (default: current workspace root)
- build_mode: `standard-image|server-image|image-from-tool|reuse-image` — infer from user wording; only ask when genuinely ambiguous
- `ict_img`: required only for `image-from-tool` mode when no image was produced in the same session; absolute or repo-relative path to `.raw.gz` or `.raw.img.gz`, containing only letters, digits, `/`, `.`, `_`, `-`, `+`, `:`, or `@` and no `..` path component

All other paths (`target_template`, `os_image_composer_repo`, etc.) use defaults — never prompt for them unless the user explicitly overrides.

## Preconditions
Run all checks silently — report failures only, no prompts:
- [ ] `test -d <enib_home> && test -w <enib_home>`
- [ ] `test -f <enib_home>/Makefile`
- [ ] `test -f <enib_home>/infrastructure/build-artifacts/build-installation-artifacts.sh`
- [ ] `docker ps` — if this fails, tell the user to run `sudo usermod -aG docker $USER && newgrp docker` (or use `sudo make build`), then stop
- [ ] `docker buildx version`
- [ ] `make --version`
- [ ] `proxy.env` present at repo root (auto-created by `make`; user can pass `skip-proxy=true` to bypass)
- [ ] If `ict_img` was given, validate it before use. Reject the input unless all checks pass:
  - `[[ "$ict_img" =~ ^[A-Za-z0-9_./:+@-]+$ ]]` (rejects shell metacharacters, whitespace, quotes, and control characters)
  - `[[ ! "$ict_img" =~ (^|/)\.\.(/|$) ]]` (rejects path traversal)
  - `[[ "$ict_img" == *.raw.gz || "$ict_img" == *.raw.img.gz ]]`
  - `[[ -f "$ict_img" ]]`
  - Canonicalize only after validation: `ict_img="$(realpath -e -- "$ict_img")"`; use this canonical value for every later command.
- [ ] **Sudo probe** (before any `sudo` step): `sudo -n true`. If non-zero, stop and tell the user to add scoped `NOPASSWD` entries for the required absolute binary paths in `/etc/sudoers.d/create-usb-installation-files`, then re-trigger. See [AGENTS.md](../../AGENTS.md).

## Steps
1. Collect required inputs and determine flow:
  - Infer `build_mode` from user wording when possible (`ict`/`image from tool`/`image composer` → `image-from-tool`; `server`/`headless`/`companion`/`uav` → `server-image`; no qualifier or `standard`/`handheld`/`backpack` → `standard-image`).
  - Ask user to choose mode only if no unambiguous inference is possible.
  - Once mode is confirmed, collect only inputs required for that mode (do not ask for unrelated inputs).
  - Flow A (`build_mode=standard-image`): no extra inputs; proceed directly to build.
  - Flow B (`build_mode=server-image`): no extra inputs; proceed directly to build.
  - Flow C (`build_mode=image-from-tool`):
    - If `ict_img` was already provided by the user: use it directly without any reuse/rebuild prompt.
    - If `ict_img` was NOT provided: probe expected ICT output path, show found image(s) with timestamps, ask one question to reuse or rebuild.
    - If rebuilding or no image found and `create_image_first=yes`: run `create-image` skill, then collect artifact path.
  - Flow D (`build_mode=reuse-image`): no additional inputs; proceed directly to build.
2. If Flow C requires image creation, run `create-image` skill to generate a host image and collect artifact path.
3. Set build command arguments:
  - `build_mode=standard-image`: `make build` (or `make build MODE=standard-image`)
  - `build_mode=server-image`: `make build MODE=server-image`
  - `build_mode=image-from-tool`: `make build MODE=image-from-tool ICT_IMG="$ict_img"`
  - `build_mode=reuse-image`: `make build MODE=reuse-image`
  - To skip proxy: append `skip-proxy=true` to any command above
4. Build USB installation artifacts from repository root:
   - `cd <enib_home>`
  - execute selected build command from Step 3
5. Capture generated output path:
   - `<enib_home>/infrastructure/build-artifacts/out/usb-installation-files.tar.gz`
6. Ask user whether to try the Virtual Edge Node (VEN) deployment script:
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
- Remove packaged output if the user requests a cleanup:
  - `rm -f <enib_home>/infrastructure/build-artifacts/out/usb-installation-files.tar.gz`
- Remove intermediate output directory if the user approves:
  - `rm -rf <enib_home>/infrastructure/build-artifacts/out`
- If the image was created in this run and the user wants a cleanup, apply rollback guidance from the `create-image` skill.

## Safety Rules
- Ask for `sudo` confirmation only before the following destructive operations: disk wipe, partition table changes, and overwriting output directories. Do not prompt for routine `sudo` use such as `apt install` or read-only commands.
- Never infer credentials, certificates, SSH keys, or secrets.
- Stop on precondition or validation failure, and provide next-action guidance.
- Do not overwrite ICT source template; always copy to working template.

## Expected Result Summary
Return:
- whether preconditions passed
- whether `create-image` was executed
- selected build mode and effective command
- discovered older image paths and timestamps
- whether the user approved the reuse of an older image or requested a rebuild
- packaging build status
- artifact file names and absolute paths
- validation results for archive contents
- whether the user opted to run VEN deployment check
- troubleshooting hints when build fails (for example, proxy, sudo, or dependency issues)

## Troubleshooting Notes
- If `/dev/nbd0` is already attached from a previous run, clean up the stale Network Block Device (NBD) connection before retrying VEN deployment.
