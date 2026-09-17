#!/bin/sh
set -eu

TARGET_DIR="$1"

# There is no calibrated IMX323 IQ profile in the CV200 package.  Never let
# generic AR0130/OV2710 tuning become Majestic's default for this camera.
rm -rf "${TARGET_DIR}/etc/sensors/iq"
mkdir -p "${TARGET_DIR}/etc/sensors/iq"

exit 0
