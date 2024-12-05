#!/bin/bash

# Default values
MEMORY=4G
SMP=4
SSH_PORT=2023

# Check if required files exist
check_files() {
    local missing=0
    
    if [ ! -f "rootfs/ubuntu2024-server.qcow2" ]; then
        echo "Error: QEMU image not found at rootfs/ubuntu2024-server.qcow2"
        missing=1
    fi
    
    if [ ! -f "rootfs/cloud-init.iso" ]; then
        echo "Error: cloud-init.iso not found at rootfs/cloud-init.iso"
        missing=1
    fi
    
    if [ ! -f "kernel/bzImage" ]; then
        echo "Error: kernel image not found at kernel/bzImage"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        echo "Please ensure you've extracted the package contents in the current directory"
        exit 1
    fi
}

# Check QEMU version and CXL support
check_qemu() {
    if ! command -v qemu-system-x86_64 &> /dev/null; then
        echo "Error: qemu-system-x86_64 not found. Please install QEMU."
        exit 1
    fi
    
    if ! qemu-system-x86_64 -machine help | grep -q "cxl"; then
        echo "Warning: Your QEMU version might not support CXL. Please ensure you have QEMU built with CXL support."
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Main execution
check_files
check_qemu

echo "Starting QEMU with CXL support..."
echo "SSH will be available on localhost:${SSH_PORT}"
echo "Login credentials: ubuntu/ubuntu"

qemu-system-x86_64 \
    -machine q35,cxl=on \
    -enable-kvm \
    -cpu host \
    -m ${MEMORY} \
    -smp ${SMP} \
    -kernel kernel/bzImage \
    -append "root=/dev/sda1 console=ttyS0 nokaslr" \
    -drive file=rootfs/ubuntu2024-server.qcow2,if=virtio,format=qcow2 \
    -drive file=rootfs/cloud-init.iso,if=virtio,format=raw \
    -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
    -device virtio-net-pci,netdev=net0 \
    -nographic \
    -object memory-backend-file,id=cxl-mem1,share=on,mem-path=/dev/shm/cxl-mem1,size=512M \
    -object memory-backend-file,id=cxl-mem2,share=on,mem-path=/dev/shm/cxl-mem2,size=512M \
    -device pxb-cxl,id=cxl.1,bus=pcie.0,bus_nr=52 \
    -device cxl-rp,id=rp1,bus=cxl.1,chassis=0,slot=0,port=0 \
    -device cxl-type3,id=cxl-pmem0,bus=rp1,memdev=cxl-mem1,lsa=0x0000000150000000,size=512M \
    -device cxl-rp,id=rp2,bus=cxl.1,chassis=0,slot=1,port=1 \
    -device cxl-type3,id=cxl-pmem1,bus=rp2,memdev=cxl-mem2,lsa=0x0000000150000000,size=512M 