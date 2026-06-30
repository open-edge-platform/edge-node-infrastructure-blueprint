<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Get Started

This guide walks you through provisioning an Intel edge node end-to-end: building installation artifacts on a developer system, writing them to a bootable USB, installing the OS on the target system, and validating the bring-up.

![Setup overview](./_assets/setup.svg)

The workflow involves two types of systems:

| System                   | Role                                                           |
| ------------------------ | -------------------------------------------------------------- |
| **Developer system**     | Builds the OS image and USB installation artifacts             |
| **Target (host) system** | The Intel edge node that will be provisioned and run workloads |

The process is divided into three phases:

1. **Phase 1** — Build bootable USB artifacts on the developer system
2. **Phase 2** — Prepare and boot from the USB on the target system
3. **Phase 3** — Validate bring-up and confirm services are running

Before starting, review the [System Requirements](./get-started/system-requirements.md).
=======

## Phase 1: Build Artifacts on the Developer System

The developer host OS can be either a baremetal Linux installation with docker or Windows Subsystem for Linux (WSL) with docker.

Follow the [Build from Source](./get-started/build-from-source.md) guide to clone the repository and produce `usb-installation-files.tar.gz`.

## Phase 2 and 3: Prepare USB and Validate Bring-Up

Follow the [Prepare USB and Validate](./get-started/prepare-usb.md) guide to write the artifacts to a bootable USB, provision the target system, and verify post-boot services.

## Troubleshooting

See the [Troubleshooting](./troubleshooting.md) guide for common issues and solutions.
=======

## Next Steps

- Use [Advanced Image Customization](./how-to/advanced-image-customization.md) if you want to build a custom image flavor.
- Run repeatable workflows through natural language using the agent skills described in the
  [AI Agent-Driven Development Strategy](https://github.com/open-edge-platform/edge-node-infrastructure-blueprint/blob/main/infrastructure/docs/agent-skills-guide.md)
  section.
- Expose Intel® accelerators to containerized workloads using the
  [Intel CDI Usage Guide](./how-to/configure-cdi.md).

<!--hide_directive
:::{toctree}
:hidden:

System Requirements <get-started/system-requirements.md>
Build from Source <get-started/build-from-source.md>
Prepare USB and Validate <get-started/prepare-usb.md>

:::
hide_directive-->
