#!/bin/bash

#set -x

# Source the kernel configuration
source ./kernel_config.sh

# Log the start of kernel build process
log_message "Starting kernel build process for version ${KERNEL_VERSION}"

KERNEL_SOURCE_DIR="${KERNEL_BUILD_DIR}/linux-${KERNEL_VERSION}"
KERNEL_PATH="${KERNEL_SOURCE_DIR}/arch/x86/boot/bzImage"
INITRAMFS_PATH="${INITRD_DIR}/initramfs-${KERNEL_VERSION}.img"

# Create build directory if it doesn't exist
mkdir -p "$KERNEL_BUILD_DIR"
cd "$KERNEL_BUILD_DIR"

# Download kernel if not already present
if [ ! -d "$KERNEL_SOURCE_DIR" ]; then
    log_message "Downloading Linux kernel ${KERNEL_VERSION}..."
    wget "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KERNEL_VERSION.tar.xz"
    tar xf "linux-$KERNEL_VERSION.tar.xz"
    rm "linux-$KERNEL_VERSION.tar.xz"
fi

cd "$KERNEL_SOURCE_DIR"

# Configure kernel if .config doesn't exist
if [ ! -f ".config" ]; then
    log_message "Configuring kernel..."
    make defconfig
    # Enable CXL support
    scripts/config --enable CONFIG_CXL_BUS
    scripts/config --enable CONFIG_CXL_MEM
    scripts/config --enable CONFIG_CXL_PORT
    scripts/config --enable CONFIG_CXL_ACPI
    scripts/config --enable CONFIG_CXL_PMEM
    scripts/config --enable CONFIG_CXL_MEM_RAW_COMMANDS
fi

# Build kernel
log_message "Building kernel..."
make -j$(nproc)

# Build and package modules
log_message "Installing kernel modules..."
make modules_install INSTALL_MOD_PATH="${BUILD_DIR}"

# Create initramfs directory
log_message "Creating initramfs structure..."
sudo rm -rf "$INITRD_DIR"
sudo mkdir -p "$INITRD_DIR"
cd "$INITRD_DIR"

# Create directory structure
sudo mkdir -p {bin,sbin,etc,proc,sys,usr/{bin,sbin},root,dev,lib64,lib/x86_64-linux-gnu,run,tmp,var/{log,run},newroot,lib/modules}

# Copy required libraries for busybox
if ! command -v busybox &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y busybox-static
fi

# Copy busybox and create symlinks
sudo cp $(which busybox) bin/busybox
sudo chmod 755 bin/busybox
cd bin
for prog in $(./busybox --list); do
    if [ "$prog" != "busybox" ]; then
        sudo ln -sf busybox "$prog"
    fi
done
cd "$INITRD_DIR"

# Copy blkid and required libraries
sudo cp $(which blkid) sbin/
for lib in $(ldd $(which blkid) | grep -o '/lib.*\.[0-9]'); do
    sudo cp --parents "$lib" .
done

# Create essential device nodes
sudo mknod -m 600 dev/console c 5 1
sudo mknod -m 666 dev/null c 1 3
sudo mknod -m 666 dev/zero c 1 5
sudo mknod -m 666 dev/ptmx c 5 2
sudo mknod -m 666 dev/tty c 5 0
sudo mknod -m 444 dev/random c 1 8
sudo mknod -m 444 dev/urandom c 1 9
sudo mknod -m 660 dev/sda b 8 0
sudo mknod -m 660 dev/sda1 b 8 1
sudo mknod -m 660 dev/sda2 b 8 2

# Copy kernel modules and generate modules.dep
log_message "Copying kernel modules..."
if [ -d "${BUILD_DIR}/lib/modules/${KERNEL_VERSION}.0" ]; then
    sudo cp -r "${BUILD_DIR}/lib/modules/${KERNEL_VERSION}.0" "${INITRD_DIR}/lib/modules/"
    cd "${INITRD_DIR}/lib/modules/${KERNEL_VERSION}.0"
    sudo rm -f modules.*
    cd "${INITRD_DIR}"
    sudo depmod -b "${INITRD_DIR}" "${KERNEL_VERSION}.0"
