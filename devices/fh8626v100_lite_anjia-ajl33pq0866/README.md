# FH8626V100 ANJIA AJL33PQ0866 device profile

This directory is the named-camera assembly layer for ANJIA AJL33PQ0866.
Generic FH8626V100 implementation is supplied by Firmware/Linux; runtime
implementation is supplied by Divinus or the Majestic compatibility package.

## Pre-deploy repository set

Current audited staging directions:

- Builder: `ArthurKoba/openipc-builder/work/fh8626v100-anjia` (record the exact HEAD from build provenance; this README is part of that branch);
- Firmware core: `ArthurKoba/openipc-firmware/work/fh8626v100@80169887`;
- Firmware Divinus: `ArthurKoba/openipc-firmware/work/fh8626v100-divinus@255b8c8d`;
- Firmware Majestic: `ArthurKoba/openipc-firmware/work/fh8626v100-majestic@aabf18a6`;
- Linux: `ArthurKoba/openipc-linux/work/fh8626v100@357c2d13`;
- Divinus: `ArthurKoba/openipc-divinus/work/fh8626v100` (record the exact source HEAD used by the matching Divinus build);
- production U-Boot direction: `ArthurKoba/u-boot-fullhan/fh8626v100-mainline@7ac0aa7e`.

The exact Linux tarball remains pinned by commit in the Firmware defconfig.

## Repository boundary

Builder owns only board policy and composition:

- board-only kernel fragment: one-bit SD0 plus RTC/TSENSOR board disable;
- RTL8188FU selection;
- persistent device/update identity;
- GPIO and GPIO23/SADC1 shared-pad policy;
- source-built PTZ and low-level WIDE/TELE selector;
- physical illumination/IR-cut and speaker-mute helpers;
- storage policy;
- runtime selection and runtime-specific board configuration.

Builder does **not** contain generic FH8626 platform/media implementation,
proprietary media kernel binaries, Divinus source, or the Majestic
compatibility implementation.

The still-proprietary FH8626 kernel media ABI is owned by Firmware package
`fullhan-media-fh8626v100`. Active source branches contain only package
metadata, loader scripts and SHA-256 manifests. The eight hardware-proven
media modules plus `rtthread_arc.bin` are downloaded from immutable archive
commit `f4bf49da6ef355c9e733e00d774efe403513b1d4`; they are not copied into
the current Builder/Firmware source trees.

## Runtime targets

Targets are composed from:

1. Firmware base `br-ext-chip-fullhan/configs/fh8626v100_lite_defconfig`;
2. Builder `configs/variants/base.config`;
3. one runtime fragment.

Available targets:

- `fh8626v100_lite_anjia-ajl33pq0866_divinus`;
- `fh8626v100_lite_anjia-ajl33pq0866_majestic`;
- `fh8626v100_lite_anjia-ajl33pq0866_diag`.

Each target has a sibling `.firmware` metadata file. `builder.sh` uses that
metadata automatically, so the normal staging commands are simply:

```sh
./builder.sh fh8626v100_lite_anjia-ajl33pq0866_divinus
./builder.sh fh8626v100_lite_anjia-ajl33pq0866_majestic
./builder.sh fh8626v100_lite_anjia-ajl33pq0866_diag
```

`OPENIPC_FW_REPO` / `OPENIPC_FW_REV` remain explicit overrides for bisect
or debugging; they are not required for these three named variants.

The composed config and source provenance are archived with a successful build. Builder now also writes `runtime-sha256.txt`, records `majestic_sha256` in `build-info.txt`, and emits archive-level `SHA256SUMS`, so the moving Majestic donor and the pinned FH8626 runtime bytes are attributable to the exact image. FH8626 archive creation is strict: Majestic requires all 10 provenance entries (Majestic plus the nine media/ARC payloads), while Divinus/diag require all nine shared media/ARC payloads.

## Shared proprietary media kernel runtime

All three Firmware directions select
`BR2_PACKAGE_FULLHAN_MEDIA_FH8626V100=y`.

The package installs:

- `vmm.ko`;
- `xbus_rpc.ko`;
- `media_process.ko`;
- `isp.ko`;
- `enc.ko`;
- `jpeg.ko`;
- `bgm.ko`;
- `gpio_wave.ko`;
- `rtthread_arc.bin`.

OpenIPC `S70vendor` calls the installed `load_fullhan -i`, which delegates
to the pinned FH8626 loader. The hardware-proven load order is VMM, ARC/XBUS,
media_process, ISP, encoder, JPEG, BGM and gpio_wave. The loader fails when
`/dev/vmm_userdev`, `/dev/media_process`, `/dev/isp`, `/dev/pae` or
`/dev/jpeg` is missing.

Sensor/MIPI userspace is not supplied by this binary package. Majestic and
Divinus own their current source/runtime paths independently.

## Majestic target

