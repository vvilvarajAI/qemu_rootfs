#!/bin/bash

# Exit on error
set -x

# Usage:
# ./create_rootfs.sh
# This script will:
# 1. Create a QCOW2 image based on Ubuntu 24.04 server
# 2. Configure it with cloud-init
# 3. Launch it for testing
# 4. After successful test, you can run it manually using the command shown at the end

# Variables
IMAGE_NAME="ubuntu2024-server.qcow2"
IMAGE_SIZE="10G"
UBUNTU_RELEASE="24.04"
UBUNTU_CODENAME="noble"

# Create QCOW2 image
echo "Creating QCOW2 image..."
qemu-img create -f qcow2 "$IMAGE_NAME" "$IMAGE_SIZE"

# Download Ubuntu cloud image if not present
echo "Checking for Ubuntu cloud image..."
if [ ! -f "$UBUNTU_CODENAME-server-cloudimg-amd64.img" ]; then
    echo "Downloading Ubuntu cloud image..."
    wget "https://cloud-images.ubuntu.com/daily/server/$UBUNTU_CODENAME/current/$UBUNTU_CODENAME-server-cloudimg-amd64.img"
else
    echo "Ubuntu cloud image already exists, skipping download..."
fi

# Create and prepare the new image
echo "Creating and preparing the new image..."
cp "$UBUNTU_CODENAME-server-cloudimg-amd64.img" "$IMAGE_NAME"
qemu-img resize "$IMAGE_NAME" "$IMAGE_SIZE"

# Check and install required dependencies
echo "Checking and installing required dependencies..."
if ! command -v cloud-localds &> /dev/null; then
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y cloud-image-utils
    else
        echo "Error: cloud-image-utils package needs to be installed manually on non-Debian systems"
        exit 1
    fi
fi

# Create cloud-init config for initial setup
cat > cloud-init.cfg <<EOF
#cloud-config
password: ubuntu
chpasswd: { expire: False }
ssh_pwauth: True
EOF

# Create cloud-init ISO
cloud-localds cloud-init.iso cloud-init.cfg

echo "Created $IMAGE_NAME with size $IMAGE_SIZE"
echo "Starting test VM..."
echo "The VM will boot and run for 3 minutes to verify functionality"
echo "You can login with username 'ubuntu' and password 'ubuntu'"
echo "Press Ctrl+A, then X to exit QEMU"

# Launch QEMU for testing
timeout 180s qemu-system-x86_64 \
    -enable-kvm \
    -m 2G \
    -smp 2 \
    -nographic \
    -drive file="$IMAGE_NAME",if=virtio \
    -drive file=cloud-init.iso,format=raw \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=net0 || true

echo ""
echo "Test completed. If the VM booted successfully, you can now run it manually using:"
echo "qemu-system-x86_64 \\"
echo "  -enable-kvm \\"
echo "  -m 2G \\"
echo "  -smp 2 \\"
echo "  -nographic \\"
echo "  -drive file=$IMAGE_NAME,if=virtio \\"
echo "  -drive file=cloud-init.iso,format=raw \\"
echo "  -netdev user,id=net0,hostfwd=tcp::2222-:22 \\"
echo "  -device virtio-net-pci,netdev=net0"
echo ""
echo "Connect to VM using: ssh -p 2222 ubuntu@localhost"
echo "Default password: ubuntu"




