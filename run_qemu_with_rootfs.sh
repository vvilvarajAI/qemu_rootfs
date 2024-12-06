#!/bin/bash

KERNEL_VERSION="6.12"
KERNEL_PATH="/workspace/data/kernel/linux-${KERNEL_VERSION}/arch/x86/boot/bzImage"
INITRD_PATH="/workspace/data/kernel/initrd.img"
ROOTFS_PATH="/workspace/data/rootfs/ubuntu2024-server.qcow2"
CLOUD_INIT_PATH="/workspace/data/rootfs/cloud-init.iso"

echo "Starting VM..."
echo "You can login with username 'ubuntu' and password 'ubuntu'"
echo "Press Ctrl+A, then X to exit QEMU"

qemu-system-x86_64 \
    -machine q35 \
    -enable-kvm \
    -cpu host \
    -m 4G \
    -smp 4 \
    -kernel "${KERNEL_PATH}" \
    -initrd "${INITRD_PATH}" \
    -append "root=/dev/sda1 console=ttyS0 nokaslr" \
    -drive file="${ROOTFS_PATH}",if=virtio,format=qcow2 \
    -drive file="${CLOUD_INIT_PATH}",if=virtio,format=raw \
    -netdev user,id=net0,hostfwd=tcp::2023-:22 \
    -device virtio-net-pci,netdev=net0 \
    -nographic

echo "VM has been shut down"
echo "To connect to VM next time using SSH: ssh -p 2023 ubuntu@localhost"
echo "Default password: ubuntu"
