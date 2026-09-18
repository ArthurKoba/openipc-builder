#!/bin/sh
#
# ANJIA AJL33PQ0866 board profile.
# Timing-sensitive GPIO5 dual-sensor sequencing is consumed by the media
# runtime around its actual module/sensor startup rather than hidden here.

# TFTP/initramfs validation must not mutate persistent U-Boot state.
grep -q ' / squashfs ' /proc/mounts || exit 0

TARGET_FILE=/etc/openipc/builder-target
TARGET=$(cat "$TARGET_FILE" 2>/dev/null || true)

case "$TARGET" in
    fh8626v100_lite_anjia-ajl33pq0866|fh8626v100_lite_anjia-ajl33pq0866_majestic)
        ;;
    *)
        echo "Invalid or missing Builder target identity: $TARGET" >&2
        exit 1
        ;;
esac

env_value()
{
    fw_printenv -n "$1" 2>/dev/null || true
}

set_env()
{
    key="$1"
    value="$2"
    [ "$(env_value "$key")" = "$value" ] || fw_setenv "$key" "$value"
}

clear_env()
{
    key="$1"
    [ -z "$(env_value "$key")" ] || fw_setenv "$key"
}

# Keep the runtime direction stable across self-update.
set_env upgrade "https://github.com/OpenIPC/builder/releases/download/latest/${TARGET}-nor.tgz"

# Preserve serial#, cid, uuid and ethaddr. Only the Wi-Fi profile is device
# policy, and avoid rewriting the environment when it already matches.
if find /lib/modules -name 8188fu.ko -type f 2>/dev/null | grep -q .; then
    set_env wlandev rtl8188fu-generic
else
    clear_env wlandev
fi

exit 0
