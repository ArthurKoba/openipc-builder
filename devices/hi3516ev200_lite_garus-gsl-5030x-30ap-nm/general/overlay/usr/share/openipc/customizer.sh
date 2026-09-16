#!/bin/sh
#
# GARUS GSL-5030X-30AP-NM
# PCB: BLK16EV2-4339P-38X38
# SoC: Hi3516EV200, 64 MiB RAM, 8 MiB SPI NOR
#
# Sensor status:
# OpenIPC currently detects the SmartSens sensor through the sc2315e family
# driver and runs stable at 1920x1080. The stock firmware was configured for
# 2304x1296 ("3M") at 25 fps. The exact physical sensor identity / native 3MP
# register mode is still being reverse-engineered from the extracted stock
# firmware. Keep the known-working sc2315e fallback until that port is ready.
#
fw_setenv sensor sc2315e
#
# Day/night hardware, decoded from stock configuration and verified on hardware:
#   GPIO15 - photo/light sensor input
#   GPIO8  - IR-cut coil direction A
#   GPIO9  - IR-cut coil direction B
#
# The front IR LED board has its own photo sensor logic and switches the IR LEDs
# autonomously. Do NOT configure a Majestic backlightPin/IR LED GPIO here.
# Majestic only follows the light input to switch ISP colour/mono state and pulse
# the mechanical IR-cut filter.
#
cli -s .nightMode.lightMonitor true
cli -s .nightMode.lightSensorPin 15
cli -s .nightMode.lightSensorInvert false
cli -s .nightMode.irCutPin1 8
cli -s .nightMode.irCutPin2 9
cli -s .nightMode.colorToGray true
#
# Self-upgrade URL is intentionally not set while this device profile is WIP in
# a private development branch. Add it only when a matching release asset is
# published.
#

exit 0
