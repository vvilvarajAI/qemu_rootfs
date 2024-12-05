# QEMU CXL Development Environment

This repository contains a dockerized QEMU environment for CXL development with Ubuntu 24.04 and custom kernel support.

## Prerequisites

- Docker
- Docker Compose
- KVM support on the host system

## Quick Start

1. Clone the repository:
```bash
git clone <repository-url>
cd <repository-directory>
```

2. Create shared directory:
```bash
mkdir shared
```

3. Build and start the container:
```bash
docker-compose up --build
```

4. Connect to the VM:
- Wait for the VM to boot
- Login with username: `ubuntu` and password: `ubuntu`
- Or use SSH: `ssh -p 2023 ubuntu@localhost`

## Directory Structure

- `shared/`: Directory mounted in the container for file sharing
- `wget_build_kernel.sh`: Script to download and build the kernel
- `run_qemu_with_rootfs.sh`: Script to run QEMU with the built kernel
- `create_rootfs.sh`: Script to create the Ubuntu root filesystem
- `cloud-init.cfg`: Cloud-init configuration for VM initialization

## Features

- Ubuntu 24.04 base system
- Custom kernel (6.8) with CXL support
- Cloud-init integration
- KVM acceleration
- SSH access
- Shared directory for easy file transfer

## Customization

- Modify `cloud-init.cfg` to customize the VM initialization
- Adjust kernel configuration in `wget_build_kernel.sh`
- Configure VM settings in `run_qemu_with_rootfs.sh`

## Troubleshooting

1. If KVM is not available:
   - Check if virtualization is enabled in BIOS
   - Verify KVM module is loaded: `lsmod | grep kvm`
   - Install KVM: `sudo apt-get install qemu-kvm`

2. If the VM fails to boot:
   - Check kernel build logs in the container
   - Verify cloud-init configuration
   - Check QEMU error messages

## License

This project is licensed under the MIT License - see the LICENSE file for details. 