#!/bin/bash
#
# OpenIPC | version 2023.11.30

DEVICE="$1"
BUILDER_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
FIRMWARE_DIR="${BUILDER_DIR}/openipc"
FIRMWARE_REPO="${OPENIPC_FW_REPO:-https://github.com/OpenIPC/firmware.git}"
TIMESTAMP=$(date +"%Y%m%d%H%M")
VERSION=$(stat -c"%Y" "$0")

cd "$BUILDER_DIR" || exit 1

echo_c() {
    t="\e[1;$1m$2\e[0m" || t="$2"
    echo -e "$t"
}

autoup_rootfs() {
    DT=$(date +"%y.%m.%d")
    OPENIPC_VER=$(echo OpenIPC v${DT:0:1}.${DT:1})
    SOC=$(echo "${DEVICE}" | cut -d_ -f1)

    echo_c 34 "\nDownloading u-boot created by OpenIPC"
    curl --location --output ./output/images/u-boot-${SOC}-universal.bin \
        https://github.com/OpenIPC/firmware/releases/download/latest/u-boot-${SOC}-universal.bin || return 1

    echo_c 34 "\nMaking autoupdate u-boot image"
    ./output/host/bin/mkimage -A arm -O linux -T firmware -n "$OPENIPC_VER" \
        -a 0x0 -e 0x50000 -d ./output/images/u-boot-${SOC}-universal.bin \
        ./output/images/autoupdate-uboot.img || return 1

    echo_c 34 "\nMaking autoupdate kernel image"
    ./output/host/bin/mkimage -A arm -O linux -T kernel -C none -n "$OPENIPC_VER" \
        -a 0x50000 -e 0x250000 -d ./output/images/uImage.${SOC} \
        ./output/images/autoupdate-kernel.img || return 1

    echo_c 34 "\nMaking autoupdate rootfs image"
    ./output/host/bin/mkimage -A arm -O linux -T filesystem -n "$OPENIPC_VER" \
        -a 0x250000 -e 0x750000 -d ./output/images/rootfs.squashfs.${SOC} \
        ./output/images/autoupdate-rootfs.img
}

