#!/bin/sh
#
# OpenIPC profile for XVI ISI-2010C
# SoC: Ingenic T31N
# Sensor: GalaxyCore GC2053
# RAM: 64 MiB
# Flash: 8 MiB SPI NOR
#
# Hardware-proven day/night contract:
# - PA16 / GPIO16 is the digital daylight-state input;
# - PB26 / GPIO58 and PB25 / GPIO57 drive the bistable IR-cut filter.
#
# The IR illuminator is controlled by the camera's separate light-sensor
# circuitry. No Majestic backlightPin is assigned.
#
# The board has no populated microphone, speaker amplifier, Wi-Fi or removable
# storage. T31 audio support is deliberately kept in the image so microphone
# and speaker hardware can be added later.
#
# No transitionDelayMs override is needed: both transition directions were
# clean on this hardware with Majestic's default timing.

fw_setenv upgrade 'https://github.com/OpenIPC/builder/releases/download/latest/t31_lite_xvi-isi-2010c-nor.tgz'
fw_setenv sensor gc2053

cli -s .nightMode.lightMonitor true
cli -s .nightMode.lightSensorPin 16
cli -s .nightMode.irCutPin1 58
cli -s .nightMode.irCutPin2 57
cli -s .video0.codec h264

exit 0
