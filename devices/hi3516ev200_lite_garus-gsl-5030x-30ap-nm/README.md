# GARUS GSL-5030X-30AP-NM — BLK16EV2-4339P-38X38

Target: `hi3516ev200_lite_garus-gsl-5030x-30ap-nm`.
Hi3516EV200, 64 MiB RAM, 8 MiB SPI NOR, wired Ethernet, fixed-focus lens.
**Source draft in the owner's fork. No compiled image or hardware acceptance of
this revision. Not an upstream submission or an installation-ready release.**

## Target and evidence

The supported target is the working **SC2315E-family 1920x1080 linear path**:
`libsns_sc2315e.so` and `sc2315e_i2c_1080p.ini`. The individual camera's earlier
OpenIPC log showed H.264 1920x1080 at 20 fps and 4096 kbit/s. These conservative
first-boot settings are now explicit; only the main stream is enabled by default.
JPEG snapshots and ordinary WebUI/RTSP/ONVIF functionality remain available.

The April stock dump and December recovery analysis found 1920x1080 input geometry
in the SC2315E path. Stock `CaptureSizes.3M=[2304,1296,1296]` and `DstFpsMax.3M=20`
are output configuration evidence, not proof of native 3MP or a measured stock
stream. The physical die name and the executed scaling path were not established.
Native 3MP, HDR, a sensor replacement and further sensor reverse engineering are
**outside this draft**, not unfinished requirements for this profile. Do not select
SC4236/SC4239 or add an upscale just to reproduce the advertised pixel count.

| Function | Board setting | Evidence / limit |
| --- | --- | --- |
| Light status | GPIO15 / GPIO1_7, input | Light/dark transitions observed after GPIO mux selection; external digital 0/3.3 V |
| IR-cut | GPIO8 / GPIO1_0 and GPIO9 / GPIO1_1 | Individual 200 ms pulses moved the filter both ways; day/night switching is hardware-accepted with `transitionDelayMs=150` |
| IR illumination | Autonomous external light board | Its own detector switches LEDs; no CPU lamp output configured |
| Audio | 3-pin header: common ground, microphone input, speaker output | Hardware loopback confirmed capture and playback; signal quality was not characterized. Support is retained and this profile does not force the runtime audio state |
| White lamp, PTZ, AF, Wi-Fi, USB, SD | Not supported by this target | No speculative GPIOs, peripherals or drive sequences |

The stock product data identified IRStatusGpio `[1,7]` and IRCutGpios `[1,0]` /
`[1,1]`; individual hardware tests confirmed those signals. GPIO16, audio-power
GPIO52 and tentative Ethernet LED assignments are not driven. Do not infer pins
from optional fields in generic XM configuration.

## What is reduced, and what must remain

The defconfig disables `MAJESTIC_AF`, `MOTORS`, `WIREGUARD_LINUX_COMPAT`,
`WIREGUARD_TOOLS` and `VTUND_OPENIPC`. The board kernel fragment disables the
wireless stack, USB host/gadget and its HiSilicon USB PHY, MMC/FAT, NAND/UBI/YAFFS
and TUN. It composes with the shared EV200 kernel config; no duplicated generic
config, kernel source patch or shared SDK loader override is introduced.

The literal exclusion list has 65 entries at the reviewed firmware revision:
33 unrelated sensor libraries, 28 unrelated capture presets, two unused IQ files,
the CamHi motor module and the manual `ircut_demo`. The selected sensor and preset
remain. **Keep `iq/default.ini` AND `iq/imx307.ini`: the former is a symlink to the
latter.** Its Sony name is not evidence that it is unused on this camera.

Keep shared MPP libraries and `open_*` modules: the EV200 loader still calls
`insert_audio` unconditionally. Majestic's package explicitly depends on Opus,
Ogg, libevent, mbedTLS and json-c. The three-pin audio header is hardware-proven,
so these paths are functional capability rather than speculative dead weight.
The profile deliberately does not write `.audio.enabled` or
`.audio.outputEnabled`: audio remains available for users who need it without
making it part of this camera's default workload. GPIO52 remains unconfigured;
the loopback test does not establish that optional stock assignment as required.

