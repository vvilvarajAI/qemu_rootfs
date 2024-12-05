#!/bin/bash

# Create necessary directories if they don't exist
create_dirs() {
    mkdir -p data/{rootfs,kernel,logs}
    mkdir -p shared
}

# Initialize the environment
init() {
    create_dirs
    echo "Environment initialized. Directory structure created."
}

# Package the environment for sharing
package() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local package_name="qemu-cxl-images-${timestamp}.tar.gz"
    
    echo "Creating package ${package_name}..."
    
    # Create a temporary directory for packaging
    mkdir -p data/package/{rootfs,kernel}
    
    # Copy QEMU and cloud-init files
    cp data/rootfs/ubuntu2024-server.qcow2 data/package/rootfs/ 2>/dev/null || echo "Warning: QEMU image not found"
    cp data/rootfs/cloud-init.iso data/package/rootfs/ 2>/dev/null || echo "Warning: cloud-init.iso not found"
    
    # Copy kernel files
    if [ -d "data/kernel/linux-6.8" ]; then
        # Copy kernel image
        cp data/kernel/linux-6.8/arch/x86/boot/bzImage data/package/kernel/ 2>/dev/null || echo "Warning: kernel image not found"
        
        # Copy kernel modules and create initrd
        if [ -d "data/kernel/linux-6.8/modules" ]; then
            cp -r data/kernel/linux-6.8/modules data/package/kernel/ 2>/dev/null || echo "Warning: kernel modules not found"
        fi
        
        if [ -f "data/kernel/linux-6.8/initrd.img" ]; then
            cp data/kernel/linux-6.8/initrd.img data/package/kernel/ 2>/dev/null || echo "Warning: initrd not found"
        fi
    else
        echo "Warning: kernel directory not found"
    fi
    
    # Copy run_local.sh script
    cp run_local.sh data/package/ 2>/dev/null || echo "Warning: run_local.sh not found"
    chmod +x data/package/run_local.sh 2>/dev/null
    
    # Create a simple README
    cat > data/package/README.md << 'EOF'
# QEMU CXL Environment

This package contains the necessary files to run a QEMU environment with CXL support.

## Contents
- `rootfs/` - Contains the QEMU disk image and cloud-init configuration
- `kernel/` - Contains the custom kernel with CXL support
- `run_local.sh` - Script to run the environment

## Requirements
- QEMU with CXL support
- KVM enabled system
- At least 4GB of RAM

## Usage
1. Extract the archive:
   ```bash
   tar xzf qemu-cxl-images-*.tar.gz
   ```

2. Run the environment:
   ```bash
   ./run_local.sh
   ```

3. Connect via SSH:
   ```bash
   ssh -p 2023 ubuntu@localhost
   ```
   Password: ubuntu

## Notes
- The script will check for QEMU CXL support before running
- Two 512MB CXL memory regions will be created
- Default SSH port is 2023
EOF
    
    # Create archive
    tar -czf "${package_name}" -C data/package .
    
    # Cleanup
    rm -rf data/package
    
    echo "Package created: ${package_name}"
    echo "Package contents:"
    tar -tvf "${package_name}"
    echo "Package size: $(du -h ${package_name} | cut -f1)"
    echo -e "\nTo use the package:"
    echo "1. Extract: tar xzf ${package_name}"
    echo "2. Run: ./run_local.sh"
}

case "$1" in
    "init")
        init
        ;;
    "build")
        create_dirs
        docker-compose build
        ;;
    "start")
        create_dirs
        docker-compose up
        ;;
    "stop")
        docker-compose down
        ;;
    "clean")
        docker-compose down
        rm -rf data/* shared/*
        echo "Environment cleaned."
        ;;
    "ssh")
        ssh -p 2023 ubuntu@localhost
        ;;
    "shell")
        docker-compose exec qemu-cxl /bin/bash
        ;;
    "logs")
        if [ -z "$2" ]; then
            echo "Recent logs:"
            ls -lht data/logs/ | head -n 5
            echo "Use './manage.sh logs <filename>' to view a specific log"
        else
            less "data/logs/$2"
        fi
        ;;
    "package")
        package
        ;;
    *)
        echo "Usage: $0 {init|build|start|stop|clean|ssh|shell|logs|package}"
        echo "  init:    Initialize the environment"
        echo "  build:   Build the Docker image"
        echo "  start:   Start the environment"
        echo "  stop:    Stop the environment"
        echo "  clean:   Clean up all generated files"
        echo "  ssh:     Connect to the VM via SSH"
        echo "  shell:   Get a shell inside the container"
        echo "  logs:    View logs (use 'logs <filename>' to view specific log)"
        echo "  package: Create a shareable package of QEMU images"
        exit 1
        ;;
esac 