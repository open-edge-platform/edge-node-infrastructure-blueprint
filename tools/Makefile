# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:
INTEL_LPMD_COMMIT ?= 956df747e56aca1739b39bff8cff77e81758af9a
PCM_COMMIT ?= abb6bce87cc2ed23d6677541ebcfc47ca769d1ed

.PHONY: power-tuning system-info lpmd pcm

power-tuning: lpmd pcm
	if [[ $$EUID -ne 0 ]]; then
		echo "ERROR: the lpmd target must be run as root (e.g. sudo make lpmd)." >&2
		exit 1
	fi
	apt-get update
	apt-get install -y sysbench msr-tools lm-sensors "linux-tools-$$(uname -r)" stress-ng # needs docker
	mkdir -p /opt/edge/developer/tools/
	cp -r power-tuning /opt/edge/developer/tools/power-tuning
	echo "power-tuning installed"

system-info:
	if [[ $$EUID -ne 0 ]]; then
		echo "ERROR: the system-info target must be run as root (e.g. sudo make system-info)." >&2
		exit 1
	fi
	mkdir -p /opt/edge/developer/tools/
	cp -r system-info /opt/edge/developer/tools/system-info
	echo "system-info installed"

lpmd:
	if [[ $$EUID -ne 0 ]]; then
		echo "ERROR: the lpmd target must be run as root (e.g. sudo make lpmd)." >&2
		exit 1
	fi
	apt-get update
	apt-get install -y autoconf autoconf-archive gcc libglib2.0-dev libdbus-1-dev libxml2-dev libnl-3-dev \
		libnl-genl-3-dev libsystemd-dev systemd-dev gtk-doc-tools libupower-glib-dev automake
	cd /tmp
	rm -rf lpmd
	git clone https://github.com/intel/intel-lpmd.git lpmd
	cd lpmd
	git checkout "$(INTEL_LPMD_COMMIT)" || { echo "ERROR: Failed to checkout intel-lpmd commit $(INTEL_LPMD_COMMIT)"; exit 1; }
	ACTUAL_COMMIT=$$(git rev-parse HEAD)
	if [[ "$$ACTUAL_COMMIT" != "$(INTEL_LPMD_COMMIT)" ]]; then
		echo "ERROR: intel-lpmd commit verification failed: expected $(INTEL_LPMD_COMMIT), got $$ACTUAL_COMMIT"
		exit 1
	fi
	./autogen.sh
	# configure skips installing the systemd unit (HAVE_SYSTEMD) when it
	# can't resolve systemdsystemunitdir via pkg-config; fail fast instead
	# of hitting a cryptic "systemctl enable" error later.
	if [[ -z "$$(pkg-config --variable=systemdsystemunitdir systemd 2>/dev/null)" ]]; then
		echo "ERROR: pkg-config could not resolve systemd's systemdsystemunitdir (is the systemd-dev package installed?)." >&2
		exit 1
	fi
	make
	make install
	# Remove restrictive hardware conditions so the service attempts to start
	# on all platforms. The daemon itself will exit gracefully if unsupported.
	mkdir -p /etc/systemd/system/intel_lpmd.service.d
	tee /etc/systemd/system/intel_lpmd.service.d/override.conf > /dev/null <<-EOF
		[Unit]
		# Clear all Condition* directives from the upstream unit
		ConditionPathExists=
		ConditionVirtualization=
	EOF
	# NOTE: Not purging build dependencies — they are shared with dkms,
	# build-essential, intel-mipi-gmsl-dkms, and librealsense2-dkms.
	apt-get clean
	# Enable service
	systemctl --root=/ enable intel_lpmd.service
	cd /tmp
	rm -rf lpmd
	echo "Installed intel-lpmd"

pcm:
	if [[ $$EUID -ne 0 ]]; then
		echo "ERROR: the pcm target must be run as root (e.g. sudo make pcm)." >&2
		exit 1
	fi
	apt-get update
	apt-get install -y build-essential cmake make git
	cd /tmp
	rm -rf pcm
	git clone https://github.com/intel/pcm.git
	cd pcm
	git checkout "$(PCM_COMMIT)" || { echo "ERROR: Failed to checkout PCM commit $(PCM_COMMIT)"; exit 1; }
	ACTUAL_COMMIT=$$(git rev-parse HEAD)
	if [[ "$$ACTUAL_COMMIT" != "$(PCM_COMMIT)" ]]; then
		echo "ERROR: PCM commit verification failed: expected $(PCM_COMMIT), got $$ACTUAL_COMMIT"
		exit 1
	fi
	git submodule update --init --recursive
	mkdir build
	cd build
	cmake ..
	make -j"$$(nproc)"
	cp -r bin/* /usr/local/bin/
	echo 'msr' | tee /etc/modules-load.d/intel-pcm.conf > /dev/null
	cd /tmp
	rm -rf pcm
	echo "Installed pcm"
