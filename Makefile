# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: LicenseRef-Intel

.PHONY: all build lint shellcheck clean coverage license list help
SHELL := bash -eu -o pipefail

# Find all shell scripts
SH_FILES := $(shell find . -type f -name '*.sh')

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
	echo $@
	cd infrastructure/build-artifacts && sudo rm -rf out/ && cd ../..
	cd infrastructure/host-os && sudo umount iso_mount  && sudo rm -rf iso_mount ubuntu-desktop-24.04* && cd ../..
	cd infrastructure/micro-os && sudo rm -rf out/ && cd ../..
	@echo "---END MAKEFILE CLEAN---"
	
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
	
