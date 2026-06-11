<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Edge Node Infrastructure Blueprint - Agent Context File
> Build and validate Intel edge node host images and infrastructure workflows for AI-ready deployments.

## Platform Overview
This repository enables repeatable edge infrastructure bring-up for Intel-based systems, with a focus on host OS image generation, provisioning readiness, and follow-on runtime enablement.
- Build Ubuntu-based host images for Intel harwares.
- Prepare artifacts for deployment, validation, and benchmarking workflows.
- Standardize team and customer interactions through reusable agent skills.

## Component Map
| Component | Purpose |
|---|---|
| infrastructure | Host OS image build, preparation, and minimal OS packaging |
| examples | Starter examples for bring-up and tryout |

## Available Skills
Skills are in `skills/`. Use trigger phrases to activate:
- `create-image`: Build Ubuntu 24.04 host images using ICT and validate output artifacts.
- `create-usb-installation-files`: Create `usb-installation-files.tar.gz` end-to-end, optionally chaining `create-image` when an ICT image is not already available.
- `validate-platform-config`: Validate post-provision platform readiness over SSH (k3s pods, binaries/path, cloud-init, network, proxy values, devices, GPU VFs).
- `tune-platform-power`: Apply CPU/GPU power profiles (battery, balanced, performance, graphical) on a provisioned Intel Core Ultra Series 3 node over SSH using the `tools/power-tuning/` scripts.
- `update-install-packages`: Update and install required packages on provisioned edge nodes.

## Skill Execution Order (MUST follow for all skills)
Every skill execution follows this mandatory sequence:
1. Collect required inputs
2. Run all preconditions
3. Execute build/deployment steps
4. Run validation checks
5. Report results and propose rollback if needed

Do not skip preconditions or validation.

## Build Order (MUST follow when full stack is requested)
1. host image creation (`create-image`)
2. USB installation artifact packaging (`create-usb-installation-files`)
3. host bring-up and provisioning
4. runtime/application deployment
5. benchmarking and validation

## Constraints
- Ask for confirmation before any `sudo` or destructive step.
- Never infer credentials, certificates, SSH keys, or secrets.
- Never overwrite user templates in place; copy to a new working template.
- Always report artifact paths and validation results at the end.

## Sudo Handling (MUST follow for all skills that invoke `sudo`)
Agent terminals are not always interactive TTYs, so a `sudo` password prompt
can silently fail — the command appears to "do nothing" with no prompt and no
output. Every skill that runs `sudo` MUST:

1. **Probe sudo state before any privileged step**:
   - Run `sudo -n true` and capture the exit code.
   - Exit 0 → cached creds or `NOPASSWD` in effect; proceed.
   - Non-zero → a password is required; do NOT run the privileged command yet.

2. **If a password is required, instruct the user (do not collect it via the agent)**:
   - Tell the user to run one of the following in their own terminal and then
     re-trigger the skill:
     - `sudo -v` — primes the sudo timestamp for ~5 minutes (safe, temporary).
     - Or add a scoped `NOPASSWD` entry for the specific binary the skill
       needs, e.g. in `/etc/sudoers.d/<skill-name>` via `sudo visudo -f`:
       ```
       <user> ALL=(root) NOPASSWD: /absolute/path/to/binary
       ```
   - Never request a password through `vscode_askQuestions` or any agent
     prompt. Never write a password into a script, env var, or log.
   - Do not suggest `NOPASSWD: ALL` — only scoped entries with absolute paths.

3. **Separate sudo failure from command failure** in reported exit codes so
   an auth failure is never misreported as a build/deploy failure.

4. **Do not retry** a privileged command after a sudo failure without first
   re-probing with `sudo -n true`.

## Quick Tryout Prompts
Use these prompts to test agent-driven development before writing your own skills:
1. `Use the create-image skill to build an Ubuntu 24.04 image from infrastructure/host-os/ict/generic-handheld-os-template.yml. Ask me for missing inputs first.`
2. `Run only preconditions and template validation for create-image, do not start the build yet.`
3. `Create a dry-run plan for create-image with commands and expected artifacts.`
4. `Use create-usb-installation-files to produce usb-installation-files.tar.gz using an existing ICT image at /path/to/image.raw.gz. Run preconditions first.`
5. `Run create-usb-installation-files from scratch: build the ICT image first, then package usb-installation-files.tar.gz, and report artifact paths.`
6. `Use validate-platform-config to verify a provisioned node over SSH and report checks for pods, k3s/kubectl binaries, cloud-init, networking, proxy values, devices, and GPU VFs.`
7. `Use tune-platform-power to switch a node to the battery profile over SSH (target=both). Run preconditions first and report pre/post snapshots.`
8. `Use tune-platform-power with target=gpu and gpu_profile=graphical over SSH; do a dry-run first.`
9. `Use update-install-packages to update and install required packages on provisioned system.  Ask me for the missing inputs first. Note: check for kernel update dependencies in infrastructure/installation-scripts/setup-kernel-depended-pkgs.sh if applicable.`