copy_to_archive() {
    if echo "${DEVICE}" | grep -q '^hi3518ev200_lite'; then
        autoup_rootfs || return 1
    fi

    echo_c 32 "Copying files to local archive"
    mkdir -p "${BUILDER_DIR}/archive/${DEVICE}/${TIMESTAMP}"
    cp -a \
        ${FIRMWARE_DIR}/output/images/rootfs.squashfs.* \
        ${FIRMWARE_DIR}/output/images/uImage.* \
        ${FIRMWARE_DIR}/output/images/*.tar \
        ${FIRMWARE_DIR}/output/images/openipc.*.tgz \
        "${BUILDER_DIR}/archive/${DEVICE}/${TIMESTAMP}" || return 1

    cp -a ${FIRMWARE_DIR}/output/images/sizes.*.json \
        "${BUILDER_DIR}/archive/${DEVICE}/${TIMESTAMP}" 2>/dev/null || true

    if [ -f "${FIRMWARE_DIR}/output/images/autoupdate-kernel.img" ]; then
        cp -a ${FIRMWARE_DIR}/output/images/autoupdate* \
            "${BUILDER_DIR}/archive/${DEVICE}/${TIMESTAMP}" || return 1
    fi

    echo_c 35 "\nAssembled firmware available in:"
    tree -C "${BUILDER_DIR}/archive/${DEVICE}/${TIMESTAMP}"
}

copy_to_tftp() {
    echo_c 32 "\nCopying files to a TFTP server using SCP protocol"
    scp -r \
        ${FIRMWARE_DIR}/output/images/rootfs.squashfs.* \
        ${FIRMWARE_DIR}/output/images/uImage.* \
        ${FIRMWARE_DIR}/output/images/openipc.*.tgz \
        "${TFTP_STORAGE}"

    if [ -f "${FIRMWARE_DIR}/output/images/autoupdate-kernel.img" ]; then
        scp -r ${FIRMWARE_DIR}/output/images/autoupdate* "${TFTP_STORAGE}"
    fi
}

select_device() {
    AVAILABLE_DEVICES=$(find devices -name '*_defconfig' | sort | cut -d/ -f5)
    cmd="whiptail --title \"Available devices\" --menu \"Please select a device from the list below:\" 20 70 12"
    for p in ${AVAILABLE_DEVICES//_defconfig}; do
        cmd="${cmd} \"$p\" \"\""
    done
    DEVICE=$(eval "${cmd} 3>&1 1>&2 2>&3")
    if [ $? != 0 ]; then
        echo_c 31 "Cancelled."
        exit 1
    fi
}

resolve_device() {
    mapfile -t matches < <(find devices -name "${DEVICE}_defconfig" -print)

    if [ "${#matches[@]}" -ne 1 ]; then
        echo_c 31 "Expected exactly one defconfig for ${DEVICE}, found ${#matches[@]}"
        exit 2
    fi

    ITEM=$(dirname "$(dirname "$(dirname "${matches[0]}")")")
}

validate_build_environment() {
    if [[ "$PATH" =~ [[:space:]] ]]; then
        echo_c 31 "PATH contains whitespace; Buildroot cannot reliably use this environment."
        echo_c 31 "Remove Windows/WSL PATH entries with spaces and retry."
        exit 2
    fi
}

register_package_tree() {
    package_root="$1"
    package_list_file="${FIRMWARE_DIR}/general/package/Config.in"

    [ -d "$package_root" ] || return 0

    for f in "$package_root"/*; do
        [ -d "$f" ] || continue
        [ -f "$f/Config.in" ] || continue
        package_name=$(basename "$f")
        source_line="source \"\$BR2_EXTERNAL_GENERAL_PATH/package/$package_name/Config.in\""
        if ! grep -Fqx "$source_line" "$package_list_file"; then
            printf '%s\n' "$source_line" >> "$package_list_file" || return 1
        fi
    done
}

validate_device_packages() {
    device_packages="${BUILDER_DIR}/${ITEM}/general/package"
    global_packages="${BUILDER_DIR}/package"

    [ -d "$device_packages" ] || return 0

    for f in "$device_packages"/*; do
        [ -d "$f" ] || continue
        package_name=$(basename "$f")
        if [ -d "$global_packages/$package_name" ]; then
            echo_c 31 "Device package collides with global package: $package_name"
            exit 2
        fi
        if [ ! -f "$f/Config.in" ]; then
            echo_c 31 "Device package has no Config.in: $f"
            exit 2
        fi
    done
}

copy_extra_packages() {
    extra_package="${BUILDER_DIR}/package"
    firmware_package="${FIRMWARE_DIR}/general/package"

    [ -d "$extra_package" ] || return 0
    cp -afv "${extra_package}/." "$firmware_package/" || return 1
    register_package_tree "$extra_package"
}

echo_c 37 "Experimental system for building OpenIPC firmware for known devices"
echo_c 30 "https://openipc.org/"
echo_c 30 "Version: ${VERSION}"

while [ -z "${DEVICE}" ]; do
    select_device
done

resolve_device
validate_build_environment
validate_device_packages

echo_c 31 "\nStarting a device for ${DEVICE}"
tree -C "${ITEM}"

# Build exactly the checked-out Builder revision. Do not mutate this checkout.
if [ "$FIRMWARE_DIR" != "${BUILDER_DIR}/openipc" ]; then
    echo_c 31 "Refusing to remove unexpected firmware directory: ${FIRMWARE_DIR}"
    exit 2
fi
rm -rf -- "$FIRMWARE_DIR"

if [ -n "${OPENIPC_FW_REV:-}" ]; then
    echo_c 33 "\nDownloading Firmware @ ${OPENIPC_FW_REV}"
    git clone "$FIRMWARE_REPO" "$FIRMWARE_DIR" || exit 1
    git -C "$FIRMWARE_DIR" checkout "$OPENIPC_FW_REV" || exit 1
else
    echo_c 33 "\nDownloading Firmware"
    git clone --depth=1 "$FIRMWARE_REPO" "$FIRMWARE_DIR" || exit 1
fi

echo_c 33 "\nCopying extra packages"
copy_extra_packages || exit 1

echo_c 33 "\nCopying device files"
cp -afv "${BUILDER_DIR}/${ITEM}/." "$FIRMWARE_DIR/" || exit 1

echo_c 33 "\nRegistering device-local packages"
register_package_tree "${BUILDER_DIR}/${ITEM}/general/package" || exit 1

cd "$FIRMWARE_DIR" || exit 1

echo_c 33 "\nBuilding the device"
make BOARD="${DEVICE}"
BUILD_RC=$?
if [ ${BUILD_RC} -ne 0 ]; then
    echo_c 31 "\nBuild FAILED (make exited ${BUILD_RC}) - not archiving"
    exit ${BUILD_RC}
fi

make BOARD="${DEVICE}" size-report || true

copy_to_archive || exit 1
echo_c 35 "\nDone"
cd "$BUILDER_DIR" || exit 1
