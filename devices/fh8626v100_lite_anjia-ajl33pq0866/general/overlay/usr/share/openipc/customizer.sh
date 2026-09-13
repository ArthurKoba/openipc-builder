#!/bin/sh
#
# ANJIA AJL33PQ0866 board profile.
# Hardware-specific media GPIO sequencing is provided by the board package,
# not by the generic FH8626V100 module loader.

# TFTP validation runs from initramfs. Do not mutate the persistent U-Boot
# environment until this profile is actually running from the NOR SquashFS.
# Per-device serial#, cid, uuid and ethaddr values are deliberately preserved;
# a shared firmware image must never replace device identity or MAC addresses.
grep -q ' / squashfs ' /proc/mounts || exit 0

# Use the board-qualified release rather than the generic FH8626 image because
# GPIO5 sequencing, dual GC1054 data and the RTL8188FU package are profile-owned.
fw_setenv upgrade 'https://github.com/OpenIPC/builder/releases/download/latest/fh8626v100_lite_anjia-ajl33pq0866-nor.tgz'
# Preserve ethaddr from each device instead of baking a development MAC into
# the image. This device defconfig selects RTL8188FU, but keep the runtime
# profile coupled to the package actually present in the composed image.
if find /lib/modules -name 8188fu.ko -type f 2>/dev/null | grep -q .; then
	fw_setenv wlandev rtl8188fu-generic
else
	fw_setenv wlandev
fi

exit 0
