<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Infrastructure - Agent Context File
> Build, validate, and package edge host infrastructure artifacts for Intel-based platforms.

## Scope
This context applies to the `infrastructure/` tree.

## Subcomponents
| Component | Purpose | Key Commands |
|---|---|---|
| host-os/ict | Build Ubuntu host images with image-composer-tool templates | `./image-composer-tool validate <template.yml>`, `sudo -E ./image-composer-tool build <template.yml>` |
| host-os | Host preparation and image support scripts | `bash host-os/prepare-host-img.sh` |
| micro-os | Minimal OS image build and packaging flow | `make -C micro-os`, `bash micro-os/build.sh` |

## Available Skills
Skills are defined under `.claude/skills/`.
- `create-image`: Build Ubuntu 24.04 host images via ICT and validate resulting artifacts.
- `validate-platform-config`: Validate a provisioned node over SSH for k3s health, cloud-init status, network/proxy setup, and hardware inventory.

## Constraints
- Never edit source templates in place; create and use a working copy.

