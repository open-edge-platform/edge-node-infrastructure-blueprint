# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: LicenseRef-Intel

.PHONY: all build check-build-credentials build-cdi-generator lint shellcheck clean coverage license list help
SHELL := bash -eu -o pipefail

# Find all shell scripts, excluding ./ci
SH_FILES := $(shell find . -type f -name '*.sh' ! -path './ci/*' -print 2>/dev/null)
BASE_IMAGE := edge-base-builder:ubuntu24.04
BUILD_ARTIFACTS_IMAGE := build-edge-blueprint-artifacts:latest
MICRO_OS_IMAGE := micro-os-builder:ubuntu24.04
HOST_OS_IMAGE := host-os-builder:ubuntu24.04

MODE     ?= standard-image
ICT_IMG  ?=
DISABLE_BUILDKIT ?= false

export DOCKER_CLI_EXPERIMENTAL=enabled
ifeq ($(DISABLE_BUILDKIT),false)
export DOCKER_BUILDKIT=1
else
export DOCKER_BUILDKIT=0
endif

PROXY_TEMPLATE := .proxy.env
PROXY_FILE     := proxy.env
ETC_ENV        := /etc/environment
# Environment variables for build commands.skip-proxy to bypass proxy checks
# If proxy settings are detected under proxy.env, they will be loaded into ENV_PROXIES
# if not, ENV_PROXIES will be updated from /etc/environment.
# if neither have valid proxy settings, the user will be prompted to proceed without proxy or abort the build.

# Auto-create proxy.env from template if missing
$(PROXY_FILE): $(PROXY_TEMPLATE)
	@cp $(PROXY_TEMPLATE) $(PROXY_FILE)
	@echo "Created $(PROXY_FILE) from $(PROXY_TEMPLATE) — edit freely, it is git-ignored."

check-build-credentials:
	@if [[ "$(MODE)" != "image-from-tool" && ( -z "$${USERNAME:-}" || -z "$${PASSWORD:-}" ) ]]; then \
		echo "ERROR: USERNAME and PASSWORD must be exported and can't be null before building." >&2; \
		exit 1; \
	elif [[ "$(MODE)" != "image-from-tool" ]] && ! grep -Eq '^\$$6\$$[a-zA-Z0-9./]{1,16}\$$[a-zA-Z0-9./]{86}$$' <<< "$${PASSWORD}"; then \
		echo "ERROR: PASSWORD must be a valid SHA-512 crypt hash." >&2; \
		exit 1; \
	fi

check-docker:
	@# Help: Check if Docker is installed and functional
	@echo "Checking if Docker is installed..."
	@if ! command -v docker &> /dev/null; then \
		echo "ERROR: Docker is not installed. Please install Docker and try again."; \
		exit 1; \
	fi
	@echo "Testing Docker access..."
	@if ! docker ps &> /dev/null; then \
		echo ""; \
		echo "ERROR: Cannot run docker without sudo!"; \
		echo ""; \
		echo "Solution 1 (Recommended): Add user to docker group"; \
		echo "  sudo usermod -aG docker \$$USER"; \
		echo "  newgrp docker"; \
		echo "  Then try: make build"; \
		echo ""; \
		echo "Solution 2 (Quick): Use sudo"; \
		echo "  sudo make build"; \
		echo ""; \
		exit 1; \
	fi
	@echo "Pulling hello-world image to verify Docker functionality..."
	@if ! docker pull hello-world 2>&1 > /dev/null; then \
		echo ""; \
		echo "ERROR: Failed to pull hello-world image!"; \
		echo ""; \
		exit 1; \
	fi
	@echo "Checking docker buildx for BuildKit support..."
	@if ! docker buildx version &> /dev/null; then \
		echo "WARNING: docker buildx not found. To enable BuildKit, install it:"; \
		echo "  https://docs.docker.com/go/buildx/"; \
		exit 1; \
	else \
		echo "BuildKit/buildx is available"; \
	fi
	@echo "All Docker checks passed. Proceeding with build..."