SSH, DHCP, IPv4/IPv6, NFS recovery support, curl, environment tools, native
`ipcinfo`, normal update tools, fonts, WebUI and the video/ISP stack remain.
CPIO/SquashFS build selections and compiler/ABI flags are unchanged. No password,
MAC, IP, memory split, flash map or generic upgrade URL is baked into the profile.
The upstream owner-claim/authentication and Majestic EULA flow is preserved; it is
not pre-accepted or bypassed by this customizer.

## Boot ownership

`customizer.sh` sets first-boot video and night-mode defaults and intentionally
leaves audio state untouched. It fails on a failed command and does not write MMIO. Existing user settings outside its small
explicit set are left alone. `muxes.sh` is unchanged from the previous profile;
S30customizer invokes it on **every boot**, outside the `/etc/custom.ok` guard,
before S70vendor and S95majestic. It does not fetch a remote `ipctool` plugin.

| Register | Mask / requested bits | Purpose |
| --- | --- | --- |
| `0x120B1400` | `0x80` / `0` | GPIO15 input; preserve other directions |
| `0x120C001C` | `0x0f` / `2` | GPIO1_7 function; preserve electrical settings |

Direction is verified before selecting the GPIO pad. Both changes use read-modify-
write and readback, with SoC and malformed-read guards. Repeated execution is
idempotent. No GPIO data, flash, lamp, PWM or coil-drive write is made by this hook.
The reviewed EV200/demo/MIPI `open_sys_config` path does not overwrite these two
settings. GPIO8/9 were already GPIO-muxed on the tested camera. Majestic alone owns
their short pulses; do not replace that with permanent output levels.

`lightSensorInvert=false`, coil order 8/9 and the resulting day/night image state are
now hardware-accepted on the tested camera. `transitionDelayMs=150` is retained as
the tested intra-transition pause between the picture-mode change and IR-cut movement. The published pinmux API is not another pad
owner in this draft: do not configure an independent persistent override for
GPIO15 while this every-boot board hook owns it.

S30customizer itself still stamps `custom.ok` after invoking a failed customizer
and does not stop subsequent services on a mux error. Our local nonzero returns
do not repair that shared lifecycle limitation. Inspect the boot log and settings;
never treat the existence of `custom.ok` as proof the defaults succeeded.

## Reviewed build inputs

Review date: 2026-09-21. The device branch is synchronized with builder
`master` through `9753e10c09fc072a76bc39bcb5cb7ce1ca050bf8`; the profile changes
remain isolated on `device/garus-gsl-5030x-30ap-nm`.

Firmware authority: **OpenIPC/firmware**
`6f03cc45a1165ad45ab60cb81984b674c14837b0`, not the stale master of the owner's
firmware mirror. Buildroot is `2024.02.10`; opensdk selects OpenIPC/openhisilicon
`b922e1999dceb43c1a949d8d76a5110176d8c57a`. The reviewed upstream sources are:

- Firmware `Makefile`, `general/openipc.fragment`, `general/scripts/rootfs_script.sh`:
  concatenate board defaults with the common fragment; apply exact-path exclusions
  before late overlays; strip shell comments; enforce NOR image size limits.
- `general/package/hisilicon-osdrv-hi3516ev200/hisilicon-osdrv-hi3516ev200.mk` and
  `files/script/load_hisilicon`: sensor/IQ installs, default IQ symlink, MPP/audio
  load contract; `hisilicon-opensdk.mk`: source sensor inventory and SDK revision.
- `general/package/majestic/majestic.mk`: runtime dependencies and moving tarball.
- `general/overlay/etc/init.d/S30customizer`: first-boot versus every-boot hooks.
- Openhisilicon `kernel/sys_config/sys_config.c` at the SDK revision above:
  EV200/demo/MIPI mux path; `kernel/Kbuild`: the EV200 set has no UVC module.
- OpenIPC/wiki `en/majestic-config.md`, inspected on the review date: the literal
  video, sensor-config, audio and nightMode keys. Validate against the actual
  Majestic binary's schema too; yaml-cli alone does not validate key names.

