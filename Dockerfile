FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update && apt-get install -y \
    qemu-utils \
    cloud-image-utils \
    wget \
    build-essential \
    flex \
    bison \
    libelf-dev \
    libssl-dev \
    bc \
    python3 \
    python3-pip \
    python3-venv \
    python3-setuptools \
    python3-dev \
    python3-wheel \
    git \
    kmod \
    ninja-build \
    pkg-config \
    libglib2.0-dev \
    libpixman-1-dev \
    libslirp-dev \
    libcap-ng-dev \
    libattr1-dev \
    meson \
    libsdl2-dev \
    libspice-server-dev \
    libspice-protocol-dev \
    libaio-dev \
    libiscsi-dev \
    libnuma-dev \
    libcap-dev \
    libseccomp-dev \
    libfdt-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies for kernel build
RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install tomli toml setuptools wheel

# Build QEMU from source with CXL support
WORKDIR /build
RUN git clone https://github.com/qemu/qemu.git && \
    cd qemu && \
    git checkout master && \
    git submodule init && \
    git submodule update --recursive && \
    mkdir build && \
    cd build && \
    ../configure --target-list=x86_64-softmmu \
                 --enable-slirp \
                 --enable-debug \
                 --disable-werror \
                 --enable-sdl \
                 --enable-spice \
                 --enable-numa && \
    make -j$(nproc) && \
    make install && \
    cd / && \
    rm -rf /build

# Create working directory
WORKDIR /workspace

# Create necessary directories
RUN mkdir -p /workspace/data/rootfs \
    && mkdir -p /workspace/data/kernel \
    && mkdir -p /workspace/data/logs \
    && mkdir -p /workspace/shared

# Copy scripts and configurations
COPY wget_build_kernel.sh .
COPY run_qemu_with_rootfs.sh .
COPY create_rootfs.sh .
COPY cloud-init.cfg .

# Make scripts executable
RUN chmod +x *.sh

# Create entrypoint script
RUN echo '#!/bin/bash\n\
cd /workspace\n\
\n\
# Setup logging\n\
exec 1> >(tee -a "/workspace/data/logs/qemu-cxl-$(date +%Y%m%d-%H%M%S).log")\n\
exec 2>&1\n\
\n\
echo "Starting QEMU-CXL environment at $(date)"\n\
\n\
if [ ! -f "/workspace/data/rootfs/ubuntu2024-server.qcow2" ]; then\n\
    echo "Creating root filesystem..."\n\
    ./create_rootfs.sh\n\
fi\n\
\n\
if [ ! -f "/workspace/data/kernel/linux-6.8/arch/x86/boot/bzImage" ]; then\n\
    echo "Building kernel..."\n\
    ./wget_build_kernel.sh\n\
fi\n\
\n\
echo "Starting QEMU..."\n\
./run_qemu_with_rootfs.sh\n' > /entrypoint.sh && chmod +x /entrypoint.sh

VOLUME ["/workspace/data", "/workspace/shared"]

ENTRYPOINT ["/entrypoint.sh"] 