# ANJIA AJL33PQ0866 board support

This package contains only low-level hardware backends that are specific to the
ANJIA AJL33PQ0866 board.

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

The shim forwards relative pan/tilt steps to `fh8626-ptz move`. The generic
delay argument is accepted for interface compatibility but is not used: this
board's hardware PWM period comes from the board/stock timing parameters rather
than userspace GPIO sleeps.

Commands:

```text
fh8626-ptz status
fh8626-ptz move PAN_STEPS TILT_STEPS
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
