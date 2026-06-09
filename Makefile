# SPDX-FileCopyrightText: (C) 2024 Intel Corporation
# SPDX-License-Identifier: LicenseRef-Intel

all: 
	@# Help: Runs build, lint, test stages
	build lint test 	
	
build: 
	@# Help: Runs build stage
	@echo "---MAKEFILE BUILD---"
	@echo "Preparing USB Installation Artifacts $@"
	echo $@
	cd infrastructure/build-artifacts && sudo -E ./build-installation-artifacts.sh "$(MODE)" "$(ISO_URL)" "$(ICT_IMG)" && cd ../..
	@echo "---END MAKEFILE Build---"

lint:
	@# Help: Runs lint stage
	@echo "---MAKEFILE LINT---"
	echo $@
	@echo "---END MAKEFILE LINT---"

clean:
	@# Help: Runs test stage
	@echo "---MAKEFILE CLEAN---"
	echo $@
	cd infrastructure/build-artifacts && sudo rm -rf out/ && cd ../..
	cd infrastructure/host-os && sudo umount iso_mount  && sudo rm -rf iso_mount ubuntu-desktop-24.04* && cd ../..
	cd infrastructure/micro-os && sudo rm -rf out/ && cd ../..
	@echo "---END MAKEFILE TEST---"
	
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
	{ \
	  echo "SPDX-FileCopyrightText: (C) 2026 Intel Corporation"; \
	  echo "SPDX-License-Identifier: Apache-2.0"; \
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
	
