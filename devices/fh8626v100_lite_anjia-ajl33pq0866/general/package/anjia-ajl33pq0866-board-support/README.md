# ANJIA AJL33PQ0866 board support

This device-local package contains the executable hardware backends that are
specific to the ANJIA AJL33PQ0866 board. It is copied and registered only when
this named device is selected; unrelated Builder targets never see it.

## PTZ motor backend

`fh8626-ptz` drives the hardware-proven pan/tilt PWM groups through
`/dev/fh_pwm`:

- pan: PWM11/10/9/6;
- tilt: PWM5/4/3/7.

The source keeps the proven Fullhan PWM transaction shape, phase ordering,
per-axis timing, pinmux hand-off, single-owner lock and safe output disable.
`pan_period`, `tilt_period`, `pan_invert` and `tilt_invert` may still be
read from the existing U-Boot environment. `pwm_invert` remains a pan fallback
for compatibility with the stock environment.

Production PTZ is deliberately stateless. It does not calibrate on boot, move
the camera during startup, save coordinates, infer an absolute position, or
provide `goto/home` commands. The mechanism has no absolute encoder, so a
saved coordinate cannot prove physical position after power-off or manual
movement.

The OpenIPC-facing entry point is the standard relative interface:

```text
gpio-motors PAN_STEPS TILT_STEPS DELAY_MS
```

The shim forwards relative pan/tilt steps and the standard delay argument to
`fh8626-ptz move`. A positive delay becomes the nominal hardware-PWM period
for both axes. Delay 0 keeps the board's proven per-axis defaults. This preserves
the OpenIPC speed-control semantics without replacing hardware PWM with
userspace GPIO sleeps.

Commands:

```text
fh8626-ptz status
fh8626-ptz move PAN_STEPS TILT_STEPS [DELAY_MS]
```

No PTZ init service is installed. Boot leaves the camera where it physically is.

The previous stock-style controller with type-2 startup calibration, persistent
coordinate state and absolute return logic is preserved as reference at
`archive/fh8626v100-anjia-stock-ptz-controller-20260918`. That reference is
evidence/debug material, not the production device policy.

## Lens selector

`fh8626-lens` is independent from PTZ. It owns only the physical WIDE/TELE
selector on GPIO4/GPIO14 and follows the captured target-first ordering:

- WIDE: assert GPIO4, then deassert GPIO14;
- TELE: assert GPIO14, then deassert GPIO4.

It waits 60 ms for the physical selector to settle. It does not recreate the
sensor/ISP stack and does not own VENC, AE, mirror/flip, illumination or
day/night policy. A runtime such as Divinus or Majestic must perform the full
logical lens-switch transaction around this low-level selector. The separate
cold-boot GPIO5 dual-sensor bootstrap also belongs to board/media startup, not
to normal lens switching.

Commands:

```text
fh8626-lens state
fh8626-lens set wide
fh8626-lens set tele
```

## Validation boundary

The PWM motor mapping and stock-style low-level PWM transaction were accepted on
hardware after correcting swapped motor connectors. The simplified stateless
production wrapper still requires an owner hardware regression for relative
pan/tilt direction, bounded movement, cancellation and safe stop.

Run the retained host recorder tests before target work:

```text
make -C src clean test
```


## Illumination / IR-cut helper

The package also installs the runtime-neutral physical helper for IR LED GPIO25,
white LED GPIO23 with the shared SADC1 pad, and the GPIO18/GPIO60 IR-cut
actuator. It does not implement AUTO/DAY/NIGHT/WLIGHT media policy. The
`S68anjia-hardware` init hook only establishes safe electrical outputs at boot
and shutdown.


## Device/update identity

The package writes the selected named target to `/etc/openipc/builder-target`.
`S32anjia-env` validates that marker on every NOR boot and keeps the
board-qualified self-update URL and RTL8188FU profile synchronized without
rewriting unchanged U-Boot environment variables. A TFTP/initramfs boot is
explicitly read-only with respect to persistent U-Boot environment state.


## Speaker amplifier mute

The board package owns the physical speaker-amplifier mute on GPIO24, active
high. This GPIO is separate from the FH8626 RTX audio transport.

`fh-anjia-ajl33pq0866-audio` exposes only the physical board operation:

```text
fh-anjia-ajl33pq0866-audio mute
fh-anjia-ajl33pq0866-audio unmute
fh-anjia-ajl33pq0866-audio status
```

Boot, shutdown and board restart force the amplifier into the safe muted state.
The selected media runtime must unmute only after AO is configured and must mute
again before AO teardown. The generic FH8626 audio/RTX adapter must not contain
AJL33PQ0866 GPIO policy.