check-proxy: $(PROXY_FILE)
	@if [ "$(skip-proxy)" = "true" ]; then \
		echo "Proxy explicitly skipped by user."; \
	else \
		# Source proxy.env to check if variables have actual data \
		FILE_HTTP=$$(file_val=$$(. ./$(PROXY_FILE) 2>/dev/null && echo "$$HTTP_PROXY$$http_proxy"); echo $$file_val); \
		FILE_HTTPS=$$(file_val=$$(. ./$(PROXY_FILE) 2>/dev/null && echo "$$HTTPS_PROXY$$https_proxy"); echo $$file_val); \
		\
		if [ -n "$$FILE_HTTP" ] && [ -n "$$FILE_HTTPS" ]; then \
			echo "Valid proxy settings detected inside $(PROXY_FILE)."; \
		else \
			echo "$(PROXY_FILE) contains empty values. Checking $(ETC_ENV)..."; \
			\
			# Extract proxy values directly from /etc/environment if it exists \
			SYS_HTTP=$$( [ -f $(ETC_ENV) ] && grep -E -i "^HTTP_PROXY=" $(ETC_ENV) | head -n1 | cut -d'=' -f2 | tr -d '"' | tr -d "'" || true ); \
			SYS_HTTPS=$$( [ -f $(ETC_ENV) ] && grep -E -i "^HTTPS_PROXY=" $(ETC_ENV) | head -n1 | cut -d'=' -f2 | tr -d '"' | tr -d "'" || true ); \
			SYS_NO=$$( [ -f $(ETC_ENV) ] && grep -E -i "^NO_PROXY=" $(ETC_ENV) | head -n1 | cut -d'=' -f2 | tr -d '"' | tr -d "'" || true ); \
			\
			if [ -n "$$SYS_HTTP" ] && [ -n "$$SYS_HTTPS" ]; then \
				echo "System proxies found in $(ETC_ENV)! Syncing them into $(PROXY_FILE)..."; \
				sudo chown "$$(id -u):$$(id -g)" $(PROXY_FILE) 2>/dev/null || true; \
				printf 'HTTP_PROXY="%s"\nHTTPS_PROXY="%s"\nNO_PROXY="%s"\nhttp_proxy="%s"\nhttps_proxy="%s"\nno_proxy="%s"\n' \
					"$$SYS_HTTP" "$$SYS_HTTPS" "$$SYS_NO" \
					"$$SYS_HTTP" "$$SYS_HTTPS" "$$SYS_NO" > $(PROXY_FILE); \
			else \
				# Both proxy.env and /etc/environment are empty \
				echo "No proxy configurations found in $(PROXY_FILE) or $(ETC_ENV)."; \
				read -p "Do you want to proceed without a proxy? [y/N]: " ans < /dev/tty; \
				if [ "$$ans" != "y" ] && [ "$$ans" != "Y" ]; then \
					echo "Build aborted. Please populate $(PROXY_FILE) or configure system proxies."; \
					exit 1; \
				fi; \
				echo "Proceeding without proxy..."; \
			fi; \
		fi; \
	fi


all: 
	@# Help: Runs build, lint, test stages
	build lint test 	

# Prepare base image with common dependencies
build-base:
	@echo "Building base image: $(BASE_IMAGE)"
	@set -a; . $(PROXY_FILE) 2>/dev/null || true; set +a; \
	docker build \
		--build-arg http_proxy="$${http_proxy:-}" \
		--build-arg https_proxy="$${https_proxy:-}" \
		--build-arg no_proxy="$${no_proxy:-}" \
		--build-arg HTTP_PROXY="$${HTTP_PROXY:-}" \
		--build-arg HTTPS_PROXY="$${HTTPS_PROXY:-}" \
		--build-arg NO_PROXY="$${NO_PROXY:-}" \
		-f infrastructure/enib-base-container/Dockerfile \
		-t $(BASE_IMAGE) \
		infrastructure/enib-base-container

