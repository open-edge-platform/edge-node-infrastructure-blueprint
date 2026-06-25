# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: LicenseRef-Intel

.PHONY: all build build-cdi-generator lint shellcheck clean coverage license list help
SHELL := bash -eu -o pipefail

# Find all shell scripts
SH_FILES := $(shell find . -type f -name '*.sh')

PROXY_FILE := proxy.env
ETC_ENV    := /etc/environment
# Environment variables for build commands.skip-proxy to bypass proxy checks, useful for CI environments where proxy settings are not needed.
# If proxy settings are detected under proxy.env, they will be loaded into ENV_PROXIES
# if not, ENV_PROXIES will be updated from /etc/environment. 
# if neither have valid proxy settings, the user will be prompted to proceed without proxy or abort the build.
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
			SYS_HTTP=$$( [ -f $(ETC_ENV) ] && grep -E -i "^HTTP_PROXY=" $(ETC_ENV) | head -n1 | cut -d'=' -f2 | tr -d '"' | tr -d "'" ); \
			SYS_HTTPS=$$( [ -f $(ETC_ENV) ] && grep -E -i "^HTTPS_PROXY=" $(ETC_ENV) | head -n1 | cut -d'=' -f2 | tr -d '"' | tr -d "'" ); \
			SYS_NO=$$( [ -f $(ETC_ENV) ] && grep -E -i "^NO_PROXY=" $(ETC_ENV) | head -n1 | cut -d'=' -f2 | tr -d '"' | tr -d "'" ); \
			\
			if [ -n "$$SYS_HTTP" ] && [ -n "$$SYS_HTTPS" ]; then \
				echo "System proxies found in $(ETC_ENV)! Syncing them into $(PROXY_FILE)..."; \
				echo "HTTP_PROXY=\"$$SYS_HTTP\"" > $(PROXY_FILE); \
				echo "HTTPS_PROXY=\"$$SYS_HTTPS\"" >> $(PROXY_FILE); \
				echo "NO_PROXY=\"$$SYS_NO\"" >> $(PROXY_FILE); \
				echo "http_proxy=\"$$SYS_HTTP\"" >> $(PROXY_FILE); \
				echo "https_proxy=\"$$SYS_HTTPS\"" >> $(PROXY_FILE); \
				echo "no_proxy=\"$$SYS_NO\"" >> $(PROXY_FILE); \
			else \
				# Both proxy.env and /etc/environment are empty \
				echo "No proxy configurations found in $(PROXY_FILE) or $(ETC_ENV)."; \
				echo -n "Do you want to proceed without a proxy? [y/N]: " && read ans; \
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
	
build-cdi-generator:
	@# Help: Build CDI GPU spec generator binary (requires Go 1.22+)
	@echo "---MAKEFILE BUILD CDI GENERATOR---"
	@CDI_BINARY="infrastructure/installation-scripts/cdi/intel-cdi-specs-generator-gpu"; \
	if [ -x "$$CDI_BINARY" ]; then \
		echo "CDI GPU generator already built, skipping"; \
	elif ! command -v go >/dev/null 2>&1; then \
		echo "WARNING: Go 1.22+ not found — skipping CDI GPU generator build. GPU CDI support will not be available."; \
	else \
		echo "Building CDI GPU spec generator (one-time)..."; \
		if bash infrastructure/installation-scripts/cdi/build-gpu-generator.sh; then \
			echo "CDI GPU generator built successfully"; \
		else \
			echo "WARNING: CDI GPU generator build failed. GPU CDI support will not be available."; \
		fi; \
	fi
	@echo "---END MAKEFILE BUILD CDI GENERATOR---"

build: check-proxy build-cdi-generator
	@# Help: Runs build stage
	@echo "---MAKEFILE BUILD---"
	@echo "Preparing USB Installation Artifacts $@"
	echo $@
	cd infrastructure/build-artifacts && . ../../$(PROXY_FILE) 2>/dev/null && sudo -E ./build-installation-artifacts.sh "$(MODE)" "$(ISO_URL)" "$(ICT_IMG)" && cd ../..
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

	@echo "--- CLEANING BUILD ARTIFACTS ---"
	@# The brackets prevent pkill from matching its own command string
	sudo -n pkill -9 -f "[q]emu-system" 2>/dev/null || true
	
	@echo "--> Freeing VNC port 99..."
	sudo -n lsof -t -i:99 | xargs sudo -n kill -9 2>/dev/null || true
	
	@echo "--> Lazy unmounting build directories..."
	@for mnt in $$(mount | grep -E 'infrastructure|iso_mounted' | awk '{print $$3}'); do \
		echo "  Unmounting $$mnt..."; \
		sudo -n umount -f -l "$$mnt" 2>/dev/null || true; \
	done

	@echo "Removing build artefacts..."
	@sudo -n rm -rf infrastructure/build-artifacts/out/
	@sudo -n rm -rf infrastructure/host-os/build/
	@sudo -n rm -rf infrastructure/host-os/ubuntu-desktop-24.04*
	@sudo -n rm -rf infrastructure/micro-os/build/ infrastructure/micro-os/output/
	@echo "---END MAKEFILE CLEAN---"
	
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
	
