#!/bin/bash

# Kernel configuration
KERNEL_VERSION="6.8"

# Set up directory structure relative to script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
LOGS_DIR="${BUILD_DIR}/logs"
KERNEL_BUILD_DIR="${BUILD_DIR}/kernel"
INITRD_DIR="${BUILD_DIR}/initrd.dir"
MODULES_DIR="${BUILD_DIR}/lib/modules"

# Image configurations
IMAGE_NAME="ubuntu2024-server.qcow2"
IMAGE_PATH="${BUILD_DIR}/${IMAGE_NAME}"
IMAGE_SIZE="10G"
CLOUD_INIT_ISO="${BUILD_DIR}/cloud-init.iso"
CLOUD_INIT_CFG="${BUILD_DIR}/cloud-init.cfg"

# Ubuntu configurations
UBUNTU_RELEASE="24.04"
UBUNTU_CODENAME="noble"
UBUNTU_IMAGE="${UBUNTU_CODENAME}-server-cloudimg-amd64.img"
UBUNTU_IMAGE_URL="https://cloud-images.ubuntu.com/daily/server/${UBUNTU_CODENAME}/current/${UBUNTU_IMAGE}"

# Kernel configurations
KERNEL_SOURCE_DIR="${KERNEL_BUILD_DIR}/linux-${KERNEL_VERSION}"
KERNEL_PATH="${KERNEL_SOURCE_DIR}/arch/x86/boot/bzImage"
INITRAMFS_PATH="${INITRD_DIR}/initramfs-${KERNEL_VERSION}.img"
KERNEL_CMD="rw console=tty0 console=ttyS0,115200 ignore_loglevel rootwait root=/dev/vda1"

# QEMU configurations
QEMU_SSH_PORT="2023"
QEMU_TEST_SSH_PORT="2222"
QEMU_MEMORY="16G"
QEMU_SMP="16"

# Script locations
ROOTFS_SCRIPT="${SCRIPT_DIR}/create_rootfs.sh"
KERNEL_SCRIPT="${SCRIPT_DIR}/wget_build_kernel.sh"
QEMU_SCRIPT="${SCRIPT_DIR}/run_qemu_with_rootfs.sh"
SETUP_SCRIPT="${SCRIPT_DIR}/setup_and_run.sh"

# Create directory structure
create_directory_structure() {
    local directories=(
        "${BUILD_DIR}"
        "${LOGS_DIR}"
        "${KERNEL_BUILD_DIR}"
        "${INITRD_DIR}"
        "${MODULES_DIR}"
    )

    for dir in "${directories[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_message "Created directory: $dir"
        fi
    done
}

# Initialize log file
LOG_FILE="${LOGS_DIR}/kernel_operations.log"

# Function to log messages
log_message() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$(dirname "${LOG_FILE}")"
    echo "[${timestamp}] $1" | tee -a "${LOG_FILE}"
}

# Create initial directory structure
create_directory_structure
log_message "Initialized build environment in ${BUILD_DIR}"