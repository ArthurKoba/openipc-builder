# ANJIA AJL33PQ0866 Divinus overlay

This directory is intentionally part of the named Builder device profile.

- `divinus.mk` selects the one-commit generic FH8626V100 Divinus port.
- `0001-anjia-ajl33pq0866-camera-features.patch` carries only this camera's
  dual-lens, PTZ/servo, saved-state, illumination, recording and diagnostic
  behavior.

The generic `firmware` repository must not absorb this patch series. Builder
copies this device package into the firmware checkout before the profile build.
