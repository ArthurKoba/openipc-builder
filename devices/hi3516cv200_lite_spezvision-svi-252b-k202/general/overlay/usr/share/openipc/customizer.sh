#!/bin/sh
#
# Initial OpenIPC profile for SpezVision SVI-252B K202
# Board: BLK16CV-0323-38X38-V1.01
# SoC: HiSilicon Hi3516CV200
# Sensor: Sony IMX323, I2C/DC
# Flash: 8 MiB SPI NOR
#
# IR-cut, IR LED and light-sensor GPIOs are intentionally left unset until
# they are measured on this exact board. Do not reuse GPIOs from other CV200
# devices here.
#

fw_setenv upgrade 'https://github.com/OpenIPC/builder/releases/download/latest/hi3516cv200_lite_spezvision-svi-252b-k202-nor.tgz'
fw_setenv sensor imx323

exit 0
