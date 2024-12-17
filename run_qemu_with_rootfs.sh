#!/bin/bash

# Source the kernel configuration
source ./kernel_config.sh

# Log QEMU startup
log_message "Starting QEMU with kernel version ${KERNEL_VERSION}"

# Check if image exists
if [ ! -f "${IMAGE_PATH}" ]; then
    log_message "Error: ${IMAGE_PATH} not found. Please run create_rootfs.sh first."
    exit 1
fi

# Check if cloud-init.iso exists
if [ ! -f "${CLOUD_INIT_ISO}" ]; then
    log_message "Error: ${CLOUD_INIT_ISO} not found. Please run create_rootfs.sh first."
    exit 1
fi

# Check if kernel exists
if [ ! -f "${KERNEL_PATH}" ]; then
    log_message "Kernel not found at ${KERNEL_PATH}"
    log_message "Running wget_build_kernel.sh to download and build kernel..."
    KERNEL_PATH=$(./wget_build_kernel.sh)
    
    if [ ! -f "${KERNEL_PATH}" ]; then
        log_message "Error: Kernel still not found after running wget_build_kernel.sh"
        exit 1
    fi
fi

log_message "Starting VM..."
echo "You can login with username 'ubuntu' and password 'ubuntu'"
echo "Press Ctrl+A, then X to exit QEMU"

# Launch QEMU
qemu-system-x86_64 \
    -kernel ${KERNEL_PATH} \
    -append "${KERNEL_CMD}" \
    -smp ${QEMU_SMP} \
    -enable-kvm \
    -netdev "user,id=network0,hostfwd=tcp::${QEMU_SSH_PORT}-:22" \
    -drive file=${IMAGE_PATH},if=virtio,format=qcow2 \
    -drive file=${CLOUD_INIT_ISO},if=virtio,format=raw \
    -device "e1000,netdev=network0" \
    -machine q35,cxl=on -m ${QEMU_MEMORY} \
    -serial stdio \
    -cpu host \
    -virtfs local,path=/lib/modules,mount_tag=modshare,security_model=mapped \
    -initrd ${INITRAMFS_PATH} \
    -display none

echo ""
echo "VM has been shut down"
echo "To connect to VM next time using SSH: ssh -p ${QEMU_SSH_PORT} ubuntu@localhost"
echo "Default password: ubuntu"

log_message "QEMU session ended"
