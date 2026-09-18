#!/bin/bash
#
# OpenIPC | version 2023.11.30

DEVICE="$1"
BUILDER_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
FIRMWARE_DIR="${BUILDER_DIR}/openipc"
FIRMWARE_TMP="${BUILDER_DIR}/.openipc.new.$"
DEFAULT_FIRMWARE_REPO="https://github.com/OpenIPC/firmware.git"
FIRMWARE_REPO="${OPENIPC_FW_REPO:-$DEFAULT_FIRMWARE_REPO}"
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
BUILDER_REV=$(git -C "$BUILDER_DIR" rev-parse HEAD 2>/dev/null || echo unknown)
VERSION=$(printf '%s' "$BUILDER_REV" | cut -c1-12)

cd "$BUILDER_DIR" || exit 1

exec 8>"$BUILDER_DIR/.builder.lock"
if ! flock -n 8; then
    echo "Another Builder run is already using $BUILDER_DIR" >&2
    exit 2
fi

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
    local archive_dir
    local -a artifacts size_reports autoupdate

    if echo "${DEVICE}" | grep -q '^hi3518ev200_lite'; then
        autoup_rootfs || return 1
    fi

    archive_dir="${BUILDER_DIR}/archive/${DEVICE}/${TIMESTAMP}"
    mkdir -p "$archive_dir" || return 1

    shopt -s nullglob
    artifacts=(
        "${FIRMWARE_DIR}"/output/images/rootfs.squashfs.*
        "${FIRMWARE_DIR}"/output/images/uImage.*
        "${FIRMWARE_DIR}"/output/images/*.tar
        "${FIRMWARE_DIR}"/output/images/openipc.*.tgz
    )
    size_reports=("${FIRMWARE_DIR}"/output/images/sizes.*.json)
    autoupdate=("${FIRMWARE_DIR}"/output/images/autoupdate*)
    shopt -u nullglob

    if [ "${#artifacts[@]}" -eq 0 ]; then
        echo_c 31 "No firmware artifacts found after successful build"
        return 1
    fi

    echo_c 32 "Copying files to local archive"
    cp -a "${artifacts[@]}" "$archive_dir/" || return 1
    [ "${#size_reports[@]}" -eq 0 ] || cp -a "${size_reports[@]}" "$archive_dir/" || return 1
    [ "${#autoupdate[@]}" -eq 0 ] || cp -a "${autoupdate[@]}" "$archive_dir/" || return 1

    if [ -f "${FIRMWARE_DIR}/output/openipc_defconfig" ]; then
        cp -a "${FIRMWARE_DIR}/output/openipc_defconfig"             "$archive_dir/input.openipc_defconfig" || return 1
    fi
    if [ -f "${FIRMWARE_DIR}/output/.config" ]; then
        cp -a "${FIRMWARE_DIR}/output/.config"             "$archive_dir/resolved.buildroot.config" || return 1
    fi

    {
        printf 'target=%s\n' "$DEVICE"
        printf 'built_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'builder_rev=%s\n' "$BUILDER_REV"
        printf 'firmware_repo=%s\n' "$FIRMWARE_REPO"
        printf 'firmware_requested_rev=%s\n' "${OPENIPC_FW_REV:-HEAD}"
        printf 'firmware_resolved_rev=%s\n' "${FIRMWARE_RESOLVED_REV:-unknown}"
        printf 'target_definition=%s\n' "${VARIANT_SOURCE:-classic-defconfig}"
        if [ -f "$archive_dir/resolved.buildroot.config" ]; then
            printf 'resolved_config_sha256=%s\n'                 "$(sha256sum "$archive_dir/resolved.buildroot.config" | awk '{print $1}')"
        fi
    } > "$archive_dir/build-info.txt" || return 1

    echo_c 35 "\nAssembled firmware available in:"
    tree -C "$archive_dir"
}

select_device() {
    local target
    local -a menu=()

    while IFS= read -r target; do
        menu+=("$target" "")
    done < <(
        {
            find devices -name '*_defconfig' -print |
                while IFS= read -r path; do basename "$path" _defconfig; done
            find devices -path '*/configs/variants/*.config' ! -name base.config -print |
                while IFS= read -r path; do basename "$path" .config; done
        } | sort -u
    )

    if [ "${#menu[@]}" -eq 0 ]; then
        echo_c 31 "No device targets found"
        exit 2
    fi

    DEVICE=$(whiptail --title "Available devices" \
        --menu "Please select a device from the list below:" 20 78 14 \
        "${menu[@]}" 3>&1 1>&2 2>&3)
    if [ $? != 0 ]; then
        echo_c 31 "Cancelled."
        exit 1
    fi
}

resolve_device() {
    local total
    mapfile -t matches < <(find devices -name "${DEVICE}_defconfig" -print)
    mapfile -t variants < <(find devices -path "*/configs/variants/${DEVICE}.config" ! -name base.config -print)
    total=$((${#matches[@]} + ${#variants[@]}))

    if [ "$total" -ne 1 ]; then
        echo_c 31 "Expected exactly one target definition for ${DEVICE}, found $total"
        exit 2
    fi

    VARIANT_SOURCE=
    VARIANT_BASE=
    VARIANT_FIRMWARE_BASE=
    VARIANT_FIRMWARE_META=
    VARIANT_OUTPUT=

    if [ "${#matches[@]}" -eq 1 ]; then
        ITEM=$(printf '%s\n' "${matches[0]}" | cut -d/ -f1,2)
        return
    fi

    VARIANT_SOURCE="${variants[0]}"
    ITEM=$(printf '%s\n' "$VARIANT_SOURCE" | cut -d/ -f1,2)
    variant_dir=$(dirname "$VARIANT_SOURCE")
    config_dir=$(dirname "$variant_dir")
    VARIANT_BASE="$variant_dir/base.config"
    firmware_base_file="$variant_dir/firmware-base"
    VARIANT_FIRMWARE_META="$variant_dir/${DEVICE}.firmware"
    VARIANT_OUTPUT="${config_dir#${ITEM}/}/${DEVICE}_defconfig"

    if [ ! -f "$VARIANT_BASE" ]; then
        echo_c 31 "Variant base is missing: $VARIANT_BASE"
        exit 2
    fi
    if [ ! -f "$firmware_base_file" ]; then
        echo_c 31 "Firmware base selector is missing: $firmware_base_file"
        exit 2
    fi

    IFS= read -r VARIANT_FIRMWARE_BASE < "$firmware_base_file"
    case "$VARIANT_FIRMWARE_BASE" in
        ""|/*|*..*)
            echo_c 31 "Invalid Firmware base path: $VARIANT_FIRMWARE_BASE"
            exit 2
            ;;
    esac
}

compose_device_variant() {
    [ -n "${VARIANT_SOURCE:-}" ] || return 0

    output="${FIRMWARE_DIR}/${VARIANT_OUTPUT}"
    firmware_base="${FIRMWARE_DIR}/${VARIANT_FIRMWARE_BASE}"

    if [ ! -f "$firmware_base" ]; then
        echo_c 31 "Selected Firmware branch does not provide: $VARIANT_FIRMWARE_BASE"
        return 1
    fi

    mkdir -p "$(dirname "$output")" || return 1
    {
        cat "$firmware_base"
        printf '\n# Named-device delta: ANJIA AJL33PQ0866\n'
        cat "${BUILDER_DIR}/${VARIANT_BASE}"
        printf '\n# Runtime variant: %s\n' "$DEVICE"
        cat "${BUILDER_DIR}/${VARIANT_SOURCE}"
    } > "$output" || return 1

    # Builder-only composition metadata must not leak into the Firmware tree.
    rm -rf -- "${FIRMWARE_DIR}/$(dirname "${VARIANT_OUTPUT}")/variants"
}

validate_build_environment() {
    if [[ "$PATH" =~ [[:space:]] ]]; then
        echo_c 31 "PATH contains whitespace; Buildroot cannot reliably use this environment."
        echo_c 31 "Remove Windows/WSL PATH entries with spaces and retry."
        exit 2
    fi
}

apply_variant_firmware_source() {
    local key value meta_repo= meta_rev=

    [ -n "${VARIANT_FIRMWARE_META:-}" ] || return 0
    [ -f "$VARIANT_FIRMWARE_META" ] || return 0

    while IFS='=' read -r key value; do
        case "$key" in
            repo) meta_repo="$value" ;;
            rev) meta_rev="$value" ;;
            ""|'#'*) ;;
            *)
                echo_c 31 "Unknown variant Firmware metadata key: $key"
                exit 2
                ;;
        esac
    done < "$VARIANT_FIRMWARE_META"

    if [ -z "$meta_repo" ] || [ -z "$meta_rev" ]; then
        echo_c 31 "Incomplete variant Firmware metadata: $VARIANT_FIRMWARE_META"
        exit 2
    fi

    if [ -z "${OPENIPC_FW_REPO:-}" ]; then
        FIRMWARE_REPO="$meta_repo"
    fi
    if [ -z "${OPENIPC_FW_REV:-}" ]; then
        OPENIPC_FW_REV="$meta_rev"
    fi
}

validate_firmware_source() {
    if [ "$FIRMWARE_REPO" != "$DEFAULT_FIRMWARE_REPO" ] &&
       [ -z "${OPENIPC_FW_REV:-}" ]; then
        echo_c 31 "OPENIPC_FW_REPO override requires OPENIPC_FW_REV"
        echo_c 31 "Pin the staging fork to a branch, tag, or commit explicitly."
        exit 2
    fi
}

cleanup_firmware_tmp() {
    [ ! -e "$FIRMWARE_TMP" ] || rm -rf -- "$FIRMWARE_TMP"
}

prepare_firmware_checkout() {
    cleanup_firmware_tmp

    if [ -n "${OPENIPC_FW_REV:-}" ]; then
        local resolved_ref

        echo_c 33 "\nDownloading Firmware @ ${OPENIPC_FW_REV}"
        git clone "$FIRMWARE_REPO" "$FIRMWARE_TMP" || return 1

        resolved_ref="$OPENIPC_FW_REV"
        if ! git -C "$FIRMWARE_TMP" rev-parse --verify "${resolved_ref}^{commit}" >/dev/null 2>&1; then
            resolved_ref="origin/$OPENIPC_FW_REV"
        fi
        if ! git -C "$FIRMWARE_TMP" rev-parse --verify "${resolved_ref}^{commit}" >/dev/null 2>&1; then
            git -C "$FIRMWARE_TMP" fetch --no-tags origin "$OPENIPC_FW_REV" || return 1
            resolved_ref=FETCH_HEAD
        fi
        git -C "$FIRMWARE_TMP" checkout --detach "$resolved_ref" || return 1
    else
        echo_c 33 "\nDownloading Firmware"
        git clone --depth=1 "$FIRMWARE_REPO" "$FIRMWARE_TMP" || return 1
    fi

    git -C "$FIRMWARE_TMP" rev-parse --verify HEAD >/dev/null || return 1

    rm -rf -- "$FIRMWARE_DIR"
    mv "$FIRMWARE_TMP" "$FIRMWARE_DIR" || return 1
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
apply_variant_firmware_source
validate_build_environment
validate_firmware_source
validate_device_packages

trap cleanup_firmware_tmp EXIT

echo_c 31 "\nStarting a device for ${DEVICE}"
echo_c 30 "Firmware source: ${FIRMWARE_REPO}${OPENIPC_FW_REV:+ @ ${OPENIPC_FW_REV}}"
tree -C "${ITEM}"

# Build exactly the checked-out Builder revision. Do not mutate this checkout.
if [ "$FIRMWARE_DIR" != "${BUILDER_DIR}/openipc" ]; then
    echo_c 31 "Refusing to use unexpected firmware directory: ${FIRMWARE_DIR}"
    exit 2
fi

prepare_firmware_checkout || exit 1
FIRMWARE_RESOLVED_REV=$(git -C "$FIRMWARE_DIR" rev-parse HEAD) || exit 1
echo_c 30 "Firmware revision: $FIRMWARE_RESOLVED_REV"

echo_c 33 "\nCopying extra packages"
copy_extra_packages || exit 1

echo_c 33 "\nCopying device files"
cp -afv "${BUILDER_DIR}/${ITEM}/." "$FIRMWARE_DIR/" || exit 1

echo_c 33 "\nRegistering device-local packages"
register_package_tree "${BUILDER_DIR}/${ITEM}/general/package" || exit 1

echo_c 33 "\nComposing device runtime variant"
compose_device_variant || exit 1

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
