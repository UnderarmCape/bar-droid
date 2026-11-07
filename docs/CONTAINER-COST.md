# What the container layer costs on the phone (2026-11-06/07)

BAR Droid runs BAR's engine inside a Debian container (proot: ptrace stops the engine for the system calls proot
translates) and shows its picture through an X server built into the app (Termux:X11's lorie), which the app then
upscales onto the display with Qualcomm's SGSR. This note measures what that layer costs in a late 16-player game on
the 8 GB dev phone (Galaxy S23 Ultra, Snapdragon 8 Gen 2, Adreno 740), what was built to shed the biggest fixable part,
and what a native Android engine without the layer would take.

Branch `no-proot` of the app (worktree `C:\Tools\BARANDROID\bar-droid-noproot`). Tools: `tools/container-cost/`.

## How a frame reaches the screen today

1. The engine (glibc, under proot) draws with Mesa (lfdevs' freedreno on KGSL) into a back buffer Mesa allocated (a
   KGSL buffer exported as a LINEAR dma-buf), and presents it with DRI3/Present over the X socket (`/tmp/.X11-unix/X0`).
2. lorie's X server (a separate app_process, `bardroid-x11`) gets the dma-buf. It cannot flip it to the screen (lorie
   refuses flips of imported dma-bufs: "does not work fine with turnip"), and Android's EGL has no
   `EGL_EXT_image_dma_buf_import` (the dev phone's EGL lists only `EGL_ANDROID_image_native_buffer` /
   `get_native_client_buffer`), so its GPU copy path cannot take it either: **every picture is copied by the CPU** from
   the mmapped dma-buf into the root window's AHardwareBuffer (logcat, late 8v8: `0/52 present copies offloaded to
   GPU (CPU fallback: ... 52 other)`).
3. The app's renderer thread (`LorieRendererTh`, in the app process) samples the root AHardwareBuffer (EGLImage, no
   copy) and draws it onto the SurfaceView (2316x1080 on the dev phone) through SGSR 1, plus the pointer, waits for the
   GPU (fence) and swaps. SurfaceFlinger shows the SurfaceView as a hardware overlay (composition type DEVICE: no GPU).
4. The renderer draws whenever the root changed **or the pointer changed or moved**. The engine sets its hardware
   pointer again every frame it draws (the same image): lorie converted it, the renderer uploaded it again and redrew
   the whole SGSR picture: **~2.5 draws per engine picture** in a late 8v8 (logcat: 125-150 renderer frames per 5 s
   against 52-55 presents).

## Measurements

(filled in below as the runs come in)
