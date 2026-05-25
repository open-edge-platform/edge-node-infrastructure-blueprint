<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Edge Node Infrastructure Blueprint - Agent Context File
> Build and validate Intel edge node host images and infrastructure workflows for AI-ready deployments.

## Platform Overview
This repository enables repeatable edge infrastructure bring-up for Intel-based systems, with a focus on host OS image generation, provisioning readiness, and follow-on runtime enablement.
- Build Ubuntu-based host images for Intel PTL and similar targets.
- Prepare artifacts for deployment, validation, and benchmarking workflows.
- Standardize team and customer interactions through reusable agent skills.

## Component Map
| Component | Purpose |
|---|---|
| infrastructure | Host OS image build, preparation, and minimal OS packaging |
| examples | Starter examples for bring-up and tryout |

## Available Skills
Skills are in `.claude/skills/`. Use trigger phrases to activate:
- `create-image`: Build Ubuntu 24.04 host images using ICT and validate output artifacts.
- `create-usb-installation-files`: Create `usb-installation-files.tar.gz` end-to-end, optionally chaining `create-image` when an ICT image is not already available.
- `validate-platform-config`: Validate post-provision platform readiness over SSH (k3s pods, binaries/path, cloud-init, network, proxy values, devices, GPU VFs).

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

## Quick Tryout Prompts
Use these prompts to test agent-driven development before writing your own skills:
1. `Use the create-image skill to build an Ubuntu 24.04 PTL image from infrastructure/host-os/ict/ubuntu24-x86_64-minimal-ptl.yml. Ask me for missing inputs first.`
2. `Run only preconditions and template validation for create-image, do not start the build yet.`
3. `Create a dry-run plan for create-image with commands and expected artifacts.`
4. `Use create-usb-installation-files to produce usb-installation-files.tar.gz using an existing ICT image at /path/to/image.raw.gz. Run preconditions first.`
5. `Run create-usb-installation-files from scratch: build the ICT image first, then package usb-installation-files.tar.gz, and report artifact paths.`
6. `Use validate-platform-config to verify a provisioned node over SSH and report checks for pods, k3s/kubectl binaries, cloud-init, networking, proxy values, devices, and GPU VFs.`
