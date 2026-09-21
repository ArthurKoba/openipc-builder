#!/bin/sh
# GARUS GSL-5030X-30AP-NM, PCB BLK16EV2-4339P-38X38.
# First-boot defaults only. muxes.sh restores the light-sensor pad every boot.
set -eu

# Keep the tested SC2315E-family 1080p path; do not request stock "3M" upscale.
# This software name does not uniquely identify the physical sensor die.
fw_setenv sensor sc2315e
cli -s .isp.sensorConfig /etc/sensors/sc2315e_i2c_1080p.ini
cli -s .video0.enabled true
cli -s .video0.codec h264
cli -s .video0.size 1920x1080
cli -s .video0.fps 20
cli -s .video0.bitrate 4096
cli -s .video1.enabled false

# The three-pin audio header is hardware-proven: common ground, microphone
# input and speaker output all pass a loopback signal. Keep the upstream audio
# stack available, but do not force audio enabled or disabled for this profile.
# Runtime audio state belongs to the owner/application.

# GPIO15 is a digital 0/3.3 V status INPUT from the autonomous IR board.
# Majestic owns only IR-cut pulses and colour/mono switching, not the lamps.
cli -s .nightMode.lightMonitor true
cli -s .nightMode.lightSensorPin 15
cli -s .nightMode.lightSensorInvert false
cli -s .nightMode.irCutEnabled true
cli -s .nightMode.irCutPin1 8
cli -s .nightMode.irCutPin2 9
cli -s .nightMode.colorToGray true
cli -s .nightMode.backlightEnabled false

# Preserve the existing polarity/pin order until full day/night acceptance.
# Do not set MAC, IP, passwords, EULA acceptance, memory, flash layout or a
# generic upgrade URL. Only a published matching board image may replace this.
exit 0
