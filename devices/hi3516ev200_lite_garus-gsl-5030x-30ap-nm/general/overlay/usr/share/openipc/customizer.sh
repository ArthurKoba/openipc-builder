#!/bin/sh
# GARUS GSL-5030X-30AP-NM, PCB BLK16EV2-4339P-38X38.
# Hi3516EV200, 64 MiB RAM, 8 MiB SPI NOR.
# First-boot defaults only; muxes.sh restores GPIO15 on EVERY boot.

# Keep the working 1080p SC2315E-family driver. Stock "3M" settings are
# not proof of a validated native 3MP mode; that port remains separate work.
fw_setenv sensor sc2315e

# The target camera does not use audio capture or playback. Keep shared SDK
# modules/libraries: disabling the stream does not make their removal safe.
cli -s .audio.enabled false
cli -s .audio.outputEnabled false

# GPIO15 is the external IR board's digital light-status INPUT (0/3.3 V).
# The board switches its IR LEDs autonomously. No GPIO16, lamp PWM, white
# light or audio-power GPIO is driven by this profile.
cli -s .nightMode.lightMonitor true
cli -s .nightMode.lightSensorPin 15
cli -s .nightMode.lightSensorInvert false
cli -s .nightMode.irCutEnabled true
cli -s .nightMode.irCutPin1 8
cli -s .nightMode.irCutPin2 9
cli -s .nightMode.colorToGray true
cli -s .nightMode.backlightEnabled false

# Preserve the existing inversion and coil order. GPIO15 transitions and
# bidirectional IR-cut pulses were tested individually; confirm the complete
# light/dark -> image/filter sequence after a cold boot of this profile.
# Do not set an upgrade URL until its matching release asset is published.

exit 0
