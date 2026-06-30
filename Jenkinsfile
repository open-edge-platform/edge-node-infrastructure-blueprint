// SPDX-FileCopyrightText: (C) 2026 Intel Corporation
// SPDX-License-Identifier: Apache-2.0

// Dynamic parameters: ICT_IMG and ICT_BUILD_JOB only appear when BUILD_MODE=ict-based.
// Requires "Active Choices" plugin (uno-choice) for full dynamic visibility.
// Without the plugin, all parameters are shown but ICT-only ones are ignored in script-based mode.

properties([
    parameters([
        choice(
            name: 'BUILD_MODE',
            choices: ['script-based', 'ict-based', 'reuse-image'],
            description: 'script-based: build from Ubuntu ISO; ict-based: build with Image Composer Tool; reuse-image: skip image build, reuse previous build artifacts.'
        ),
        string(
            name: 'ISO_URL',
            defaultValue: 'https://releases.ubuntu.com/24.04.4/ubuntu-24.04.4-desktop-amd64.iso',
            description: '(script-based only) Ubuntu ISO URL to build from.'
        ),
        string(
            name: 'ICT_IMG',
            defaultValue: '',
            description: '(ict-based only) Absolute path to pre-built ICT image (.raw.gz/.raw.img.gz). Leave empty to build from source.'
        ),
        string(
            name: 'SOURCE_REPO_URL',
            defaultValue: 'https://github.com/open-edge-platform/edge-node-infrastructure-blueprint.git',
            description: 'Git URL of this repository to checkout.'
        ),
        string(
            name: 'SOURCE_REPO_BRANCH',
            defaultValue: 'main',
            description: 'Branch or ref to checkout.'
        ),
        string(
            name: 'SOURCE_REPO_CREDENTIALS_ID',
            defaultValue: '',
            description: 'Optional Jenkins credentialsId for SOURCE_REPO_URL.'
        ),
        booleanParam(
            name: 'SKIP_BUILD_REUSE_CACHE',
            defaultValue: false,
            description: 'Skip image build entirely and reuse cached artifacts from the last successful build (/tmp/enib-build-cache/).'
        ),
        booleanParam(
            name: 'RUN_VEN_DEPLOYMENT',
            defaultValue: true,
            description: 'Run Virtual Edge Node (VEN) deployment and validation after image build.'
        )
    ])
])

