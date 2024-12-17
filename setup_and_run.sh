#!/bin/bash

# Source the kernel configuration
source ./kernel_config.sh

# Function to check script execution status
check_status() {
    if [ $? -eq 0 ]; then
        log_message "✓ $1 completed successfully"
    else
        log_message "✗ $1 failed"
        exit 1
    fi
}

# Print banner
log_message "Starting CXL Development Environment Setup"
log_message "=========================================="
log_message "This script will:"
log_message "1. Create Ubuntu root filesystem"
log_message "2. Build Linux kernel with CXL support"
log_message "3. Launch QEMU with the built kernel"
echo ""

# Check if all required scripts exist
for script in "${ROOTFS_SCRIPT}" "${KERNEL_SCRIPT}" "${QEMU_SCRIPT}"; do
    if [ ! -f "$script" ]; then
        log_message "Error: Required script $script not found"
        exit 1
    fi
    chmod +x "$script"
done

# Step 1: Create root filesystem
log_message "Step 1/3: Creating root filesystem..."
./create_rootfs.sh
check_status "Root filesystem creation"

# Step 2: Build kernel
log_message "Step 2/3: Building kernel..."
./wget_build_kernel.sh
check_status "Kernel build"

# Step 3: Run QEMU
log_message "Step 3/3: Launching QEMU..."
log_message "You can connect to the VM using: ssh -p ${QEMU_SSH_PORT} ubuntu@localhost"
log_message "Password: ubuntu"
echo ""
log_message "Press Enter to start the VM..."
read

./run_qemu_with_rootfs.sh
check_status "QEMU execution"

log_message "Setup completed"
log_message "To start the VM again, just run: ./run_qemu_with_rootfs.sh" 