else
    log_message "ERROR: Kernel modules directory not found at ${BUILD_DIR}/lib/modules/${KERNEL_VERSION}.0"
    exit 1
fi

# Create essential files
log_message "Creating essential files..."
sudo touch "${INITRD_DIR}/etc/fstab"
echo "root::0:0:root:/root:/bin/sh" | sudo tee "${INITRD_DIR}/etc/passwd" > /dev/null
echo "root:x:0:" | sudo tee "${INITRD_DIR}/etc/group" > /dev/null
sudo chmod 644 "${INITRD_DIR}/etc/passwd" "${INITRD_DIR}/etc/group"

# Create init script
log_message "Creating init script..."
sudo tee "${INITRD_DIR}/init" << 'EOF' > /dev/null
#!/bin/sh

# Mount essential filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mount -t tmpfs tmpfs /tmp
mount -t tmpfs tmpfs /run

# Create necessary device nodes if devtmpfs is not used
[ -e /dev/console ] || mknod -m 600 /dev/console c 5 1
[ -e /dev/null ]    || mknod -m 666 /dev/null c 1 3

# Load necessary modules
for mod in $(find /lib/modules -name '*.ko'); do
    echo "Loading module: $mod"
    insmod $mod
done

# Set up basic networking
ip link set lo up
ip link set eth0 up

echo "Mounting root filesystem..."
mkdir -p /newroot

# Debug information
echo "Kernel command line:"
cat /proc/cmdline
echo "Block devices:"
ls -l /dev/vd*
echo "Partition info:"
cat /proc/partitions
echo "File system info:"
blkid

# Find root partition
ROOT_PART=""
for part in /dev/vda*; do
    if blkid "$part" | grep -q 'LABEL="cloudimg-rootfs"'; then
        echo "Found root partition: $part"
        ROOT_PART="$part"
        break
    fi
done

if [ -z "$ROOT_PART" ]; then
    echo "No root partition found!"
    echo "Available partitions:"
    blkid
    echo "Trying to mount each partition to check filesystem..."
    for part in /dev/vda*; do
        echo "Trying $part..."
        if mount -t ext4 "$part" /newroot 2>/dev/null; then
            if [ -d "/newroot/home" ] && [ -d "/newroot/etc" ]; then
                echo "Found root filesystem on $part"
                ROOT_PART="$part"
                umount /newroot
                break
            fi
            umount /newroot
        fi
    done
fi

if [ -z "$ROOT_PART" ]; then
    echo "Still no root partition found. Dropping to shell..."
    exec sh
fi

echo "Attempting to mount $ROOT_PART as root filesystem..."
mount -o rw "$ROOT_PART" /newroot

if [ $? -ne 0 ]; then
    echo "Failed to mount root filesystem!"
    echo "Available block devices:"
    ls -l /dev/vd*
    echo "Kernel modules loaded:"
    lsmod
    echo "Block device details:"
    blkid
    echo "Dropping to shell..."
    exec sh
fi

# Verify root filesystem
if [ ! -d "/newroot/home" ] || [ ! -d "/newroot/etc" ]; then
    echo "Mounted filesystem does not look like a root filesystem!"
    echo "Contents of /newroot:"
    ls -la /newroot
    echo "Dropping to shell..."
    exec sh
fi

echo "Root filesystem mounted successfully"
echo "Verifying password file..."
if [ -f "/newroot/etc/shadow" ]; then
    echo "Shadow file exists:"
    cat /newroot/etc/shadow | grep ubuntu
fi

echo "Switching to root filesystem..."
exec switch_root /newroot /sbin/init

# Fall back to shell if switch_root fails
exec sh
EOF

sudo chmod 755 "${INITRD_DIR}/init"

# Create the initramfs with proper output path
log_message "Creating initramfs image..."
cd "$INITRD_DIR"
sudo bash -c "find . -print0 | cpio --null --create --format=newc 2>/dev/null | gzip > '$INITRAMFS_PATH'"
sudo chown $(id -u):$(id -g) "$INITRAMFS_PATH"

cd "$KERNEL_SOURCE_DIR"
log_message "Kernel build completed successfully"
echo "$KERNEL_PATH"
