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

mkdir -p ${OUTDIR}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    # Clone only if the repository does not exist.
    echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
    git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    # Apply manual fix for dtc issue
    sed -i 's/YYLTYPE yylloc;/extern YYLTYPE yylloc;/' scripts/dtc/dtc-lexer.l
    sed -i '/YYLTYPE yylloc;/a YYLTYPE yylloc;' scripts/dtc/dtc.c

    # Kernel build steps
    echo "Configuring the kernel"
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
    echo "Building the kernel"
    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all
    echo "Building kernel modules"
    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} modules
    echo "Building device tree blobs"
    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} dtbs
fi

echo "Adding the Image in outdir"
cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ${OUTDIR}/Image

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
    echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm -rf ${OUTDIR}/rootfs
fi

mkdir -p ${OUTDIR}/rootfs
cd ${OUTDIR}/rootfs
mkdir -p bin dev etc home lib lib64 proc sbin sys tmp usr var
mkdir -p usr/bin usr/lib usr/sbin
mkdir -p var/log

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
    echo "Cloning BusyBox"
    git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    # Configure BusyBox
    echo "Configuring BusyBox"
    make distclean
    make defconfig
    if [ $? -ne 0 ]; then
        echo "BusyBox defconfig failed"
        exit 1
    fi
else
    cd busybox
    # Ensure BusyBox is configured before building
    if [ ! -f .config ]; then
        echo "Configuring BusyBox"
        make distclean
        make defconfig
        if [ $? -ne 0 ]; then
            echo "BusyBox defconfig failed"
            exit 1
        fi
    fi
fi

# Make and install BusyBox
echo "Building BusyBox"
make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
if [ $? -ne 0 ]; then
    echo "BusyBox build failed"
    exit 1
fi
echo "Installing BusyBox"
make CONFIG_PREFIX=${OUTDIR}/rootfs ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} install
if [ $? -ne 0 ]; then
    echo "BusyBox install failed"
    exit 1
fi

echo "Library dependencies"
${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "Shared library"

# Add library dependencies to rootfs
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)
cp ${SYSROOT}/lib/ld-linux-aarch64.so.1 ${OUTDIR}/rootfs/lib
cp ${SYSROOT}/lib64/libm.so.6 ${OUTDIR}/rootfs/lib64
cp ${SYSROOT}/lib64/libresolv.so.2 ${OUTDIR}/rootfs/lib64
cp ${SYSROOT}/lib64/libc.so.6 ${OUTDIR}/rootfs/lib64

# Make device nodes
echo "Creating device nodes"
sudo mknod -m 666 ${OUTDIR}/rootfs/dev/null c 1 3
sudo mknod -m 600 ${OUTDIR}/rootfs/dev/console c 5 1

# Clean and build the writer utility
echo "Building writer utility"
cd ${FINDER_APP_DIR}
make clean
make cross-compile CROSS_COMPILE=${CROSS_COMPILE}

cp ${FINDER_APP_DIR}/writer.sh ${OUTDIR}/rootfs/home

# Copy the finder related scripts and executables to the /home directory on the target rootfs
echo "Copying files to rootfs"
cp ${FINDER_APP_DIR}/writer ${OUTDIR}/rootfs/home
cp ${FINDER_APP_DIR}/finder.sh ${OUTDIR}/rootfs/home

# Check if a file named 'conf' exists and remove it
if [ -f "${OUTDIR}/rootfs/home/conf" ]; then
    rm "${OUTDIR}/rootfs/home/conf"
fi

# Copy the 'conf' directory
cp -r ${FINDER_APP_DIR}/conf ${OUTDIR}/rootfs/home

cp ${FINDER_APP_DIR}/finder-test.sh ${OUTDIR}/rootfs/home
cp ${FINDER_APP_DIR}/autorun-qemu.sh ${OUTDIR}/rootfs/home


# Change ownership of the root directory to root
echo "Changing ownership of rootfs"
sudo chown -R root:root ${OUTDIR}/rootfs

# Create initramfs.cpio.gz
echo "Creating initramfs"
cd ${OUTDIR}/rootfs
find . | cpio -H newc -o > ${OUTDIR}/initramfs.cpio
gzip -f ${OUTDIR}/initramfs.cpio

echo "Kernel and root filesystem build completed successfully."
echo "Kernel image: ${OUTDIR}/Image"
echo "Initramfs: ${OUTDIR}/initramfs.cpio.gz"