Builder overlays `devices/<target>/*` onto a fresh upstream firmware checkout and
runs `make BOARD=<target>`. `OPENIPC_FW_REV` selects that firmware revision.
**This is not a complete reproducibility lock**: builder.sh runs `git pull` on
itself, and Majestic/WebUI and some other inputs use moving download names.
Capture actual Builder/Firmware revisions, resolved configs, package versions and
image hashes with the first successful build; do not overwrite the known-good
archive. Use a dedicated Builder checkout because its `openipc/` is recreated.

## Validation and later build

Run in the root of that dedicated checkout, on the device branch:

```sh
python3 devices/hi3516ev200_lite_garus-gsl-5030x-30ap-nm/test_boot_defaults.py
python3 .github/scripts/ci-matrix.py --self-test
```

When a full build is explicitly requested, the existing build entry point is:

```sh
OPENIPC_FW_REV=6f03cc45a1165ad45ab60cb81984b674c14837b0 ./builder.sh hi3516ev200_lite_garus-gsl-5030x-30ap-nm
```

Afterward the same host test can inspect the real source and output:

```sh
python3 devices/hi3516ev200_lite_garus-gsl-5030x-30ap-nm/test_boot_defaults.py --firmware openipc --stripper openipc/general/scripts/strip-shell-comments.awk --kernel-config openipc/output/build/linux-custom/.config --rootfs openipc/output/target
```

The host test needs Python 3.8+ and BusyBox, never root or camera access. The
optional output arguments require a successful build and are not fake fixtures.
Source/mock validation for this draft: **32 host cases passed** (source plus exact
upstream comment-stripped scripts), together with static package/fragment/pruning
checks. The mock PATH contains only mock tools. The untouched mux baseline and
the test's upstream stripper were verified against their Git blob IDs.

Full-tree CI selector self-test, resolved Kconfig, SDK/kernel compilation, final
rootfs/ELF dependency audit, independent review and hardware tests were **not run**.
The available validation container could not fetch the full Git checkout; MCP
source reads remained available. Do not promote the host checks to build success.

Expected local archive: `archive/<target>/<timestamp>/`, with
`openipc.hi3516ev200-nor-lite.tgz`, `uImage.hi3516ev200`,
`rootfs.squashfs.hi3516ev200`, rootfs tar and size report when generated.
That TGZ is kernel + rootfs, **not a full 8 MiB flash dump or a new U-Boot**.
The wrapper is responsible for any later device-specific release naming.

| Existing NOR area | Start | Capacity |
| --- | --- | --- |
| U-Boot | `0x000000` | 256 KiB |
| Environment | `0x040000` | 64 KiB |
| Kernel | `0x050000` | 2048 KiB |
| SquashFS rootfs | `0x250000` | 5120 KiB |
| Writable overlay | `0x750000` | 704 KiB |

Before installation, require kernel <= 2097152 bytes and rootfs <= 5242880 bytes,
using exact byte counts, not rounded KiB. Check a real resolved kernel config,
only the selected sensor/preset, valid IQ symlink, full shared-library resolution,
claim/setup assets and both boot hooks in the built image. Confirm the live flash
map and a restorable backup independently; a damaged/mixed stock research dump
is not such a backup. No erase/program/reset commands are part of this draft.

Hardware observations now confirmed on the locally built 202609210723 image:
1080p picture, microphone/speaker audio path and automatic day/night + IR-cut
switching all work on the target camera. The tested runtime also uses
`nightMode.transitionDelayMs=150`. A rebuild is still required after folding that
value into this source revision, and a second cold-boot/settings-retention pass is
still required before treating the resulting bytes as fully accepted. An unclaimed installation
may require the owner to complete password/EULA setup before normal streaming.

An upgrade preserving `custom.ok` will NOT apply these first-boot defaults. Back up
`/etc/majestic.yaml` and the environment, review the small customizer delta and
apply it once through the normal service lifecycle during acceptance. Do not wipe
rootfs_data, delete all user settings or rerun configuration on every boot. The
upgrade URL stays unset until a matching, accepted board artifact is published.
