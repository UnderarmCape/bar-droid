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

## A native Android engine: what it would take

The container exists for one reason: Android 10+ only lets an app execute code from its APK's native library
folder, and BAR's engine is a glibc Linux program that expects a Linux file system (`/usr/lib`, `/etc/resolv.conf`,
`/usr/share/fonts`, `/tmp/.X11-unix`) and an X server. proot answers both (its loader maps the Debian binaries; its
ptrace translates every path), lorie answers the second. A port without them, in three steps of growing size:

1. **glibc engine, no proot** (days). Ship the engine, glibc's `ld-linux-aarch64.so.1` and the ~60 Debian libraries
   the engine loads (SDL2, OpenAL Soft, X11/xcb, fontconfig/freetype, Mesa's GLX and freedreno driver) inside the APK
   as `lib*.so` files: everything then executes from the native library folder, and `ld-linux` runs the engine
   with `--library-path <that folder>` (no exec from app data, no W^X problem). What proot translated has to be
   answered another way, because glibc opens these files with internal calls an LD_PRELOAD cannot catch: a glibc
   built with its prefix inside the app's data folder (`/data/data/<pkg>/files/sys`: `resolv.conf`, `nsswitch.conf`,
   locales and gconv there), `FONTCONFIG_FILE`, `LIBGL_DRIVERS_PATH`, `XLOCALEDIR`, `DISPLAY` as the socket's full
   path (libxcb 1.15+), `/dev/shm` users pointed at memfd. The engine finds its own data from `/proc/self/exe`
   (that would be `ld-linux`): an engine setting or `--isolation-dir`. Gains: proot's stops and its process (below).
   Risks: every absolute path a library hides; updates of the engine and of Debian's libraries become APK updates
   (today `setup-container.sh` and `Updater` install them at run time).
2. **No X server** (one to two weeks). The engine (an engine-branch change in `SpringApp`/`GlobalRendering`) renders
   its last pass into AHardwareBuffers the app allocates and passes over a Unix socket (their dma-buf, imported into
   Mesa as a memory object, `GL_EXT_memory_object_fd`, with the layout gralloc chose), and hands each finished buffer
   back with a fence; the app shows it with one SGSR pass straight onto its SurfaceView (or, without SGSR, as a
   SurfaceControl buffer the display hardware scales for free). SDL2 keeps a window for input only or gives way to the
   app's own input events (touch and pad already arrive through files and UDP). Gains: the CPU copy of every
   picture, the X server process, the Present round trips. Risks: gralloc's layout against freedreno's (UBWC, pitch
   alignment), fences between two GL stacks (Mesa's and Android's), fold/unfold resizes.
3. **A bionic engine** (weeks to months, BAR's developers' call). Recoil built with the NDK against bionic, Mesa's
   freedreno GL built for bionic as a private library (it already talks to `/dev/kgsl-3d0` from user space),
   OpenAL Soft on AAudio, SDL2's Android backend or none. Removes Debian altogether (~375 MB on disk, the first-run
   install). The catch is sync: the NDK has only clang, and the official engine is GCC 13 with
   `-fsingle-precision-constant` (docs/ENGINE-SIM.md, engine/sim branch: a clang build matched 20 minutes of a
   real replay, but GCC is the proven choice); every simulation file must compute bit for bit what BAR's servers'
   players compute.
