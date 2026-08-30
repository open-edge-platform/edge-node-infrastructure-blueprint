<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Edge Node Infrastructure Blueprint - Agent Context File
> Build and validate Intel edge node host images and infrastructure workflows for AI-ready deployments.

## Platform Overview
This repository enables repeatable edge infrastructure bring-up for Intel-based systems, with a focus on host OS image generation, provisioning readiness, and follow-on runtime enablement.
- Build Ubuntu OS-based host images for Intel hardware.
- Prepare artifacts for deployment, validation, and benchmarking workflows.
- Standardize team and customer interactions through reusable agent skills.

## Component Map
| Component | Purpose |
|---|---|
| infrastructure | Host OS image build, preparation, and minimal OS packaging |
| examples | Starter examples for bring-up and tryout |

## Available Skills
Skills are in `skills/`. Use trigger phrases to activate:
- `create-image`: Build Ubuntu OS version 24.04 host images using the Image Composer Tool (ICT) and validate output artifacts.
- `create-usb-installation-files`: Create `usb-installation-files.tar.gz` end-to-end, optionally chaining `create-image` when an ICT image is not already available.
- `validate-platform-config`: Validate post-provision platform readiness over SSH [lightweight Kubernetes distribution (k3s) pods, binaries and path, cloud-init, network, proxy values, devices, and GPU virtual functions (VFs)].
- `set-power-profile`: Set the platform power with `tools/power-tuning/set_power_profile.sh` — either a named profile (LowPower 10 W, BalancedLow 15 W, BalancedHigh 20 W, Performance 25 W, MaxPerformance = platform max / cTDP Level 2) by PkgWatt budget, or a `Custom` envelope with an explicit PkgWatt (PL1, multiples of 5 up to cTDP Level 2), an optional independent SysWatt (psys) cap, a configurable burst ratio, and a PL1 time window (tau). PkgWatt (the package cap) is enforced on every platform; each profile has a default burst ratio (overridable), and on psys-capable silicon the SysWatt cap tracks the PkgWatt budget or an explicit `--sysWatt` value when supplied.
- `generate-platform-stress`: Generate configurable CPU and integrated-GPU load locally with `tools/power-tuning/stress_gen.sh` (stress-ng) — command-line control of worker count, per-CPU load percentage, GPU worker count, and duration.
- `generate-openvino-stress`: Generate sustained AI inference load on CPU, GPU, or NPU locally with `tools/power-tuning/openvino_stress.sh` (OpenVINO `benchmark_app` in a K3s pod or Docker container) — real neural-network inference stress (unlike stress-ng synthetic load), with control of target device, container runtime (auto-detected), iterations or duration, thread count, and synchronous or asynchronous API mode. Ideal for validating power profiles under realistic AI workloads and thermal qualification with real compute patterns.
- `monitor-power-thermal`: Run a live power and thermal monitor locally with `tools/power-tuning/pt_mon.sh` (turbostat) — samples PkgTmp and the RAPL domains (PkgWatt, CorWatt, GFXWatt, RAMWatt, SysWatt) at a fixed interval and logs to `pt_mon.txt`.
- `set-thermal-profile`: Set the thermal escalation policy with `tools/power-tuning/set_thermal_profile.sh` — generate, validate, apply and verify a thermald `thermal-conf.xml` that stages Fan (active) < Processor (passive) < intel_powerclamp (passive) trip points on the CPU package sensor. Choose a named profile (cool 55/70/80, warm 60/75/85, hot 70/90/95, or thermal-max 95/100/104 °C) or `custom` trips, optionally add the CHRG device, make thermald the sole thermal authority, or `--disable` to revert to the kernel default thermal control.
- `combined-power-thermal-profiling`: Orchestrate a full profiling session — chain `set-power-profile` → `set-thermal-profile` → `monitor-power-thermal` → `generate-platform-stress` (apply → monitor → stress → summarize) with a single confirmation and a bounded `duration`, then emit one consolidated enclosure report (min, mean, and maximum of PkgTmp, PkgWatt, and GFXWatt plus a throttle or headroom verdict). Use to qualify whether an enclosure can sustain a chosen profile under load.
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

## Human-in-the-Loop Policy (MUST follow for all skills)
Agents are guided assistants, not autonomous operators. Read-only local
preconditions may run without confirmation. Before any operation that changes
state, uses `sudo`, downloads external content, connects to a remote system,
starts a container or workload, changes hardware tuning, or creates, replaces,
or deletes artifacts, the agent MUST:

1. Render the exact resolved command or a complete table of the commands,
   inputs, target host, affected files/devices, expected side effects, and
   rollback or stop action.
2. Obtain an explicit `yes` or `y` from the user immediately before execution.
   Do not infer approval from the initial request, a prior approval, or a
   `dry_run` result.
3. Treat any changed parameter, target, command, or side effect as a new plan
   requiring a new confirmation. A single confirmation may authorize a combined
   skill only when its displayed plan enumerates every mutating stage.
4. Stop on any other response and record `CONFIRMATION=declined`.

`auto_confirm` and similar flags MUST NOT bypass this policy. Agents may not
silently execute state-changing commands, even when non-interactive sudo has
been preconfigured.

## Sudo Handling (MUST follow for all skills that invoke `sudo`)
Agent terminals are not always interactive teletypewriters (TTYs), so a `sudo` password prompt
can silently fail — the command appears to "do nothing" with no prompt and no
output. Every skill that runs `sudo` MUST:

1. **Probe sudo state before any privileged step**:
   - Run `sudo -n true` and capture the exit code.
   - Exit 0 → cached credentials or `NOPASSWD` in effect; proceed.
   - Non-zero → a password is required; do NOT run the privileged command yet.

2. **If a password is required, instruct the user (do not collect it via the agent)**:
    - Tell the user to add a scoped `NOPASSWD` entry for each specific binary the
       skill needs, for example in `/etc/sudoers.d/<skill-name>` via
       `sudo visudo -f /etc/sudoers.d/<skill-name>`, then re-trigger the skill:
       ```
       <user> ALL=(root) NOPASSWD: /absolute/path/to/binary
       ```
    - Never request passwords, tokens, SSH keys, private keys, or other secrets
       through `vscode_askQuestions` or any agent prompt. Never write them into a
       script, env var, or log.
    - Do not recommend global sudo timestamps or `NOPASSWD: ALL`; permit only
       scoped entries containing the absolute paths of required binaries.

3. **Separate sudo failure from command failure** in reported exit codes so
   an authentication failure is never misreported as a build/deploy failure.

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
7. `Use update-install-packages to update and install required packages on provisioned system.  Ask me for the missing inputs first. Note: check for kernel update dependencies in infrastructure/installation-scripts/setup-kernel-depended-pkgs.sh if applicable.`
