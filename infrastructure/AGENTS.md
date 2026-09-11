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
Skills are defined under `skills/`.
- `create-image`: Build host images via the Image Composer Tool (ICT) and validate resulting artifacts.
- `create-usb-installation-files`: Package bootable USB installation artifacts (HookOS OS, host image, and deployment scripts) from an ICT image, Ubuntu ISO image, or previously built image.
- `validate-platform-config`: Validate a provisioned node for k3s health, cloud-init status, network or proxy setup, and hardware inventory.

## Constraints
- Never edit source templates in place; create and use a working copy.