pipeline {
    agent { label 'fed-node' }

    options {
        timestamps()
        ansiColor('xterm')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '15'))
    }

    environment {
        PATH = "/usr/local/go/bin:${env.PATH}"
    }

    stages {
        stage('Parameter Validation') {
            steps {
                script {
                    if (params.BUILD_MODE == 'script-based') {
                        if (!params.ISO_URL?.trim()) {
                            error "ISO_URL is required for script-based mode."
                        }
                        echo "Mode: script-based | ISO: ${params.ISO_URL}"
                    } else if (params.BUILD_MODE == 'reuse-image') {
                        echo "Mode: reuse-image | Skipping image build, reusing previous artifacts."
                    } else {
                        if (params.ICT_IMG?.trim()) {
                            echo "Mode: ict-based | ICT image: ${params.ICT_IMG}"
                        } else {
                            echo "Mode: ict-based | No ICT image provided; will build from source using Image Composer Tool."
                        }
                    }
                }
            }
        }

        stage('Checkout') {
            steps {
                script {
                    if (fileExists('Makefile') && fileExists('README.md')) {
                        echo 'Repository content already exists in workspace; skipping checkout.'
                        return
                    }

                    def resolvedRepoUrl = params.SOURCE_REPO_URL?.trim() ?: 'https://github.com/open-edge-platform/edge-node-infrastructure-blueprint.git'
                    echo "Checking out: ${resolvedRepoUrl} @ ${params.SOURCE_REPO_BRANCH}"

                    def remote = [url: resolvedRepoUrl]
                    if (params.SOURCE_REPO_CREDENTIALS_ID?.trim()) {
                        remote.credentialsId = params.SOURCE_REPO_CREDENTIALS_ID.trim()
                    }

                    checkout([
                        $class: 'GitSCM',
                        branches: [[name: params.SOURCE_REPO_BRANCH]],
                        userRemoteConfigs: [remote],
                        extensions: [[
                            $class: 'CloneOption',
                            shallow: true,
                            depth: 1,
                            noTags: false,
                            timeout: 30
                        ]]
                    ])
                }
            }
        }

        stage('Preflight') {
            steps {
                sh '''#!/usr/bin/env bash
                set -euo pipefail

                echo "Build mode: ${BUILD_MODE}"
                echo "Workspace: ${WORKSPACE}"

                # Verify non-interactive sudo with env preservation
                if ! sudo -n true 2>/dev/null; then
                    echo "ERROR: Non-interactive sudo not available. Grant NOPASSWD:SETENV for Jenkins user."
                    exit 1
                fi
                if ! sudo -nE true 2>/dev/null; then
                    echo "ERROR: sudo -E not allowed. Add SETENV to sudoers entry."
                    exit 1
                fi

                # Verify Go (needed for CDI generator build)
                if ! command -v go &>/dev/null; then
                    echo "ERROR: Go not found in PATH. PATH=$PATH"
                    exit 1
                fi
                echo "Go: $(go version)"
                echo "Preflight passed."
                '''
            }
        }

        stage('Restore Cached Build') {
            when {
                expression { params.SKIP_BUILD_REUSE_CACHE }
            }
            steps {
                sh '''#!/usr/bin/env bash
                set -euo pipefail

                CACHE_DIR="/tmp/enib-build-cache"
                echo "=== Restoring cached build artifacts from ${CACHE_DIR} ==="

                if [ ! -f "${CACHE_DIR}/usb-installation-files.tar.gz" ]; then
                    echo "ERROR: No cached build found at ${CACHE_DIR}/"
                    echo "Run a full build first (SKIP_BUILD_REUSE_CACHE=false) to populate the cache."
                    ls -la "$CACHE_DIR" 2>/dev/null || echo "  (directory does not exist)"
                    exit 1
                fi

                mkdir -p infrastructure/build-artifacts/out
                cp -v "${CACHE_DIR}"/* infrastructure/build-artifacts/out/
                echo "Cache restored. Contents:"
                ls -lh infrastructure/build-artifacts/out/
                '''
            }
        }

        stage('Build Image (script-based)') {
            when {
                expression { params.BUILD_MODE == 'script-based' && !params.SKIP_BUILD_REUSE_CACHE }
            }
            steps {
                sh '''#!/usr/bin/env bash
                set -euo pipefail
                echo "Running: make build MODE=image-from-iso"
                make build MODE=image-from-iso ISO_URL="${ISO_URL}" ICT_IMG="" skip-proxy=true
                '''
            }
        }

        stage('Build Artifacts (reuse-image)') {
            when {
                expression { params.BUILD_MODE == 'reuse-image' && !params.SKIP_BUILD_REUSE_CACHE }
            }
            steps {
                sh '''#!/usr/bin/env bash
                set -euo pipefail
                echo "Running: make build MODE=reuse-image (skipping image creation)"
                make build MODE=reuse-image skip-proxy=true
                '''
            }
        }

        stage('Build ICT Image from Source') {
            when {
                expression { params.BUILD_MODE == 'ict-based' && !params.ICT_IMG?.trim() && !params.SKIP_BUILD_REUSE_CACHE }
            }
            steps {
                sh '''#!/usr/bin/env bash
                set -euo pipefail

                echo "=== Building ICT Image from Source ==="
                ICT_TEMPLATE="infrastructure/host-os/ict/generic-handheld-os-template.yml"

                # Clone Image Composer Tool
                if [ ! -d ict-tool ]; then
                    git clone --depth 1 --branch 2026.1-Release \
                        https://github.com/open-edge-platform/image-composer-tool.git ict-tool
                fi

                # Install prerequisites
                sudo apt-get update -qq
                sudo apt-get install -y --no-install-recommends systemd-ukify mmdebstrap

                # Build ICT binary
                cd ict-tool
                go build -buildmode=pie -ldflags "-s -w" ./cmd/image-composer-tool
                echo "ICT binary built: $(ls -la image-composer-tool)"

                # Validate template
                TEMPLATE="${WORKSPACE}/${ICT_TEMPLATE}"
                ./image-composer-tool validate "$TEMPLATE"
                echo "Template validation passed."

                # Build the image
                echo "Building ICT image (this may take a while)..."
                sudo -E ./image-composer-tool build "$TEMPLATE"
                echo "ICT image build completed."
                cd ..

                # Find the output image
                ICT_OUTPUT=$(find ict-tool -type f -name "*.raw.gz" -print -o -type f -name "*.raw.img.gz" -print | head -1)
                if [ -z "$ICT_OUTPUT" ]; then
                    echo "ERROR: No ICT image output found."
                    exit 1
                fi

                # Copy to a known location for next stage
                mkdir -p /tmp/ict-shared-output
                cp "$ICT_OUTPUT" /tmp/ict-shared-output/
                echo "ICT image ready: $ICT_OUTPUT"
                '''
            }
        }

        stage('Build Image (ict-based)') {
            when {
                expression { params.BUILD_MODE == 'ict-based' && !params.SKIP_BUILD_REUSE_CACHE }
            }
            steps {
                script {
                    def ictPath = params.ICT_IMG?.trim()
                    if (!ictPath) {
                        // Use image built by previous stage
                        ictPath = sh(
                            script: "find /tmp/ict-shared-output -type f -name '*.raw.gz' -print -o -type f -name '*.raw.img.gz' -print | head -1",
                            returnStdout: true
                        ).trim()
                    }
                    if (!ictPath) {
                        error "No ICT image path available."
                    }
                    sh """#!/usr/bin/env bash
                    set -euo pipefail
                    echo "Running: make build MODE=image-from-tool ICT_IMG=${ictPath}"
                    make build MODE=image-from-tool ICT_IMG="${ictPath}" ISO_URL="" skip-proxy=true
                    """
                }
            }
        }

        stage('Collect Build Artifacts') {
            steps {
                sh '''#!/usr/bin/env bash
                set -euo pipefail
                echo "=== Build Artifacts ==="
                find infrastructure/build-artifacts/out -type f -print 2>/dev/null \
                    | while read f; do
                        size=$(du -h "$f" | cut -f1)
                        echo "  [$size] $f"
                    done || echo "  (none)"

                echo ""
                echo "Artifacts remain on disk at: ${WORKSPACE}/infrastructure/build-artifacts/out/"
                echo "(Large image files are NOT uploaded to Jenkins to avoid 10+ min archive delays)"
                '''
                // Only archive small metadata/logs, NOT multi-GB images
                archiveArtifacts artifacts: 'infrastructure/build-artifacts/out/**/*.log,infrastructure/build-artifacts/out/**/*.txt,infrastructure/build-artifacts/out/**/config-file', allowEmptyArchive: true
            }
        }

        stage('Save Build Cache') {
            when {
                expression { !params.SKIP_BUILD_REUSE_CACHE }
            }
            steps {
                sh '''#!/usr/bin/env bash
                set -euo pipefail

                CACHE_DIR="/tmp/enib-build-cache"
                echo "=== Saving build artifacts to cache (${CACHE_DIR}) ==="

                rm -rf "$CACHE_DIR"
                mkdir -p "$CACHE_DIR"

                if [ -d infrastructure/build-artifacts/out ] && [ "$(ls -A infrastructure/build-artifacts/out 2>/dev/null)" ]; then
                    cp infrastructure/build-artifacts/out/* "$CACHE_DIR/" 2>/dev/null || true
                    echo "Cached for next run:"
                    ls -lh "$CACHE_DIR/"
                else
                    echo "No artifacts to cache."
                fi
                '''
            }
        }

        stage('VEN Deployment') {
            when {
                expression { params.RUN_VEN_DEPLOYMENT }
            }
            steps {
                sh '''#!/usr/bin/env bash
                set -euo pipefail

                echo "=== Virtual Edge Node (VEN) Deployment ==="
                cd infrastructure/build-artifacts

                if [ ! -f out/usb-installation-files.tar.gz ]; then
                    echo "ERROR: usb-installation-files.tar.gz not found in build output."
                    exit 1
                fi

                # Extract installation artifacts
                sudo tar -xzf out/usb-installation-files.tar.gz -C out/
                cd out

                # Inject Jenkins agent SSH key into config-file for post-install SSH access
                if [ -f ~/.ssh/id_ed25519.pub ]; then
                    SSH_PUB_FILE=~/.ssh/id_ed25519.pub
                elif [ -f ~/.ssh/id_rsa.pub ]; then
                    SSH_PUB_FILE=~/.ssh/id_rsa.pub
                else
                    SSH_PUB_FILE=""
                    echo "WARNING: No SSH public key found. VEN tests requiring SSH will fail."
                fi

                if [ -n "$SSH_PUB_FILE" ]; then
                    # Use awk to avoid sed delimiter issues with SSH key content
                    # Files are root-owned (from sudo tar), so use sudo for write
                    SSH_PUB=$(cat "$SSH_PUB_FILE")
                    sudo awk -v key="$SSH_PUB" '/^ssh_key=/{print "ssh_key=\"" key "\""; next} {print}' config-file > /tmp/config-file.tmp
                    sudo mv /tmp/config-file.tmp config-file
                    echo "Injected SSH public key from $SSH_PUB_FILE into config-file."
                fi

                # Inject host proxy settings into config-file to avoid interactive prompts.
                # Reads from host environment (/etc/environment or current shell).
                HOST_HTTP_PROXY="${http_proxy:-${HTTP_PROXY:-}}"
                HOST_HTTPS_PROXY="${https_proxy:-${HTTPS_PROXY:-}}"
                HOST_NO_PROXY="${no_proxy:-${NO_PROXY:-localhost,127.0.0.1}}"

                if [ -n "$HOST_HTTP_PROXY" ]; then
                    sudo awk \
                        -v hp="$HOST_HTTP_PROXY" \
                        -v hps="$HOST_HTTPS_PROXY" \
                        -v np="$HOST_NO_PROXY" \
                    '
                        /^http_proxy=/  {print "http_proxy=\"" hp "\""; next}
                        /^https_proxy=/ {print "https_proxy=\"" hps "\""; next}
                        /^no_proxy=/    {print "no_proxy=\"" np "\""; next}
                        /^HTTP_PROXY=/  {print "HTTP_PROXY=\"" hp "\""; next}
                        /^HTTPS_PROXY=/ {print "HTTPS_PROXY=\"" hps "\""; next}
                        /^NO_PROXY=/    {print "NO_PROXY=\"" np "\""; next}
                        {print}
                    ' config-file > /tmp/config-file.tmp
                    sudo mv /tmp/config-file.tmp config-file
                    echo "Injected host proxy into config-file: $HOST_HTTP_PROXY"
                else
                    echo "No proxy detected on host. Leaving config-file proxy values as-is."
                fi

                echo "Config-file key values:"
                grep -E '^(http_proxy|https_proxy|ssh_key|host_type)' config-file || true

                # ven-deployment.sh runs QEMU in foreground.
                # The installer ends with 'reboot -f' which reboots the VM (doesn't shut it down).
                # We run it in background and monitor for installation completion.
                echo "Launching VEN deployment (ven-deployment.sh) in background..."
                sudo -E ./ven-deployment.sh &
                VEN_PID=$!

                # Wait for installation to complete.
                # The installer writes to ubuntu-disk.img. After reboot, the VM boots the installed OS.
                # We detect completion by waiting for the disk to grow beyond the initial 197K qcow2 header.
                TIMEOUT=2400  # 40 minutes max for installation
                ELAPSED=0
                INSTALL_DONE=false
                while kill -0 $VEN_PID 2>/dev/null; do
                    if [ $ELAPSED -ge $TIMEOUT ]; then
                        echo "WARNING: Installation timeout (${TIMEOUT}s). Killing QEMU."
                        sudo pkill -f "qemu-system-x86_64.*ubuntu-disk.img" || true
                        break
                    fi

                    # Check if the disk has been written to significantly (>1GB = installation happened)
                    DISK_SIZE=$(stat -c%s ubuntu-disk.img 2>/dev/null || echo 0)
                    if [ "$DISK_SIZE" -gt 1073741824 ]; then
                        if [ "$INSTALL_DONE" = "false" ]; then
                            echo "  Installation detected (disk size: $(du -h ubuntu-disk.img | cut -f1)). Waiting for reboot cycle..."
                            INSTALL_DONE=true
                        fi
                        # After install + reboot, give it 60s to boot the installed OS, then kill
                        sleep 60
                        echo "  Post-install boot detected. Shutting down installation VM."
                        sudo pkill -f "qemu-system-x86_64.*ubuntu-disk.img" || true
                        break
                    fi

                    sleep 30
                    ELAPSED=$((ELAPSED + 30))
                    echo "  Installing... (${ELAPSED}s elapsed)"
                done
                wait $VEN_PID 2>/dev/null || true

                echo "VEN installation completed."

                # Disconnect NBD from installation phase
                sudo qemu-nbd --disconnect /dev/nbd0 2>/dev/null || true

                # Verify disk was created
                if [ ! -f ubuntu-disk.img ]; then
                    echo "FAIL: ubuntu-disk.img not created by installation."
                    exit 1
                fi
                echo "PASS: ubuntu-disk.img created ($(ls -lh ubuntu-disk.img | awk '{print $5}'))"
                '''
            }
        }

        stage('VEN Boot & Test') {
            when {
                expression { params.RUN_VEN_DEPLOYMENT }
            }
            steps {
                sh '''#!/usr/bin/env bash
                set -euo pipefail

                echo "=== Booting Installed VEN for Testing ==="
                chmod +x tests/ven-boot-installed.sh tests/ven-validate.sh tests/ven-cleanup.sh

                # Boot the installed VM with SSH port forwarding
                # ubuntu-disk.img is in infrastructure/build-artifacts/out/ (created by ven-deployment.sh)
                sudo tests/ven-boot-installed.sh \
                    infrastructure/build-artifacts/out/ubuntu-disk.img \
                    2222 98 4G 300

                echo ""
                echo "=== Running VEN Validation Tests ==="
                # Run the test suite (uses SSH to validate the VM)
                tests/ven-validate.sh 2222 user localhost || VEN_TEST_RESULT=$?

                # Archive test results
                cp /tmp/ven-test-results.txt infrastructure/build-artifacts/out/ven-test-results.txt 2>/dev/null || true

                # Cleanup test VM
                sudo tests/ven-cleanup.sh 2222 user localhost

                if [ "${VEN_TEST_RESULT:-0}" -ne 0 ]; then
                    echo "VEN validation had failures. Check test results."
                    exit 1
                fi
                '''

                archiveArtifacts artifacts: 'infrastructure/build-artifacts/out/ven-test-results.txt', allowEmptyArchive: true
            }
        }
    }

    post {
        always {
            // Cleanup any leftover QEMU processes (installation + test VMs)
            sh 'sudo pkill -f "qemu-system-x86_64.*ubuntu-disk.img" 2>/dev/null || true'
            sh 'sudo pkill -f "qemu-system-x86_64.*ven-test-vm" 2>/dev/null || true'
            sh 'sudo qemu-nbd --disconnect /dev/nbd0 2>/dev/null || true'
            sh 'rm -f /tmp/ven-test-vm.pid 2>/dev/null || true'
            cleanWs(deleteDirs: true, notFailBuild: true)
        }
        success {
            echo 'Pipeline completed successfully.'
        }
        failure {
            echo 'Pipeline failed. Check stage logs for details.'
        }
    }
}
