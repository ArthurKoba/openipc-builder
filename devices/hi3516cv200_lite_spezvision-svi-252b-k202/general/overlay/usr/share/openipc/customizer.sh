#!/bin/sh
#
# Initial OpenIPC profile for SpezVision SVI-252B K202
# Board: BLK16CV-0323-38X38-V1.01
# SoC: HiSilicon Hi3516CV200
# Sensor: Sony IMX323, I2C/DC
# Flash: 8 MiB SPI NOR
#
# Majestic numbers legacy HiSilicon GPIOs as bank * 8 + bit:
# GPIO6_6 = 54, GPIO7_3 = 59, GPIO8_0 = 64.
#
# Stock Sofia's NID 0x11 / IR-cut profile 0x19c references GPIO8_0 and
# GPIO7_3 as the two pulsed IR-cut outputs. GPIO6_6 is only proven to be
# an input gate/state check in that branch, not an ambient-light sensor,
# so do not expose it as lightSensorPin.
#
# The stock IR LED path is still ambiguous between GPIO8_1 (65) and
# GPIO0_2 (2), so backlightPin intentionally remains unset.
#

fw_setenv upgrade 'https://github.com/OpenIPC/builder/releases/download/latest/hi3516cv200_lite_spezvision-svi-252b-k202-nor.tgz'
fw_setenv sensor imx323

cli -s .isp.sensorConfig /etc/sensors/imx323_i2c_dc_1080p.ini
cli -s .nightMode.lightMonitor true
cli -s .nightMode.irCutPin1 64
cli -s .nightMode.irCutPin2 59
cli -s .video0.codec h264
cli -s .video0.fps 25

exit 0
