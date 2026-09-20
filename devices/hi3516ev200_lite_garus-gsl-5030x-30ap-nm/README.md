# GARUS GSL-5030X-30AP-NM — BLK16EV2-4339P-38X38

Target: `hi3516ev200_lite_garus-gsl-5030x-30ap-nm`.
Hi3516EV200, 64 MiB RAM, 8 MiB SPI NOR, wired Ethernet.
This is a development profile in the owner's fork, not an upstream-ready release.

## Scope and evidence

- Keep the working `sc2315e` driver and `sc2315e_i2c_1080p.ini`.
  Individual camera tests established 1080p video with this driver. Stock
  `Resolution="3M"`/25 fps settings and `CaptureSizes.3M=[2304,1296,1296]`
  are configuration evidence, not proof of native sensor output or its rate.
  Native 3MP remains separate reverse-engineering work.
- GPIO15 / GPIO1_7: external IR-board digital status input, 0/3.3 V.
  Light/dark transitions were observed with `ipctool gpio scan` after selecting
  GPIO mode. A sysfs input alone had read constant zero with the wrong pad mux.
- GPIO8 / GPIO1_0 and GPIO9 / GPIO1_1: IR-cut bridge controls. Individual
  200 ms pulses moved the filter in both directions. Leave pulse generation
  to Majestic; do not hold a coil on from this boot hook.
- The front IR board controls its LEDs autonomously with its own light detector.
  There is no white/warm lamp on this camera. Do not configure `backlightPin`,
  GPIO16 or lamp PWM, and do not copy those fields from the generic XM profile.
- Audio capture/playback are outside this camera's target use and are disabled.
  A reserved connector or audio fields in generic XM firmware do not establish
  populated, working audio hardware. GPIO52 is not driven or assumed safe.

The stock `IPC_85HF30T` product data identified IRStatusGpio `[1,7]` and
IRCutGpios `[1,0]`/`[1,1]`; the individual hardware tests confirmed these three
signals. Other stock GPIO assignments are not enabled merely because they exist.

## Boot responsibilities

`customizer.sh` supplies first-boot defaults: `sensor=sc2315e`, audio input/output
false, light monitoring on GPIO15, IR-cut on GPIO8/9, colour/mono switching,
and Majestic lamp control disabled. It does not write pinmux registers.

`muxes.sh` restores the GPIO15 input on **every boot**, even when
`/etc/custom.ok` exists. The native `S30customizer` calls it outside the one-time
customizer guard, before `S70vendor` and `S95majestic`. No extra init service,
remote ipctool download or per-boot environment/config rewrite is needed.

Only two registers can be changed, using read-modify-write and readback:

| Register | Mask / requested bits | Purpose |
| --- | --- | --- |
| `0x120B1400` | `0x80` / `0` | GPIO bank 1 direction: GPIO15 input, other pins preserved |
| `0x120C001C` | `0x0f` / `2` | GPIO1_7 pad function, electrical configuration preserved |

Input direction is verified **before** selecting the GPIO pad. Repeated execution
is idempotent; failed reads/writes or failed readback return nonzero. The hook
checks the SoC and never writes GPIO data, flash, IR LED control or audio power.
Note: the native S30 script reports the hook output but does not gate all later
services on its exit status; a reported mux error must not be treated as success.
GPIO8/9 already used the GPIO function in the observed camera boot. Their output
state and pulsing remain Majestic's responsibility.

Source contracts inspected for this change:

- [S30customizer](https://github.com/OpenIPC/firmware/blob/master/general/overlay/etc/init.d/S30customizer):
  every-boot hook (inspected blob `34655932dfcda42279f724016320007d5bacf85a`).
- [ipctool reginfo.c](https://github.com/OpenIPC/ipctool/blob/master/src/reginfo.c):
  `EV200_iocfg_reg50` maps `0x120C001C` selector 2 to `GPIO1_7`; HiSilicon
  pad function changes use a low-nibble mask.
- [open_sys_config](https://github.com/OpenIPC/openhisilicon/blob/5ccb5e9a276d0d4514551fbe69c7a423de2d09d2/kernel/sys_config/sys_config.c):
  the selected EV200/demo/MIPI path does not overwrite this pad after S30.
  Recheck this ordering if the vendor package changes.
- [Majestic settings](https://github.com/OpenIPC/wiki/blob/master/en/majestic-config.md):
  `audio.enabled`, `audio.outputEnabled`, `nightMode.lightSensorPin`,
  `irCutEnabled` and `backlightEnabled` are separate switches.

Shared SDK audio modules and Majestic libraries are intentionally retained. The
current EV200 loader inserts audio modules unconditionally, and removing them or
Opus/Ogg without dependency validation risks unrelated startup failures. This
change disables audio operation by default; it is not an audio-free binary build.

## Build and validation

From a checkout of `device/garus-gsl-5030x-30ap-nm`:

```sh
python3 devices/hi3516ev200_lite_garus-gsl-5030x-30ap-nm/test_boot_defaults.py
python3 .github/scripts/ci-matrix.py --self-test
./builder.sh hi3516ev200_lite_garus-gsl-5030x-30ap-nm
```

The host test requires BusyBox and uses mocked `devmem`, `ipcinfo`, `cli` and
`fw_setenv`; it never accesses hardware. With a firmware checkout, also pass
`--stripper openipc/general/scripts/strip-shell-comments.awk` to test the exact
comment-stripped scripts. Tests belong to the host, not the camera rootfs.

Validation for this change: 24 host cases passed (source and packaged scripts),
including ash syntax, preserving unrelated register bits, direction-before-mux,
idempotency, wrong-SoC rejection, read/write/readback failures and video-only
defaults. No full firmware build, full-tree CI matrix self-test or hardware boot
of this revised profile was performed. Do not promote the old individual camera
tests to acceptance of this new image.

After a successful build, check image sizes and installed dependencies, then test:

1. Fresh first boot and another cold boot with `/etc/custom.ok` already present:
   `muxes.sh` still runs; GPIO15 is an input and follows the physical light sensor.
2. Record explicitly which GPIO15 level means dark/light and confirm the filter
   moves in the matching direction with colour/mono switching. The pre-existing
   `lightSensorInvert=false` and pin order 8/9 are preserved, not newly claimed as
   end-to-end polarity validation. Swap/invert only after that observation.
3. No audio track/playback, unchanged 1080p video, no GPIO/PWM control of the
   autonomous IR board, and no persistent IR-cut coil drive.

An upgrade preserving `/etc/custom.ok` also preserves old first-boot settings.
Such an installation needs an explicit one-time defaults migration after backing
up `/etc/majestic.yaml`; do not delete the entire overlay or rewrite user settings
on every boot. No live camera was modified by this repository change.
The upgrade URL remains unset until a matching artifact is published. Preserve
per-device MAC/network settings; do not bake one camera's identity into the image.
