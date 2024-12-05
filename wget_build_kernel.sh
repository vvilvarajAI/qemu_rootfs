#!/bin/bash

set -x

# Variables
KERNEL_VERSION="6.8"
BUILD_DIR="/home/vvilvaraj/QEMU_CXL_DEV_TOOLS/temp"
KERNEL_SOURCE_DIR="$BUILD_DIR/linux-$KERNEL_VERSION"
KERNEL_PATH="$BUILD_DIR/linux-$KERNEL_VERSION/arch/x86/boot/bzImage"
INITRAMFS_PATH="$BUILD_DIR/initrd.dir/initramfs-${KERNEL_VERSION}.img"

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
sudo rm -rf "$BUILD_DIR/initrd.dir"
sudo mkdir -p "$BUILD_DIR/initrd.dir"
cd "$BUILD_DIR/initrd.dir"

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
cd ..

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
sudo cp -r "$BUILD_DIR/lib/modules/${KERNEL_VERSION}.0" lib/modules/
cd lib/modules/${KERNEL_VERSION}.0
sudo rm -f modules.*
cd ../../..
sudo depmod -b . "${KERNEL_VERSION}.0"

# Create essential files
sudo touch etc/fstab
echo "root::0:0:root:/root:/bin/sh" | sudo tee etc/passwd > /dev/null
echo "root:x:0:" | sudo tee etc/group > /dev/null
sudo chmod 644 etc/passwd etc/group

# Create init script
sudo tee init << 'EOF' > /dev/null
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
insmod /lib/modules/6.8.0/kernel/fs/ext4/ext4.ko
insmod /lib/modules/6.8.0/kernel/drivers/ata/libata.ko
insmod /lib/modules/6.8.0/kernel/drivers/scsi/scsi_mod.ko
insmod /lib/modules/6.8.0/kernel/drivers/scsi/sd_mod.ko
insmod /lib/modules/6.8.0/kernel/drivers/ata/ata_piix.ko

# Set up basic networking
ip link set lo up
ip link set eth0 up

echo "Mounting root filesystem..."
mkdir -p /newroot

# Debug information
echo "Kernel command line:"
cat /proc/cmdline
echo "Block devices:"
ls -l /dev/sd*
echo "Partition info:"
cat /proc/partitions
echo "File system info:"
blkid

# Find root partition
ROOT_PART=""
for part in /dev/sda*; do
    if blkid "$part" | grep -q 'TYPE="ext4"'; then
        echo "Found ext4 partition: $part"
        ROOT_PART="$part"
        break
    fi
done

if [ -z "$ROOT_PART" ]; then
    echo "No ext4 root partition found!"
    echo "Available partitions:"
    blkid
    echo "Trying to mount each partition to check filesystem..."
    for part in /dev/sda*; do
        echo "Trying $part..."
        if mount -t ext4 "$part" /newroot 2>/dev/null; then
            echo "Successfully mounted $part"
            ROOT_PART="$part"
            break
        else
            umount /newroot 2>/dev/null
        fi
    done
fi

if [ -z "$ROOT_PART" ]; then
    echo "Still no root partition found. Dropping to shell..."
    exec sh
fi

echo "Attempting to mount $ROOT_PART..."
mount -t ext4 "$ROOT_PART" /newroot

if [ $? -ne 0 ]; then
    echo "Failed to mount root filesystem!"
    echo "Available block devices:"
    ls -l /dev/sd*
    echo "Kernel modules loaded:"
    lsmod
    echo "Block device details:"
    blkid
    echo "Dropping to shell..."
    exec sh
fi

echo "Switching to root filesystem..."
exec switch_root /newroot /sbin/init

# Fall back to shell if switch_root fails
exec sh
EOF

sudo chmod 755 init

# Create the initramfs with proper output path
cd "$BUILD_DIR/initrd.dir"
sudo bash -c "find . -print0 | cpio --null --create --format=newc 2>/dev/null | gzip > '$INITRAMFS_PATH'"
sudo chown $(id -u):$(id -g) "$INITRAMFS_PATH"

cd "$KERNEL_SOURCE_DIR"
echo "Kernel build complete!"
echo "$KERNEL_PATH"
