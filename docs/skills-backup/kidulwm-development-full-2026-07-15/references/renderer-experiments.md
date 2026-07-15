# Renderer experiments

## 2026-07-09: Pixman vs GLES2 (kms_swrast)

Context: animations disabled; output Virtual-1 forced to 3840x2160.

### Pixman (service default)
- env: WLR_RENDERER=pixman
- log: KidulWM: renderer pixman=true gles2=false
- result: boots cleanly; text is pixelated at 3840x2160.
- hypothesis: Pixman nearest-neighbor upscaling of client surfaces.

### GLES2 (kms_swrast)
- env: WLR_RENDERER=gles2
- log: KidulWM: renderer pixman=false gles2=true; new output Virtual-1 3840x2160
- boot result: starts; output commits successfully.
- client test: Ghostty returned Gtk: Failed to open display; needs further reproduction.
- hypothesis: GLES2 software raster should filter better than Pixman.

### Next test
Run Ghostty directly under the live GLES2 compositor, verify windows map, and visually compare sharpness.