The Majestic variant selects `BR2_PACKAGE_MAJESTIC_FH8852V200_COMPAT` plus
shared board packages. The compatibility package itself also selects
`BR2_PACKAGE_FULLHAN_MEDIA_FH8626V100`, so the target cannot accidentally
lose the required FH8626 kernel/ARC media runtime. It does not install Divinus
configuration.

Default boot remains the proven media-off Majestic control plane.

For staged hardware acceptance the image includes
`majestic-fh8626-full-run`, which runs native VENC with permissive stubs
disabled and enables together:

- H.264 main 1280x720@25;
- H.264 sub 640x360@25;
- JPEG 640x384;
- OSD;
- motion;
- 8 kHz audio capture/output;
- RTSP;
- recovered ANJIA day/night wiring.

Majestic HTTP/WebUI remains native. There is no HTTP proxy or JavaScript patch.

The FH8626 kernel/ARC media payload is immutable and SHA-256 pinned. The
FH8852V200 Majestic executable is still downloaded from the upstream moving
`majestic.fh8852v200.lite.master.tar.bz2` object. The first controlled build
must therefore archive the exact installed Majestic SHA-256. ABI guards make
an incompatible API expansion fail the build, but the moving donor remains a
product-reproducibility blocker until an immutable donor or official FH8626
Majestic build is available.

## Divinus target

The Divinus variant selects Divinus plus the device-local
`anjia-ajl33pq0866-divinus-config` package.

The current Builder acceptance YAML deliberately starts with the proven
1280x720@25 H.264 path. Audio and JPEG/MJPEG remain disabled in that YAML even
though the implementation has advanced further; they are later target gates,
not missing Builder ownership.

## Diagnostic target

The diagnostic variant selects no streamer. It keeps board support plus the
shared FH8626 media runtime for low-level diagnostics. It has no persistent
update target, so a diagnostic NOR/TFTP session does not redirect normal
self-update policy.

## U-Boot and NOR layout

Builder does not build or flash the FH8626 U-Boot port.

Production U-Boot is a separate artifact from
`u-boot-fullhan/fh8626v100-mainline`. Its native OpenIPC 8 MiB layout is:

- boot: 256 KiB;
- env: 64 KiB;
- kernel: 2048 KiB;
- rootfs: 5120 KiB;
- remaining NOR: rootfs_data.

The Builder/Firmware image uses the same kernel/rootfs limits. A first Majestic
userspace/media test may use an already-working bootloader, but migration to
the new native U-Boot artifact is a separate cold-boot/recovery hardware gate.

`/etc/fw_env.config` points at the 64 KiB env partition:
`/dev/mtd1 0x0000 0x10000 0x10000`.

## Board hardware contracts

### PTZ and lens

PTZ uses the source-built relative `/dev/fh_pwm` backend and exposes:

`gpio-motors PAN_STEPS TILT_STEPS DELAY_MS`

No boot calibration or persistent absolute position is claimed.

The WIDE/TELE helper owns only GPIO4/GPIO14. A media runtime owns the complete
logical switch around that physical selector.

Cold TELE visibility has the separate GPIO5 bootstrap requirement: LOW before
media-module initialization and HIGH before sensor/media startup.

### Illumination / IR-cut

Hardware contract:

- IR-cut DAY coil: GPIO18;
- IR-cut NIGHT coil: GPIO60;
- pulse: 190 ms;
- IR LED: GPIO25 active high;
- white LED: GPIO23 active high;
- light input: SADC1 on the GPIO23 shared pad.

Board init establishes only safe outputs. Runtime scene policy belongs to the
selected streamer.

### Audio amplifier

GPIO24 is the active-high physical speaker-amplifier mute. Board boot/shutdown
keeps it muted. Media runtimes must unmute only after AO is configured and mute
before AO teardown. Majestic uses the board-neutral lifecycle hook for this.

## Build and deployment gates

The source/composition audit is not a successful build.

Before flashing a persistent image:

1. build the exact Majestic composed target;
2. record the resolved Builder/Firmware/Linux refs;
3. verify the external media payload SHA-256 checks pass and retain the generated runtime/archive checksum manifests;
4. require `uImage <= 2048 KiB`;
5. require `rootfs.squashfs <= 5120 KiB` and record headroom; Builder now enforces both FH8626 limits as hard post-build gates before archiving;
6. inspect the final target for all nine media runtime artifacts and
   `/usr/bin/load_fullhan`;
7. boot non-destructively first where practical;
8. prove media devices after `S70vendor`;
9. run Majestic ABI probe and require selected-library loading, Fullhan symbols, media devices and the complete FH8852-shaped sensor callback table to pass; then run `majestic-fh8626-full-run`;
10. only after media acceptance proceed to persistent/update/U-Boot migration.

All three named targets remain CI `NOT_BUILT` while these fork-local staging
directions are not part of normal upstream CI.
