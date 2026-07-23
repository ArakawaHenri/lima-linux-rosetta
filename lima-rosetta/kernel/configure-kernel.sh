#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu

src=${1:?usage: configure-kernel.sh SOURCE OUTPUT APPLE_CONFIG}
out=${2:?usage: configure-kernel.sh SOURCE OUTPUT APPLE_CONFIG}
base=${3:?usage: configure-kernel.sh SOURCE OUTPUT APPLE_CONFIG}

mkdir -p "$out"
cp "$base" "$out/.config"

# First migrate Apple's VZ/container kernel baseline to Linux 6.18.39 and to
# the active LLVM toolchain. Then apply the small, explicit Rosetta/Fedora
# delta and resolve dependencies one more time.
make -C "$src" ARCH=arm64 LLVM=1 O="$out" olddefconfig

cfg="$src/scripts/config"
config="$out/.config"

"$cfg" --file "$config" \
    --set-str LOCALVERSION "-rosetta-tso-lto" \
    --disable LOCALVERSION_AUTO \
    --enable CC_OPTIMIZE_FOR_PERFORMANCE \
    --disable CC_OPTIMIZE_FOR_SIZE \
    --disable LTO_NONE \
    --disable LTO_CLANG_THIN \
    --enable LTO_CLANG_FULL \
    --enable ARM64_TSO \
    --enable BTRFS_FS \
    --enable BTRFS_FS_POSIX_ACL \
    --enable RD_ZSTD \
    --enable PSI \
    --disable PSI_DEFAULT_DISABLED \
    --disable RT_GROUP_SCHED \
    --disable FW_LOADER_USER_HELPER \
    --disable NUMA \
    --disable NUMA_BALANCING \
    --disable SCHED_AUTOGROUP \
    --disable MODULES \
    --disable CFI_CLANG \
    --disable SHADOW_CALL_STACK \
    --disable UEVENT_HELPER \
    --set-str UEVENT_HELPER_PATH "" \
    --disable BPFILTER \
    --disable BPFILTER_UMH \
    --disable BPF_PRELOAD \
    --disable BPF_PRELOAD_UMD \
    --disable DEBUG_KERNEL \
    --disable DEBUG_MISC \
    --disable DEBUG_FS \
    --disable DEBUG_LIST \
    --disable DEBUG_MEMORY_INIT \
    --disable DEBUG_SECTION_MISMATCH \
    --disable DYNAMIC_DEBUG \
    --disable SLUB_DEBUG \
    --disable BUG_ON_DATA_CORRUPTION \
    --disable EXT4_DEBUG \
    --disable FUSE_DAX \
    --disable VIRTIO_PCI_LEGACY \
    --disable VIRTIO_PMEM \
    --disable VIRTIO_INPUT \
    --disable VIRTIO_IOMMU \
    --disable VIRTIO_DMA_SHARED_BUFFER \
    --disable KVM \
    --disable VIRTUALIZATION \
    --disable KEXEC \
    --disable KEXEC_FILE \
    --disable HIBERNATION \
    --disable PM_SLEEP \
    --disable CPU_FREQ \
    --disable CPU_IDLE \
    --disable DRM \
    --disable FB \
    --disable INPUT \
    --disable HID \
    --disable I2C \
    --disable GPIOLIB \
    --disable THERMAL \
    --disable WATCHDOG \
    --enable RTC_CLASS \
    --enable RTC_HCTOSYS \
    --set-str RTC_HCTOSYS_DEVICE "rtc0" \
    --enable RTC_SYSTOHC \
    --set-str RTC_SYSTOHC_DEVICE "rtc0" \
    --disable RTC_DRV_PL030 \
    --enable RTC_DRV_PL031 \
    --disable SCSI \
    --enable SECURITY \
    --enable SECURITY_NETWORK \
    --enable SECURITY_SELINUX \
    --enable SECURITY_SELINUX_BOOTPARAM \
    --enable SECURITY_SELINUX_DEVELOP \
    --enable SECURITY_YAMA \
    --enable LANDLOCK \
    --enable BPF_LSM \
    --set-str LSM "landlock,lockdown,yama,integrity,selinux,bpf"

make -C "$src" ARCH=arm64 LLVM=1 O="$out" olddefconfig

for symbol in \
    CONFIG_CC_IS_CLANG=y \
    CONFIG_LD_IS_LLD=y \
    CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y \
    CONFIG_LTO_CLANG_FULL=y \
    CONFIG_ARM64_TSO=y \
    CONFIG_ACPI=y \
    CONFIG_PCI_HOST_GENERIC=y \
    CONFIG_SERIAL_AMBA_PL011_CONSOLE=y \
    CONFIG_VIRTIO_PCI=y \
    CONFIG_VIRTIO_BLK=y \
    CONFIG_VIRTIO_NET=y \
    CONFIG_VIRTIO_CONSOLE=y \
    CONFIG_VIRTIO_FS=y \
    CONFIG_VIRTIO_VSOCKETS=y \
    CONFIG_RTC_CLASS=y \
    CONFIG_RTC_DRV_PL031=y \
    CONFIG_BTRFS_FS=y \
    CONFIG_EXT4_FS=y \
    CONFIG_BINFMT_MISC=y \
    CONFIG_CGROUPS=y \
    CONFIG_NAMESPACES=y \
    CONFIG_SECCOMP_FILTER=y \
    CONFIG_SECURITY_SELINUX=y
do
    if ! grep -qxF "$symbol" "$config"; then
        printf 'missing required setting: %s\n' "$symbol" >&2
        exit 1
    fi
done

for symbol in \
    CONFIG_MODULES \
    CONFIG_LTO_NONE \
    CONFIG_LTO_CLANG_THIN \
    CONFIG_UEVENT_HELPER \
    CONFIG_VIRTIO_PCI_LEGACY
do
    if ! grep -qxF "# $symbol is not set" "$config"; then
        printf 'setting was expected to be disabled: %s\n' "$symbol" >&2
        exit 1
    fi
done

printf 'configured %s\n' "$config"
