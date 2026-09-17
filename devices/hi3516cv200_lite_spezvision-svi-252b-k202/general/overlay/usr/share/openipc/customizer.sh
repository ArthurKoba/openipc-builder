#!/bin/sh
#
# SpezVision SVI-252B K202
# Board: BLK16CV-0323-38X38-V1.01
# SoC: HiSilicon Hi3516CV200
# Sensor: Sony IMX323, I2C/DC
# Flash: 8 MiB SPI NOR
#
# IR-cut, IR LED, light-sensor and audio-specific settings stay unset until
# they are validated on this exact board.
#

fw_setenv upgrade 'https://github.com/OpenIPC/builder/releases/download/latest/hi3516cv200_lite_spezvision-svi-252b-k202-nor.tgz'

# CV200 ships both I2C/DC and SPI/DC IMX323 presets. This board uses I2C/DC,
# so select the board wiring explicitly instead of relying on sensor-name
# inference.
cli -s .isp.sensorConfig /etc/sensors/imx323_i2c_dc_1080p.ini

exit 0
