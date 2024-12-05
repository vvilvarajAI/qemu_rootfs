#!/bin/bash

# Exit on error
set -x

# Variables
IMAGE_NAME="/workspace/data/rootfs/ubuntu2024-server.qcow2"
IMAGE_SIZE="10G"
UBUNTU_RELEASE="24.04"
UBUNTU_CODENAME="noble"
CLOUD_IMAGE="$UBUNTU_CODENAME-server-cloudimg-amd64.img"
CLOUD_INIT_ISO="/workspace/data/rootfs/cloud-init.iso"

# Create directories
mkdir -p /workspace/data/rootfs

cd /workspace/data/rootfs

# Create QCOW2 image
echo "Creating QCOW2 image..."
qemu-img create -f qcow2 "$IMAGE_NAME" "$IMAGE_SIZE"

# Download Ubuntu cloud image if not present
echo "Checking for Ubuntu cloud image..."
if [ ! -f "$CLOUD_IMAGE" ]; then
    echo "Downloading Ubuntu cloud image..."
    wget "https://cloud-images.ubuntu.com/daily/server/$UBUNTU_CODENAME/current/$CLOUD_IMAGE"
else
    echo "Ubuntu cloud image already exists, skipping download..."
fi

# Create and prepare the new image
echo "Creating and preparing the new image..."
cp "$CLOUD_IMAGE" "$IMAGE_NAME"
qemu-img resize "$IMAGE_NAME" "$IMAGE_SIZE"

# Create cloud-init ISO
cloud-localds "$CLOUD_INIT_ISO" /workspace/cloud-init.cfg

echo "Created $IMAGE_NAME with size $IMAGE_SIZE"
echo "You can now run the VM using run_qemu_with_rootfs.sh"




