<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->
# Intel System Info Script

This README explains what `system-info.sh` is used for and how to run it.

## What this script is used for

`system-info.sh` is a diagnostic script for **Intel Panther Lake (PTL)** systems on **Ubuntu/Linux**.

It collects a full platform report, including:
- PTL platform detection (CPU family/model checks)
- CPU details, hybrid P/E/LP-E topology, frequencies, and power settings
- Memory, storage, and network information
- Intel GPU (Xe3) driver/runtime status (`xe`, Vulkan, VA-API, OpenGL)
- Intel NPU status (`ivpu`/`intel_vpu`), firmware, and related logs
- AI/compute runtime checks (OpenCL, Level Zero, OpenVINO)
- Thermals, RAPL power limits, battery/power supply, BIOS/firmware/security info
- Intel-related package inventory and recommended package list

Use it when you need to:
- Validate PTL bring-up on Ubuntu
- Troubleshoot driver/firmware/runtime issues
- Capture a full system snapshot for debugging or support

## Requirements

- Ubuntu/Linux shell environment
- Common tools available on the system (`bash`, `lscpu`, `lsblk`, `ip`, etc.)
- Optional tools improve report depth (`dmidecode`, `turbostat`, `intel_gpu_top`, `vulkaninfo`, `vainfo`, `clinfo`, `fwupdmgr`, etc.)
- `sudo` recommended for full visibility (firmware, DMI, turbostat, some dmesg paths)

## How to run

Step into the target system. From the folder containing the script (recommend sudo for a more complete report):

```bash
cd /opt/edge/developer/tools/system-info
sudo ./system-info.sh
```

Save output to a file:

```bash
sudo ./system-info.sh > sys-info.txt 2>&1
```

## Notes

- The script is read/inspect oriented and prints results to standard output.
- Some sections will show warnings or "not installed" messages if optional tools are missing.
- If PTL is not detected (CPUID mismatch), the script still runs and reports what it finds.