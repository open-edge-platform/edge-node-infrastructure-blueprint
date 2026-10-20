# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: LicenseRef-Intel
# Makefile — Edge Node Infrastructure Blueprint (ENIB) installer
#
# Usage:
#   sudo make -f app.Makefile docker   # Docker-based system
#   sudo make -f app.Makefile k3s      # k3s-based system
#

SCRIPTS := infrastructure/installation-scripts
SHELL := bash

.PHONY: docker k3s prereqs resources common

docker: prereqs resources
	$(SCRIPTS)/install-docker.sh
	$(MAKE) common
	@echo "Docker installed. Exit and log in again to ensure that the 'docker' command works correctly."

k3s: prereqs resources
	$(SCRIPTS)/install-k3s.sh
	systemctl start k3s
	$(SCRIPTS)/install-helm.sh
	$(SCRIPTS)/install-intel-device-plugins.sh
	$(MAKE) common

prereqs:
	@if [[ $$EUID -ne 0 ]]; then \
		echo "ERROR: the target must be run as root" >&2; \
		exit 1; \
	fi
	apt install -y make git curl

resources:
	$(SCRIPTS)/download-resources.sh

common:
	apt update && apt install -y chrony 
	$(MAKE) -C $(SCRIPTS) realsense cdi
	$(MAKE) -C tools power-tuning system-info
 