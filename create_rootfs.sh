#!/bin/bash

# Exit on error
#set -x

# Source the kernel configuration
source ./kernel_config.sh

# Log the start of rootfs creation
log_message "Starting rootfs creation process"

# Create QCOW2 image
log_message "Creating QCOW2 image..."
qemu-img create -f qcow2 "${IMAGE_PATH}" "${IMAGE_SIZE}"

# Download Ubuntu cloud image if not present
log_message "Checking for Ubuntu cloud image..."
if [ ! -f "${BUILD_DIR}/${UBUNTU_IMAGE}" ]; then
    log_message "Downloading Ubuntu cloud image..."
    wget -O "${BUILD_DIR}/${UBUNTU_IMAGE}" "${UBUNTU_IMAGE_URL}"
else
    log_message "Ubuntu cloud image already exists, skipping download..."
fi

# Create and prepare the new image
log_message "Creating and preparing the new image..."
cp "${BUILD_DIR}/${UBUNTU_IMAGE}" "${IMAGE_PATH}"
qemu-img resize "${IMAGE_PATH}" "${IMAGE_SIZE}"

# Check and install required dependencies
log_message "Checking and installing required dependencies..."
if ! command -v cloud-localds &> /dev/null; then
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y cloud-image-utils
    else
        log_message "Error: cloud-image-utils package needs to be installed manually on non-Debian systems"
        exit 1
    fi
fi

# Create cloud-init config for initial setup
log_message "Setting up cloud-init configuration..."
cat > "${CLOUD_INIT_CFG}" <<EOF
#cloud-config
password: ubuntu
chpasswd: { expire: False }
ssh_pwauth: True
EOF

# Create cloud-init ISO
log_message "Creating cloud-init ISO..."
cloud-localds "${CLOUD_INIT_ISO}" "${CLOUD_INIT_CFG}"

log_message "Starting test VM..."
echo "Created ${IMAGE_NAME} with size ${IMAGE_SIZE}"
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
    -drive file="${IMAGE_PATH}",if=virtio \
    -drive file="${CLOUD_INIT_ISO}",format=raw \
    -netdev user,id=net0,hostfwd=tcp::${QEMU_TEST_SSH_PORT}-:22 \
    -device virtio-net-pci,netdev=net0 || true

echo ""
echo "Test completed. If the VM booted successfully, you can now run it manually using:"
echo "qemu-system-x86_64 \\"
echo "  -enable-kvm \\"
echo "  -m 2G \\"
echo "  -smp 2 \\"
echo "  -nographic \\"
echo "  -drive file=${IMAGE_PATH},if=virtio \\"
echo "  -drive file=${CLOUD_INIT_ISO},format=raw \\"
echo "  -netdev user,id=net0,hostfwd=tcp::${QEMU_TEST_SSH_PORT}-:22 \\"
echo "  -device virtio-net-pci,netdev=net0"
echo ""
echo "Connect to VM using: ssh -p ${QEMU_TEST_SSH_PORT} ubuntu@localhost"
echo "Default password: ubuntu"

log_message "Rootfs creation process completed"




