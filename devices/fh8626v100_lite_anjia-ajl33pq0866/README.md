# FH8626V100 ANJIA AJL33PQ0866 device profile

This directory is the named-camera layer for ANJIA AJL33PQ0866. It is intentionally
thin: generic FH8626V100 implementation is supplied by Firmware/Linux and streamer
implementation is supplied by Divinus or Majestic.

## Repository boundary

Builder owns only AJL33PQ0866 policy and assembly. Its executable board
support packages live under this device tree, so unrelated Builder targets do
not even register them:

- the board-only kernel fragment, including one-bit SD0 and this board's
  RTC/TSENSOR disable policy;
- RTL8188FU selection and persistent first-boot device settings;
- the physical GPIO map and the GPIO23/SADC1 shared-pad policy;
- illumination/IR-cut low-level helpers and safe output handling;
- source-built AJL33PQ0866 PTZ and WIDE/TELE low-level backends;
- removable-storage shutdown policy;
- runtime selection and runtime-specific named-device configuration.

Builder does not contain generic FH8626 kernel/platform/media code, Linux
patches, factory Fullhan .ko/.so/.bin payloads, Divinus implementation source or
the Majestic compatibility package.

Current cross-repository staging inputs are:

- Firmware core: `ArthurKoba/openipc-firmware/work/fh8626v100@eabd1ccd4684af6997771269c4655f7e4435bcec`;
- Linux: `ArthurKoba/openipc-linux/work/fh8626v100@357c2d13e7589db0dbe2bbf89c2ec38b1c036e6e`;
- Divinus implementation: `ArthurKoba/openipc-divinus/work/fh8626v100@f986a82f309b8794a5aae251589c6a5d07690c53`.

The exact Linux tarball in the defconfig is a temporary engineering pin until
the curated Linux series has an OpenIPC-owned ref.

## Runtime targets

The main target is:

`fh8626v100_lite_anjia-ajl33pq0866`

The board-support package embeds that exact target name in
`/etc/openipc/builder-target`. The idempotent `S32anjia-env` service uses it
to preserve runtime direction across self-update and only writes U-Boot
environment values when they actually differ. The first-boot customizer merely
invokes the same service, so correctness does not depend on one-shot
`/etc/custom.ok` behavior.

It selects Divinus plus the small
`anjia-ajl33pq0866-divinus-config` package. The Divinus YAML is not in the
shared device overlay, so it does not leak into other runtime directions.
The current acceptance profile starts only the 1280x720@25 H.264 path. RTX
audio and JPEG/MJPEG stay disabled by default until their separate package and
target gates are exercised.

The Majestic direction is maintained on
`work/fh8626v100-anjia-majestic` as the separate named target
`fh8626v100_lite_anjia-ajl33pq0866_majestic`. Its implementation package stays
in Firmware; Builder only selects that Firmware direction and applies this same
board policy.

Both targets remain in CI `NOT_BUILT` while their required FH8626 Firmware
refs are fork-local.

## PTZ

Production PTZ is a stateless relative backend over the hardware-proven
`/dev/fh_pwm` channel map. It exposes the normal OpenIPC interface:

`gpio-motors PAN_STEPS TILT_STEPS DELAY_MS`

There is no automatic calibration, boot movement, saved absolute coordinate,
`home` or `goto` state. This hardware has no absolute position feedback, so a
coordinate saved across power loss is not authoritative physical position.

The earlier stock-style controller remains reference/evidence only at tag
`archive/fh8626v100-anjia-stock-ptz-controller-20260918`.

PTZ and lens switching are separate. `fh8626-lens` owns only the physical
GPIO4/GPIO14 selector and stock target-first ordering. A streamer/media owner
must coordinate VENC, orientation and exposure around a logical WIDE/TELE
switch.

## Dual-sensor bootstrap

TELE visibility after cold boot has a separate hardware prerequisite: GPIO5
must be LOW before the validated Fullhan media-module initialization sequence
and HIGH before sensor/media startup.

That transaction cannot be reproduced correctly by an unrelated early/late
Builder init script. Builder records the board contract; the selected media
runtime must place the two edges around its actual media initialization. GPIO5
is not toggled on ordinary WIDE/TELE switches.

## Illumination and IR-cut

Board wiring is:

- IR LED GPIO25, active high;
- white LED GPIO23, active high;
- IR-cut actuator GPIO18/GPIO60;
- light input SADC channel 1, sharing pad70 with white-light GPIO23.

`fh-anjia-ajl33pq0866-light` owns only these physical operations. AUTO
hysteresis, day/night/WLIGHT scene choice and ISP transitions belong to the
selected media runtime. `S68anjia-hardware` only establishes safe outputs at
boot/shutdown: LEDs off, pad70 returned to SADC and both IR-cut drive lines at
rest; it does not move the filter merely because the process starts or stops.

The current IR-cut active/rest values are retained from the already-staged
working helper. Their final polarity/actuator direction is an explicit hardware
regression gate; do not silently infer it from GPIO numbering.

## Storage and identity

The one-bit SD0 slot is selected with
`CONFIG_FH8626V100_SD0_1BIT=y`. Generic OpenIPC mdev owns hotplug mounting;
the device init script only creates the recording directory when a card is
already mounted and syncs/unmounts it on shutdown.

`fw_env.config` addresses the native OpenIPC 64 KiB environment partition as
`/dev/mtd1`. The customizer does not overwrite serial/cid/uuid/ethaddr. It
sets the board-qualified update URL and the RTL8188FU runtime profile only when
the module is actually present.

The full named-device defconfig still repeats architecture/toolchain/kernel
selection because Builder overlays complete Buildroot defconfigs. Those lines
select the shared Firmware/Linux implementation; they are not copies of generic
FH8626 source.

## Validation state

Source-level checks for the cleaned board-support code pass, including the PTZ
recorder tests and warning-clean host compilation. This is not hardware
acceptance.

Remaining owner gates are:

- build both named targets against their exact Firmware directions and record
  the resolved config plus kernel/rootfs sizes;
- cold-boot GPIO5 dual-sensor bootstrap and WIDE/TELE switching;
- relative pan/tilt direction, requested delay/speed, cancellation and safe
  output disable with no boot movement;
- IR/white LED, IR-cut DAY/NIGHT direction/polarity, SADC shared-pad restore and
  shutdown safe state;
- microSD hotplug/shutdown, RTL8188FU, reset-button path and persistent U-Boot
  settings;
- streamer-specific media/audio acceptance in the owning Divinus/Majestic path.
