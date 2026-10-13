# Standalone applications installation

This repo allows you to install applications, such as Docker, K3s, power-tuning, system-info and others. To install them on a supported machine, run the following commands as a prerequisite for installation.

```shell
sudo apt install make git curl
git clone https://github.com/open-edge-platform/edge-node-infrastructure-blueprint.git
cd edge-node-infrastructure-blueprint
```

After that, the system is ready for installation of packages. It will download additional dependencies from the APT repo or will build them during installation, which might take some time depending on the bandwidth of the system.

To install Docker, run

```shell
sudo make docker
```

To install K3s, run

```shell
sudo make k3s
```

To install system-info, power-tuning, realsense, CDI and SR-IOV packages (which are automatically installed in Docker and K3s targets), run

```shell
sudo make common
```
