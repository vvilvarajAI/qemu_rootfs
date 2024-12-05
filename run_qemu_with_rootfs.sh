#!/bin/bash


# Variables
KERNEL_VERSION="6.8"
BUILD_DIR="/home/vvilvaraj/QEMU_CXL_DEV_TOOLS/temp"
IMAGE_NAME="ubuntu2024-server.qcow2"
KERNEL_PATH="$BUILD_DIR/linux-$KERNEL_VERSION/arch/x86/boot/bzImage"
QEMU_IMG="/home/vvilvaraj/Desktop/CanisFW/minimal_ROOTFS/ubuntu2024-server.qcow2"
INITRAMFS_IMG="$BUILD_DIR/initrd.dir/initramfs-${KERNEL_VERSION}.img"
KERNEL_CMD="rw console=tty0 console=ttyS0,115200 ignore_loglevel rootwait root=/dev/vda1"

# Check if image exists
if [ ! -f "$IMAGE_NAME" ]; then
    echo "Error: $IMAGE_NAME not found. Please run create_rootfs.sh first."
    exit 1
fi

# Check if cloud-init.iso exists
if [ ! -f "cloud-init.iso" ]; then
    echo "Error: cloud-init.iso not found. Please run create_rootfs.sh first."
    exit 1
fi

# Check if kernel exists
if [ ! -f "$KERNEL_PATH" ]; then
    echo "Kernel not found at $KERNEL_PATH"
    echo "Running wget_build_kernel.sh to download and build kernel..."
    KERNEL_PATH=$(./wget_build_kernel.sh)
    
    if [ ! -f "$KERNEL_PATH" ]; then
        echo "Error: Kernel still not found after running wget_build_kernel.sh"
        exit 1
    fi
fi


echo "Starting VM..."
echo "You can login with username 'ubuntu' and password 'ubuntu'"
echo "Press Ctrl+A, then X to exit QEMU"

# Launch QEMU
qemu-system-x86_64 \
    -kernel ${KERNEL_PATH} \
    -append "${KERNEL_CMD}" \
    -smp 16 \
    -enable-kvm \
    -netdev "user,id=network0,hostfwd=tcp::2023-:22" \
    -drive file=${QEMU_IMG},if=virtio,format=qcow2 \
    -drive file=cloud-init.iso,if=virtio,format=raw \
    -device "e1000,netdev=network0" \
    -machine q35,cxl=on -m 16G \
    -serial stdio \
    -cpu host \
    -virtfs local,path=/lib/modules,mount_tag=modshare,security_model=mapped \
    -initrd ${INITRAMFS_IMG} \
    -display none

echo ""
echo "VM has been shut down"
echo "To connect to VM next time using SSH: ssh -p 2023 ubuntu@localhost"
echo "Default password: ubuntu"