build: check-build-credentials check-proxy check-docker build-base
	@echo "---MAKEFILE BUILD---"
	@echo "Preparing USB Installation Artifacts (containerized in Ubuntu 24.04)"
	@set -a; . $(PROXY_FILE) 2>/dev/null || true; set +a; \
	cd $(dir $(abspath $(firstword $(MAKEFILE_LIST)))) && \
	ICT_MOUNT_ARGS=""; \
	CONTAINER_ICT_IMG=""; \
	if [ "$(MODE)" = "image-from-tool" ]; then \
		if [ -z "$(ICT_IMG)" ]; then \
			echo "ERROR: MODE=image-from-tool requires ICT_IMG=/path/to/image.raw.gz" >&2; \
			echo "Example: make build MODE=image-from-tool ICT_IMG=/home/user/images/minimal-desktop-ubuntu-24.04.raw.gz" >&2; \
			exit 1; \
		fi; \
		case "$(ICT_IMG)" in \
			/*) ICT_ABS="$(ICT_IMG)" ;; \
			*)  ICT_ABS="$$(readlink -m "$(ICT_IMG)")" ;; \
		esac; \
		ICT_DIR="$$(dirname "$$ICT_ABS")"; \
		ICT_BASE="$$(basename "$$ICT_ABS")"; \
		case "$$ICT_BASE" in \
			*.raw.gz|*.raw.img.gz) ;; \
			*) echo "ERROR: ICT_IMG must end in .raw.gz or .raw.img.gz (got: $$ICT_BASE)" >&2; exit 1;; \
		esac; \
		if [ ! -f "$$ICT_ABS" ] && [ ! -r "$$ICT_ABS" ]; then \
			if ! sudo test -f "$$ICT_ABS"; then \
				echo "ERROR: ICT_IMG not found on host: $$ICT_ABS" >&2; \
				echo "Hint: ICT typically writes images under ~/ict/builds or ~/ict/workspace as root when built with 'sudo -E ./image-composer-tool build'." >&2; \
				exit 1; \
			fi; \
			echo "Note: ICT_IMG is root-owned; container (privileged) will read it via bind mount."; \
		fi; \
		ICT_MOUNT_ARGS="-v $$ICT_DIR:/ict-image-src:ro"; \
		CONTAINER_ICT_IMG="/ict-image-src/$$ICT_BASE"; \
		echo "ICT image (host):      $$ICT_ABS"; \
		echo "ICT image (container): $$CONTAINER_ICT_IMG"; \
	fi; \
	echo "Building orchestrator image: $(BUILD_ARTIFACTS_IMAGE)"; \
	docker build \
		--build-arg http_proxy="$${http_proxy:-}" \
		--build-arg https_proxy="$${https_proxy:-}" \
		--build-arg no_proxy="$${no_proxy:-}" \
		--build-arg HTTP_PROXY="$${HTTP_PROXY:-}" \
		--build-arg HTTPS_PROXY="$${HTTPS_PROXY:-}" \
		--build-arg NO_PROXY="$${NO_PROXY:-}" \
		-f infrastructure/build-artifacts/Dockerfile \
		-t $(BUILD_ARTIFACTS_IMAGE) \
		. && \
	docker run --rm \
		--privileged \
		--network host \
		-e http_proxy="$${http_proxy:-}" \
		-e https_proxy="$${https_proxy:-}" \
		-e no_proxy="$${no_proxy:-}" \
		-e HTTP_PROXY="$${HTTP_PROXY:-}" \
		-e HTTPS_PROXY="$${HTTPS_PROXY:-}" \
		-e NO_PROXY="$${NO_PROXY:-}" \
		-e MICRO_OS_REBUILD="$${MICRO_OS_REBUILD:-false}" \
		-e HOST_OS_REBUILD="$${HOST_OS_REBUILD:-false}" \
		-e ENABLE_SWAP_RESUME="$${ENABLE_SWAP_RESUME:-0}" \
		-e USERNAME="$${USERNAME:-}" \
		-e PASSWORD="$${PASSWORD:-}" \
		-e HOST_REPO_ROOT="$$PWD" \
		-e HOST_UID="$$(id -u)" \
		-e HOST_GID="$$(id -g)" \
		-v "$$PWD":/workspace \
		-v /var/run/docker.sock:/var/run/docker.sock \
		$$ICT_MOUNT_ARGS \
		$(BUILD_ARTIFACTS_IMAGE) \
		"$(MODE)" "$$CONTAINER_ICT_IMG"
	@echo "---END MAKEFILE Build---"

lint: shellcheck
	@# Help: Runs lint stage
	@echo "---MAKEFILE LINT---"
	echo $@
	@echo "---END MAKEFILE LINT---"
# https://github.com/koalaman/shellcheck
shellcheck:
	@# Help: Lint shell scripts with shellcheck
	shellcheck --version
	shellcheck -x -S style \
		$(SH_FILES)

clean:

	@echo "---MAKEFILE CLEAN---"
	docker run --rm --privileged \
		--entrypoint /bin/bash \
		-v "$$PWD":/workspace \
		$(BUILD_ARTIFACTS_IMAGE) \
		bash -c "rm -rf /workspace/infrastructure/build-artifacts/out /workspace/infrastructure/host-os/*.raw.img* /workspace/infrastructure/host-os/build /workspace/infrastructure/micro-os/build" || true
	docker rmi -f $(BUILD_ARTIFACTS_IMAGE) 2>/dev/null || true
	docker rmi -f $(MICRO_OS_IMAGE) 2>/dev/null || true
	docker rmi -f $(HOST_OS_IMAGE) 2>/dev/null || true
	sudo rm -rf infrastructure/build-artifacts/out infrastructure/host-os/build infrastructure/micro-os/output
	@echo "---END MAKEFILE CLEAN---"

clean-all: clean
	@# Help: Clean all including base image (use when base dependencies change)
	@echo "Removing base image: $(BASE_IMAGE)"
	docker rmi -f $(BASE_IMAGE) 2>/dev/null || true
	docker builder prune -f
	@echo "---END CLEAN ALL---"
	
coverage:
	@# Help: Runs coverage stage
	@echo "---MAKEFILE COVERAGE---"
	echo $@
	@echo "---END MAKEFILE COVERAGE---"

license: 
	## Check licensing with the reuse tool.
	reuse --version
	reuse --root . lint

list: 
	@# Help: displays make targets
	help

help:	
	@printf "%-20s %s\n" "Target" "Description"
	@printf "%-20s %s\n" "------" "-----------"
	@make -pqR : 2>/dev/null \
        | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' \
        | sort \
        | egrep -v -e '^[^[:alnum:]]' -e '^$@$$' \
        | xargs -I _ sh -c 'printf "%-20s " _; make _ -nB | (grep -i "^# Help:" || echo "") | tail -1 | sed "s/^# Help: //g"'
	
