#!/bin/bash

set -e

KERNEL_VERSION="6.12"
KERNEL_MAJOR="6"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/linux-${KERNEL_VERSION}.tar.xz"
BUILD_DIR="/workspace/data/kernel"
KERNEL_SRC="${BUILD_DIR}/linux-${KERNEL_VERSION}"

# Create build directory
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Download and extract kernel if not already done
if [ ! -d "linux-${KERNEL_VERSION}" ]; then
    echo "Downloading kernel source..."
    wget -q "${KERNEL_URL}"
    tar xf "linux-${KERNEL_VERSION}.tar.xz"
    rm "linux-${KERNEL_VERSION}.tar.xz"
fi

cd "linux-${KERNEL_VERSION}"

# Configure kernel if not already done
if [ ! -f ".config" ]; then
    echo "Configuring kernel..."
    make defconfig
    # Enable CXL support
    ./scripts/config --enable CONFIG_CXL_BUS
    ./scripts/config --enable CONFIG_CXL_PCI
    ./scripts/config --enable CONFIG_CXL_MEM
    ./scripts/config --enable CONFIG_CXL_PORT
    ./scripts/config --enable CONFIG_CXL_ACPI
    ./scripts/config --enable CONFIG_CXL_PMEM
    ./scripts/config --enable CONFIG_CXL_MEM_RAW_COMMANDS
    # Enable basic features needed for boot
    ./scripts/config --enable CONFIG_BLK_DEV_INITRD
    ./scripts/config --enable CONFIG_VIRTIO
    ./scripts/config --enable CONFIG_VIRTIO_PCI
    ./scripts/config --enable CONFIG_VIRTIO_BLK
    ./scripts/config --enable CONFIG_VIRTIO_NET
    ./scripts/config --enable CONFIG_EXT4_FS
    ./scripts/config --enable CONFIG_DEVTMPFS
    ./scripts/config --enable CONFIG_DEVTMPFS_MOUNT
fi

# Build kernel and modules
echo "Building kernel..."
make -j$(nproc)

# Install modules
echo "Installing modules..."
mkdir -p "${BUILD_DIR}/modules"
make INSTALL_MOD_PATH="${BUILD_DIR}/modules" modules_install

# Create initrd directory structure
echo "Creating initrd..."
INITRD_DIR="${BUILD_DIR}/initrd.dir"
rm -rf "${INITRD_DIR}"
mkdir -p "${INITRD_DIR}"/{bin,sbin,etc,proc,sys,dev,lib,lib64,usr/lib,usr/lib64}

# Copy required files for initrd
cp -a "${BUILD_DIR}/modules/lib/modules" "${INITRD_DIR}/lib/"

# Create basic init script
cat > "${INITRD_DIR}/init" << 'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
exec /sbin/init
EOF

# Make init executable
chmod +x "${INITRD_DIR}/init"

# Create initrd
cd "${INITRD_DIR}"
find . -print0 | cpio --null --create --format=newc | gzip > "${BUILD_DIR}/initrd.img"

cd "${KERNEL_SRC}"
echo "Kernel build complete!"
echo "${KERNEL_SRC}/arch/x86/boot/bzImage"
