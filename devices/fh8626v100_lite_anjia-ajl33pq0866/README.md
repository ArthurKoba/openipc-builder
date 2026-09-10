# FH8626V100 ANJIA AJL33PQ0866 device profile

This named OpenIPC Builder profile contains hardware choices that are not
valid for every FH8626V100 board.

- The generic `fh8626v100_lite` firmware definition supplies the SoC kernel,
  FH GMAC support, common networking and WPA userspace. It does not select a
  Wi-Fi chipset or the ANJIA SD/MMC wiring.
- This profile selects the external RTL8188FU module, the WEXT WPA backend,
  the AJL33PQ0866 kernel fragment and the board rootfs overlay.
- The customizer sets `wlandev=rtl8188fu-generic` only when `8188fu.ko` exists.
  SSID and passphrase remain runtime configuration; without them Wi-Fi stays
  inactive while Ethernet DHCP still runs.
- DHCP failure uses U-Boot `ipaddr`, or `192.168.1.10` when it is absent.
  Historical development values `.203` and `.204` are migration inputs, not
  defaults for new devices.
- The microSD slot, bidirectional audio, I2C and the muxed SADC ambient-light
  path are hardware-proven. Dedicated Ethernet stress and long combined soak
  tests remain deferred release-hardening work.
- Native `FH_DMAC`/`FH_DW_I2S` support remains available for other FH8626V100
  designs, but is intentionally disabled in this profile: the stock-compatible
  RTX path owns audio and its DMA interface. Microphone capture and speaker
  playback are hardware-proven with `FH_AXI_DMAC` enabled.
- USB VBUS is always powered on this board and has no controllable power-enable
  GPIO; the kernel treats that optional GPIO as absent without a boot warning.
- The generic FH8626V100 RTC support is retained, but this board profile leaves
  its platform device disabled. Suitable clock/backup hardware was not available
  for complete functional validation; RTC must be retested before enabling it.
  FH8626 TSENSOR is not a separate direct MMIO provider: measurement trigger and
  result retrieval use the same non-responsive RTC core command channel. Native
  and exact stock kernels both timed out on that channel, so this profile also
  explicitly disables `FH_TSENSOR`, `USE_TSENSOR`, and its optional eFuse-offset
  path. Divinus must report temperature as unavailable rather than inventing a
  value. A working RTC/TSENSOR command path must first be demonstrated by a
  bounded TFTP test before any of these choices can change.

This is the device-level selection exposed by Builder. Do not move its Wi-Fi
driver or board fragment back into the generic SoC defconfig.

## Divinus ownership

The public Divinus tree carries only the generic FH8626V100 platform/HAL
support. This profile pins that one-commit Divinus port and applies
`general/package/divinus/0001-anjia-ajl33pq0866-camera-features.patch`.
That device patch owns the dual-lens switch, PTZ/servo control, saved PTZ
state, ANJIA illumination and recording behavior, runtime diagnostics and
other camera-specific Divinus controls. Do not move these features into the
generic firmware package or the upstream Divinus platform commit.

## Removable storage and Divinus

The profile enables the FH one-bit MMC controller through its board kernel
fragment. Card presence is deliberately a runtime concern: the common OpenIPC
`mdev` rule mounts a discovered first partition at `/mnt/mmcblk0p1`; images do
not change according to whether a card happened to be inserted at build time.

This device overlay owns the corresponding policy:

- `S39fh8626-storage` and `automount-hook` create
  `/mnt/mmcblk0p1/recordings` idempotently and stop Divinus recording before an
  orderly unmount.
- `/etc/divinus.yaml` points the recorder at that directory, keeps automatic
  continuous recording disabled, and uses five-minute segments. Recording is
  started explicitly through the Divinus API or WebUI.
- Divinus-generated filenames use `recording_YYYYMMDD_HHMMSS.mp4`, which is
  valid on FAT filesystems. The recorder checks write failures and closes a
  segment only at an MP4-fragment boundary.
- `fsck.fat` is included for manual/offline recovery of an unclean card. The
  boot path never performs an unsolicited repair of user data.

The supported compact baseline is a partition formatted as FAT16/FAT32. The
kernel and rootfs do not require a card in order to boot, stream, or expose
diagnostics.
