<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Troubleshooting

- Docker build fails: Recheck the Docker daemon and CLI proxy settings, then restart the Docker daemon.
- USB preparation fails: Verify the device path and available USB capacity.
- `kubectl` issues: Confirm that the Kubernetes installation has completed and the node status is `Ready`.
- GPU or NPU not detected: Inspect `dmesg` for driver load failures.
- OS installation fails: Set `installation_mode=true` in the `config-file`, rebuild the USB, and reboot to enable **Attended Mode** with interactive prompts. Optionally, run `/usr/local/bin/os-install.sh -i` on the Alpine OS terminal to launch the installer in interactive debug mode.
- After a successful OS provisioning reboot, if the edge node boots from USB and starts provisioning again, the Boot Override option is enabled in the target system BIOS. Disable Boot Override, or ensure USB is not the first option in the Boot Override list. Set the hard disk as the default boot option, then save and exit.
- System boots with an unexpected kernel after provisioning: If the system boots with any kernel version other than `linux-image-6.18.23-*`, set GRUB to boot the 6.18 entry.

  1. Verify installed kernels and current kernel:

	  ```bash
	  uname -r
	  dpkg -l | grep -E 'linux-image|linux-headers' | grep -E '6\.18|generic'
	  ```

  2. Set the default GRUB entry to the first Linux 6.18 menu entry and regenerate GRUB config:

	  ```bash
	  K_ID=$(sudo grep -E "menuentry '.*Linux 6.18" /boot/grub/grub.cfg | head -n1 | grep -oP "'gnulinux-.*?'" | tr -d "'") && \
	  S_ID=$(sudo grep -E "submenu " /boot/grub/grub.cfg | head -n1 | grep -oP "'gnulinux-.*?'" | tr -d "'") && \
	  sudo sed -i "s/^GRUB_DEFAULT=.*/GRUB_DEFAULT=\"$S_ID>$K_ID\"/" /etc/default/grub && \
	  sudo update-grub
	  ```

  3. Reboot and verify:

	  ```bash
	  sudo reboot
	  # after reboot
	  uname -r
	  ```
