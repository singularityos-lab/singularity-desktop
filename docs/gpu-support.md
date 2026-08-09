# GPU and renderer support

Singularity does **not** require Vulkan. It runs on GLES-only GPUs — for example Arm
Mali parts driven by `libmali`, which expose GLES 3.x and no Vulkan driver at all.

Two independent renderer decisions make this work, and both already default correctly:

1. **GTK4 (shell and apps).** `singularity-desktop-session` sets `GSK_RENDERER=gl`, so
   GTK uses its GL renderer and never requests the Vulkan (`ngl`) path.

2. **wlroots (labwc's compositor backend).** wlroots auto-selects a renderer and falls
   back to GLES2 when no Vulkan renderer is available.

So a GLES-only GPU needs no configuration, no override and no source changes.

## Verified configuration

A full session (labwc + shell + apps) running on Arm **Mali-G720** (CIX Sky1 CD8180,
GLES 3.x, no Vulkan driver present), aarch64. GLES2 was auto-selected; no `WLR_RENDERER`
override was needed.

## Forcing a renderer

wlroots and GTK both read their renderer choice from the environment, so nothing in
Singularity needs to be changed to pin one:

```bash
WLR_RENDERER=gles2 GSK_RENDERER=gl singularity-labwc-session
```

Note that `singularity-labwc-session` already has a software-rendering safety net: if the
session exits within 30 seconds it retries once with `GSK_RENDERER=cairo`,
`WLR_RENDERER=pixman`, `LIBGL_ALWAYS_SOFTWARE=1` and `GALLIUM_DRIVER=llvmpipe`, so an
early crash on the hardware GL path still lands you at a usable desktop (see #78). If you
find yourself in a software session unexpectedly, check the labwc log for that retry line
before assuming your GPU is unsupported.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Session starts, then everything is slow | The #78 fallback fired — grep the labwc log for `retrying with software rendering` |
| Compositor fails to start on a GLES-only GPU | Confirm the GLES driver is actually loading; try `WLR_RENDERER=gles2` explicitly |
| GTK apps fail but the compositor is fine | A GTK-side renderer issue, not wlroots — try `GSK_RENDERER=cairo` |
