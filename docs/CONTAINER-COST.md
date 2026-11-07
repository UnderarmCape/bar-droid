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

### proot

What its seccomp filter stops (Termux's proot, `tools/build-proot.py`'s ioctl filter on top): every path-taking call
(`openat`, `faccessat`, `newfstatat`, `readlinkat`, `statx`, ...), `fstat` (link2symlink, the ashmem/memfd
extension), `close` (proot tracks netlink, auxv and pipe descriptors), `brk` (proot's heap emulation), `getcwd`,
`clone`, `prctl`, `execve`, and **`recvmsg`, `sendmsg`, `sendto`, `recvfrom`, `sendmmsg`** (Unix socket addresses,
fake netlink sockets). Not stopped: `read`/`write`/`readv`/`writev`, `recvmmsg`, `mmap`, `futex`, `ioctl` (but for the
seven terminal/network requests proot handles), the vDSO clock.

One stop, `tools/container-cost/trapbench` in the dev phone's container (idle phone, three rounds; the same calls
outside proot in brackets): `fstat` 71-463 us (0.3), `close(-1)` 33-249 us (0.3), `sendmsg`+`recv` 56-448 us (1.2),
`brk(0)` 46-134 us (0.2), `openat`+`close` 206-782 us (3.7), `getppid` (never stopped) 0.8-1.3 us. A stop is two
context switches to proot's process and back plus proot's own work: **hundreds of times the call itself**, and
slowest when the cores have gone idle in between.

In the game (late 8v8, game second ~1300, 13 fps, read passively while another session's run played,
`stopsample` at 2 kHz for 20 s on the engine's main thread): **stopped by proot 1.38 % of the time** (503 stop
episodes seen; many shorter ones fall between samples, the share stays exact). By system call, of the samples that
could be attributed: `recvmsg` 60 % (libxcb reading the X connection), `faccessat` 12 %, `openat` 11 %, `close` 10 %,
`newfstatat`/`fstat` 6 %. (The unattributed rest is a race in the probe: the stop ended between reading the thread's
state and its system call.) proot's own process: ~3.3 % of one core, ~285 wake-ups a second (each stop wakes it).

My own runs (`tools/container-cost/measure.ps1`: the 2026-10-26 Isthmus 8v8 replay, game seconds 1210-1330, engine
`gcc-cut` with its springsettings, render scale 70 %: a 1408x657 X screen on the 2316x1080 display; phone hot, the
prime core capped at 1248-1363 MHz, GPU at 475-615 MHz and 47-76 % busy, so this window was CPU-bound; 12-16 fps,
x0.98-1.00):

| | run A (00:46, as shipped) | run B (00:59) |
| --- | --- | --- |
| main thread stopped by proot | 1.05 % (`recvmsg` 48 % of the attributed) | 1.66 % (`getsockopt` 51 %: see below) |
| proot's process | | 4.1 % of a core, 584 wake-ups/s |

Run B had the first version of the X socket change in the pace library, which asked each socket's type with
`getsockopt` on every call: proot stops `getsockopt` too (its fake root answers `SO_PEERCRED`), so it traded one stop
for two. Fixed (asked once per descriptor), measured again below.

### The display path

| | run A | run B |
| --- | --- | --- |
| engine pictures a second (Present) | 13.8 | 13.4 |
| X server: CPU copy of each picture | 1.18-1.30 ms (~100 MB/s from the dma-buf), 0.2 ms of it waiting for the renderer | 1.14-1.25 ms |
| renderer draws a second | 32 (of them pointer only: 18) | 30 (pointer only: 17) |
| GPU per draw (SGSR 1408x657 -> 2316x1080, the pointer) | 0.74 ms at 475 MHz | 0.72-0.81 ms |
| GPU time of the display pass | 23 ms a second (2.3 % of the GPU) | 20-24 ms a second |
| renderer thread per draw (mostly its fence waits) | 8.3-8.7 ms | 7.5-8.5 ms |
| X server pointer traffic | ~17 sets a second, every one a new image | the same: 0 moves, every set a new image |

The engine's pointer is animated (Recoil's `HardwareCursorSDL::Update` sets the current frame of BAR's animated cursor
every drawn frame): the X server's dedupe of identical images (patch 0011) finds none, so more than half of the
renderer's draws exist only to show the next pointer frame. Fixed in the renderer (a pointer image alone waits up to
100 ms for the next picture), measured again below.

Memory (run B, PSS in RAM + swapped): the app's process 15 + 31 MB, the X server 3 + 43 MB, proot 1 + 0.5 MB; on the
GPU the SurfaceView's five 2316x1080 buffers (49 MB, `dumpsys gfxinfo`) and the root window (3.6 MB). The engine
itself: 1.33 GB + 2.1 GB, the GPU driver 2.06 GB in all.

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
