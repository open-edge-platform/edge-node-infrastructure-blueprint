# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: LicenseRef-Intel

.PHONY: all build lint shellcheck clean coverage license list help
SHELL := bash -eu -o pipefail

# Find all shell scripts
SH_FILES := $(shell find . -type f -name '*.sh' 2>/dev/null)

BASE_IMAGE := edge-base-builder:ubuntu24.04
BUILD_ARTIFACTS_IMAGE := build-edge-blueprint-artifacts:latest
MICRO_OS_IMAGE := micro-os-builder:ubuntu24.04
HOST_OS_IMAGE := host-os-builder:ubuntu24.04

MODE     ?= standard-image
ICT_IMG  ?=

export DOCKER_BUILDKIT=1
export DOCKER_CLI_EXPERIMENTAL=enabled

PROXY_FILE := proxy.env
ETC_ENV    := /etc/environment
# Environment variables for build commands.skip-proxy to bypass proxy checks
# If proxy settings are detected under proxy.env, they will be loaded into ENV_PROXIES
# if not, ENV_PROXIES will be updated from /etc/environment. 
# if neither have valid proxy settings, the user will be prompted to proceed without proxy or abort the build.
check-docker:
	@# Help: Check if Docker is installed and functional
	@echo "Checking if Docker is installed..."
	@if ! command -v docker &> /dev/null; then \
		echo "ERROR: Docker is not installed. Please install Docker and try again."; \
		exit 1; \
	fi
	@echo "Docker found. Testing Docker with hello-world image..."
	@if ! docker pull hello-world; then \
		echo "ERROR: Failed to pull hello-world image. Docker may not be properly configured. check proxy settings or Docker daemon."; \
		exit 1; \
	fi
	@echo "Docker is installed and functional. Proceeding with next steps..."

check-proxy:
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

build: check-proxy check-docker build-base
	@echo "---MAKEFILE BUILD---"
	@echo "Preparing USB Installation Artifacts (containerized in Ubuntu 24.04)"
	@set -a; . $(PROXY_FILE) 2>/dev/null || true; set +a; \
	cd $(dir $(abspath $(firstword $(MAKEFILE_LIST)))) && \
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
		-e HOST_REPO_ROOT="$$PWD" \
		-e HOST_UID="$$(id -u)" \
		-e HOST_GID="$$(id -g)" \
		-v "$$PWD":/workspace \
		-v /var/run/docker.sock:/var/run/docker.sock \
		$(BUILD_ARTIFACTS_IMAGE) \
		"$(MODE)" "$(ICT_IMG)"
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
		-e SC1001,SC1003,SC1090,SC1091,SC2001,SC2002,SC2006,SC2012,SC2015,SC2016,SC2028,SC2034,SC2046,SC2048,SC2053,SC2064,SC2086,SC2094,SC2112,SC2124,SC2128,SC2140,SC2145,SC2155,SC2162,SC2164,SC2179,SC2181,SC2231,SC2252,SC2320 \
		$(SH_FILES)

clean:
	@# Help: Runs clean stage
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

ICT_DIR              := infrastructure/host-os/ict
ICT_PATCH            := $(ICT_DIR)/generic-handheld-os-template.patch
ICT_FINAL            := $(ICT_DIR)/generic-handheld-os-template.yml
ICT_UPSTREAM_REPO    := open-edge-platform/image-composer-tool
ICT_UPSTREAM_PATH    := image-templates/ubuntu24-x86_64-minimal-ptl-pv-raw.yml
ICT_UPSTREAM_SHA     := b21499751a1e50677bbf2b4ea4517adcb67da7d8
ICT_UPSTREAM_RAW_URL := https://raw.githubusercontent.com/$(ICT_UPSTREAM_REPO)/$(ICT_UPSTREAM_SHA)/$(ICT_UPSTREAM_PATH)

ict-refresh-upstream:
	@# Help: Fetch upstream ICT template at ICT_UPSTREAM_SHA & apply the patch to regenerate template
	@echo "---MAKEFILE ICT REFRESH UPSTREAM---"
	@set -eu; \
	UPSTREAM_BASENAME="$$(basename $(ICT_UPSTREAM_PATH))"; \
	TMP_DIR="$$(mktemp -d)"; \
	TMP_UPSTREAM="$$TMP_DIR/$$UPSTREAM_BASENAME"; \
	TMP_REGEN="$$TMP_DIR/regen.yml"; \
	KEEP_ON_FAIL=0; \
	trap '[ $$KEEP_ON_FAIL -eq 0 ] && rm -rf "$$TMP_DIR" || echo "Fetched upstream kept at: $$TMP_UPSTREAM"' EXIT; \
	echo "Fetching upstream @ $(ICT_UPSTREAM_SHA)"; \
	echo "  URL: $(ICT_UPSTREAM_RAW_URL)"; \
	curl -fsSL "$(ICT_UPSTREAM_RAW_URL)" -o "$$TMP_UPSTREAM"; \
	echo "Dry-run applying $(ICT_PATCH) on the fetched upstream..."; \
	if ! patch --dry-run -s -o "$$TMP_REGEN" "$$TMP_UPSTREAM" < $(ICT_PATCH); then \
	  KEEP_ON_FAIL=1; \
	  echo "ERROR: patch does not apply cleanly on the fetched upstream."; \
	  echo "Resolve rejected hunks manually in $(ICT_FINAL) and regenerate $(ICT_PATCH)."; \
	  exit 1; \
	fi; \
	patch -s -o "$$TMP_REGEN" "$$TMP_UPSTREAM" < $(ICT_PATCH); \
	cp "$$TMP_REGEN" $(ICT_FINAL); \
	echo "Regenerating $(ICT_PATCH) with refreshed SHA label..."; \
	SPDX_TAG="SPDX-License-Identifier"; \
	{ \
	  echo "SPDX-FileCopyrightText: (C) 2026 Intel Corporation"; \
	  echo "$$SPDX_TAG: Apache-2.0"; \
	  echo ""; \
	  diff -u \
	    --label "a/$$UPSTREAM_BASENAME (upstream @ $(ICT_UPSTREAM_SHA))" \
	    --label "b/$$(basename $(ICT_FINAL))" \
	    "$$TMP_UPSTREAM" $(ICT_FINAL) || [ $$? -eq 1 ]; \
	} > $(ICT_PATCH); \
	echo "Round-trip verification..."; \
	patch -s -o "$$TMP_REGEN" "$$TMP_UPSTREAM" < $(ICT_PATCH); \
	diff -q "$$TMP_REGEN" $(ICT_FINAL)
	@echo "---END MAKEFILE ICT REFRESH UPSTREAM---"

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
	
