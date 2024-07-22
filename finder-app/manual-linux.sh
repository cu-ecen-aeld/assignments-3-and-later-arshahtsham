#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -euxo pipefail  # Enable strict error handling and debugging

OUTDIR=/tmp/aeld
KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.1.10
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

if [ $# -lt 1 ]
then
    echo "Using default directory ${OUTDIR} for output"
else
    OUTDIR=$1
    echo "Using passed directory ${OUTDIR} for output"
fi

sudo mkdir -p ${OUTDIR}  # Requires sudo if the directory is not writable by the user

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
    sudo git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    sudo git checkout ${KERNEL_VERSION}

    # Apply manual fix for dtc issue
    # Ensure yylloc is declared extern in dtc-lexer.l if not already declared
    sudo sed -i 's/YYLTYPE yylloc;/extern YYLTYPE yylloc;/' scripts/dtc/dtc-lexer.l
    sudo sed -i '/YYLTYPE yylloc;/a YYLTYPE yylloc;' scripts/dtc/dtc.c

    # Kernel build steps
    echo "Configuring the kernel"
    sudo make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
    echo "Building the kernel"
    sudo make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all
    echo "Building kernel modules"
    sudo make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} modules
    echo "Building device tree blobs"
    sudo make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} dtbs
fi

echo "Adding the Image in outdir"
sudo cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ${OUTDIR}/Image

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
    echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm -rf ${OUTDIR}/rootfs
fi

sudo mkdir -p ${OUTDIR}/rootfs
cd ${OUTDIR}/rootfs
sudo mkdir -p bin dev etc home lib lib64 proc sbin sys tmp usr var
sudo mkdir -p usr/bin usr/lib usr/sbin
sudo mkdir -p var/log

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
    echo "Cloning BusyBox"
    sudo git clone git://busybox.net/busybox.git
    cd busybox
    sudo git checkout ${BUSYBOX_VERSION}
    # Configure BusyBox
    echo "Configuring BusyBox"
    sudo make distclean
    sudo make defconfig
else
    cd busybox
    # Ensure BusyBox is configured before building
    if [ ! -f .config ]; then
        echo "Configuring BusyBox"
        sudo make distclean
        sudo make defconfig
    fi
fi

# Make and install BusyBox
echo "PATH before sudo make: $PATH"
sudo env PATH=$PATH make -j$(nproc) ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE

echo "Installing BusyBox"
sudo make CONFIG_PREFIX=${OUTDIR}/rootfs ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} install

echo "Library dependencies"
sudo ${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "program interpreter"
sudo ${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "Shared library"

# Add library dependencies to rootfs
SYSROOT=$(sudo ${CROSS_COMPILE}gcc -print-sysroot)
sudo cp ${SYSROOT}/lib/ld-linux-aarch64.so.1 ${OUTDIR}/rootfs/lib
sudo cp ${SYSROOT}/lib64/libm.so.6 ${OUTDIR}/rootfs/lib64
sudo cp ${SYSROOT}/lib64/libresolv.so.2 ${OUTDIR}/rootfs/lib64
sudo cp ${SYSROOT}/lib64/libc.so.6 ${OUTDIR}/rootfs/lib64

# Make device nodes
echo "Creating device nodes"
sudo mknod -m 666 ${OUTDIR}/rootfs/dev/null c 1 3
sudo mknod -m 600 ${OUTDIR}/rootfs/dev/console c 5 1

# Clean and build the writer utility
echo "Building writer utility"
cd ${FINDER_APP_DIR}
sudo make clean
sudo make cross-compile CROSS_COMPILE=${CROSS_COMPILE}

sudo cp ${FINDER_APP_DIR}/writer.sh ${OUTDIR}/rootfs/home
sudo cp ${FINDER_APP_DIR}/writer ${OUTDIR}/rootfs/home
sudo cp ${FINDER_APP_DIR}/finder.sh ${OUTDIR}/rootfs/home
sudo cp -r ${FINDER_APP_DIR}/conf ${OUTDIR}/rootfs/home
sudo cp ${FINDER_APP_DIR}/finder-test.sh ${OUTDIR}/rootfs/home
sudo cp ${FINDER_APP_DIR}/autorun-qemu.sh ${OUTDIR}/rootfs/home

# Change ownership of the root directory to root
echo "Changing ownership of rootfs"
sudo chown -R root:root ${OUTDIR}/rootfs

# Create initramfs.cpio.gz
echo "Creating initramfs"
cd ${OUTDIR}/rootfs
(cd ${OUTDIR}/rootfs && sudo sh -c 'find . | cpio -H newc -o | gzip -f > ../initramfs.cpio.gz')

echo "Kernel and root filesystem build completed successfully."
echo "Kernel image: ${OUTDIR}/Image"
echo "Initramfs: ${OUTDIR}/initramfs.cpio.gz"

