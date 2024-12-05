#!/bin/bash

set -x

# Variables
KERNEL_VERSION="6.8"
BUILD_DIR="/workspace/data/kernel"
KERNEL_SOURCE_DIR="$BUILD_DIR/linux-$KERNEL_VERSION"
KERNEL_PATH="$BUILD_DIR/linux-$KERNEL_VERSION/arch/x86/boot/bzImage"
INITRAMFS_PATH="$BUILD_DIR/initramfs-${KERNEL_VERSION}.img"
INITRD_DIR="$BUILD_DIR/initrd.dir"

# Create build directory if it doesn't exist
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Download kernel if not already present
if [ ! -d "$KERNEL_SOURCE_DIR" ]; then
    echo "Downloading Linux kernel $KERNEL_VERSION..."
    wget "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KERNEL_VERSION.tar.xz"
    tar xf "linux-$KERNEL_VERSION.tar.xz"
    rm "linux-$KERNEL_VERSION.tar.xz"
fi

cd "$KERNEL_SOURCE_DIR"

# Configure kernel if .config doesn't exist
if [ ! -f ".config" ]; then
    echo "Configuring kernel..."
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
echo "Building kernel..."
make -j$(nproc)

# Build and package modules
make modules_install INSTALL_MOD_PATH="$BUILD_DIR"

# Create initramfs directory
rm -rf "$INITRD_DIR"
mkdir -p "$INITRD_DIR"
cd "$INITRD_DIR"

# Create directory structure
mkdir -p {bin,sbin,etc,proc,sys,usr/{bin,sbin},root,dev,lib64,lib/x86_64-linux-gnu,run,tmp,var/{log,run},newroot,lib/modules}

# Install busybox if not present
if ! command -v busybox &> /dev/null; then
    apt-get update
    apt-get install -y busybox-static
fi

# Copy busybox and create symlinks
cp $(which busybox) bin/busybox
chmod 755 bin/busybox
cd bin
for prog in $(./busybox --list); do
    if [ "$prog" != "busybox" ]; then
        ln -sf busybox "$prog"
    fi
done
cd ..

# Copy blkid and required libraries
cp $(which blkid) sbin/
for lib in $(ldd $(which blkid) | grep -o '/lib.*\.[0-9]'); do
    cp --parents "$lib" .
done

# Create essential device nodes
mknod -m 600 dev/console c 5 1
mknod -m 666 dev/null c 1 3
mknod -m 666 dev/zero c 1 5
mknod -m 666 dev/ptmx c 5 2
mknod -m 666 dev/tty c 5 0
mknod -m 444 dev/random c 1 8
mknod -m 444 dev/urandom c 1 9
mknod -m 660 dev/vda b 254 0
mknod -m 660 dev/vda1 b 254 1
mknod -m 660 dev/vda2 b 254 2

# Copy kernel modules
cp -r "$BUILD_DIR/lib/modules/${KERNEL_VERSION}.0" lib/modules/
cd lib/modules/${KERNEL_VERSION}.0
rm -f modules.*
cd ../../..
depmod -b . "${KERNEL_VERSION}.0"

# Create essential files
touch etc/fstab
echo "root::0:0:root:/root:/bin/sh" > etc/passwd
echo "root:x:0:" > etc/group
chmod 644 etc/passwd etc/group

# Create init script
cat > init << 'EOF'
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

echo "Root filesystem mounted successfully"
echo "Switching to root filesystem..."
exec switch_root /newroot /sbin/init

# Fall back to shell if switch_root fails
exec sh
EOF

chmod 755 init

# Create the initramfs
find . -print0 | cpio --null --create --format=newc 2>/dev/null | gzip > "$INITRAMFS_PATH"

cd "$KERNEL_SOURCE_DIR"
echo "Kernel build complete!"
echo "$KERNEL_PATH"
