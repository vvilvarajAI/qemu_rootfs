#!/bin/bash

# Variables
KERNEL_VERSION="6.8"
BUILD_DIR="/workspace/data/kernel"
IMAGE_NAME="/workspace/data/rootfs/ubuntu2024-server.qcow2"
KERNEL_PATH="$BUILD_DIR/linux-$KERNEL_VERSION/arch/x86/boot/bzImage"
INITRAMFS_IMG="$BUILD_DIR/initramfs-${KERNEL_VERSION}.img"
CLOUD_INIT_ISO="/workspace/data/rootfs/cloud-init.iso"
KERNEL_CMD="rw console=tty0 console=ttyS0,115200 ignore_loglevel rootwait root=/dev/vda1"

# Check if image exists
if [ ! -f "$IMAGE_NAME" ]; then
    echo "Error: $IMAGE_NAME not found. Please run create_rootfs.sh first."
    exit 1
fi

# Check if cloud-init.iso exists
if [ ! -f "$CLOUD_INIT_ISO" ]; then
    echo "Error: cloud-init.iso not found. Please run create_rootfs.sh first."
    exit 1
fi

# Check if kernel exists
if [ ! -f "$KERNEL_PATH" ]; then
    echo "Kernel not found at $KERNEL_PATH"
    echo "Running wget_build_kernel.sh to download and build kernel..."
    ./wget_build_kernel.sh
    
    if [ ! -f "$KERNEL_PATH" ]; then
        echo "Error: Kernel still not found after running wget_build_kernel.sh"
        exit 1
    fi
fi

echo "Starting VM..."
echo "You can login with username 'ubuntu' and password 'ubuntu'"
echo "Press Ctrl+A, then X to exit QEMU"

# Check QEMU version and capabilities
qemu-system-x86_64 --version
echo "Available machine types:"
qemu-system-x86_64 -machine help

# Launch QEMU
qemu-system-x86_64 \
    -kernel ${KERNEL_PATH} \
    -append "${KERNEL_CMD}" \
    -smp 16 \
    -enable-kvm \
    -netdev "user,id=network0,hostfwd=tcp::2023-:22" \
    -drive file=${IMAGE_NAME},if=virtio,format=qcow2 \
    -drive file=${CLOUD_INIT_ISO},if=virtio,format=raw \
    -device "e1000,netdev=network0" \
    -machine q35,cxl=on,kernel-irqchip=split -m 16G \
    -serial stdio \
    -cpu host \
    -virtfs local,path=/lib/modules,mount_tag=modshare,security_model=mapped \
    -initrd ${INITRAMFS_IMG} \
    -display none \
    -object memory-backend-ram,size=512M,id=cxl-mem0 \
    -object memory-backend-ram,size=512M,id=cxl-mem1 \
    -device pxb-cxl,bus=pcie.0,bus_nr=12,id=cxl.0 \
    -device cxl-rp,port=0,bus=cxl.0,id=root_port13,chassis=0,slot=2 \
    -device cxl-type3,bus=root_port13,memdev=cxl-mem0,id=cxl-pmem0,size=512M \
    -device cxl-rp,port=1,bus=cxl.0,id=root_port14,chassis=0,slot=3 \
    -device cxl-type3,bus=root_port14,memdev=cxl-mem1,id=cxl-pmem1,size=512M

echo ""
echo "VM has been shut down"
echo "To connect to VM next time using SSH: ssh -p 2023 ubuntu@localhost"
echo "Default password: ubuntu"
