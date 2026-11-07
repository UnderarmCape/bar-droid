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
`gcc-cut` with its springsettings, no frame cap (the dev phone's benchmark setup), 3,300-3,450 units; the phone
hot: prime core capped at 1248-1363 MHz, GPU at 475-615 MHz and 47-76 % busy, so this window was CPU-bound,
12-16 fps at x0.92-1.00 in every run). Runs A-D played at the phone's saved render scale, 100 % (a 2008x938 X
screen on the 2316x1080 display); run E at 70 % (1408x657) is below.

| | A (00:46) as shipped | B (00:59) first try | C (01:50) the fixes | D (02:03) C + the display scales |
| --- | --- | --- | --- | --- |
| main thread stopped by proot | 1.05 % | 1.66 % | **0.23 %** | 0.25 % |
| of it, by call (attributed samples) | `recvmsg` 48 %, `openat` 19 %, `faccessat` 11 % | `getsockopt` 51 % | `faccessat` 48 %, `newfstatat` 25 % | the same |
| main thread's voluntary switches | | 505/s | 89/s | 96/s |
| proot's process | | 4.1 % of a core, 584 wake-ups/s | 2.8 %, 196/s | 2.7 %, 188/s |
| engine pictures a second | 13.8 | 13.4 | 13.9 | 13.4 |
| X server: CPU copy of a picture | 1.18-1.30 ms (~100 MB/s), 0.18-0.34 ms of it waiting for the renderer | 1.14-1.25 ms | 1.05-1.09 ms, 0.00-0.04 waiting | 1.05-1.20 ms, 0.00 waiting |
| renderer draws a second | 32 (pointer only: 18) | 30 (17) | **14 (0.2)** | 13 (0.4) |
| GPU per draw | 0.74 ms (SGSR) | 0.72-0.81 ms | 0.71-0.75 ms | **0.50-0.55 ms** (1:1, no SGSR) |
| GPU time of the display pass | 23 ms a second (2.3 % of the GPU) | 20-24 ms | **10.3 ms** | **5.8-7.0 ms** |
| renderer thread | 8.3-8.7 ms a draw | 4.9 % of a core | 2.6 % of a core | 3.0 % |
| X server process | | 6.7 % of a core | 7.2 % | 7.3 % |
| SurfaceView buffer, composition | 2316x1080, DEVICE | the same | the same | 2012x938 scaled by the display hardware, DEVICE |

Run B had the first version of the X socket change in the pace library, which asked each socket's type with
`getsockopt` on every call: proot stops `getsockopt` too (its fake root answers `SO_PEERCRED`), so it traded one stop
for two. Run C asks once per descriptor.

The engine's pointer is animated (Recoil's `HardwareCursorSDL::Update` sets the current frame of BAR's animated cursor
on every drawn frame, ~17 a second, a new image each time: the X server's dedupe of identical images finds none),
so in A and B more than half of the renderer's draws were there only to show the next pointer frame. In C a pointer
image alone waits up to 100 ms for the next picture (or a move, which still draws at once).

Run E (02:13, the fixes as in C, **render scale 70 %**: a 1408x657 X screen, SGSR to 2316x1080): 13-21 fps, x1.00
(median), 0 desync warnings; main thread stopped by proot 0.27 %; proot 2.6 % of a core (210 wake-ups/s); X server
5.6 %; the CPU copy **0.46-0.49 ms a picture** (49 MB/s); the renderer drew only pictures (69-72 per 5 s), **0.53-0.55 ms
of GPU a draw, 7.5 ms of GPU a second**, 3.1-3.3 ms of its thread a draw (2.8 % of a core). After the measured part,
with the replay over and the engine drawing 1 picture a second, the pointer kept animating at the 100 ms fallback
(24 pointer-only draws in 5 s).

No run had a desync warning (each fast-forwards the first 20 minutes of the server-recorded replay, every frame
checked against every player's checksum): nothing here touches what the simulation sees.

Memory (run B, PSS in RAM + swapped): the app's process 15 + 31 MB, the X server 3 + 43 MB, proot 1 + 0.5 MB; on the
GPU the SurfaceView's five display-sized buffers (5 x 9.8 MB = 49 MB, `dumpsys gfxinfo`; 5 x 7.5 MB in run D) and the
root window (7.5 MB at 100 %, 3.7 MB at 70 %). The engine itself: 1.33-1.48 GB + 1.95-2.13 GB swapped, the GPU driver
2.06 GB in all.

## What the layer costs, in one table (late 8v8, hot dev phone)

| | as shipped | with this branch |
| --- | --- | --- |
| engine main thread stopped by proot | 1.05-1.38 % | 0.23-0.27 % |
| proot's process | ~3.3 % of a core, 285 wake-ups/s | 2.6-2.8 %, ~200/s |
| X server process (CPU copy of every picture: 0.5 ms at 70 %, 1.1-1.3 ms at 100 %) | 6-7 % of a core | 5.6-7.3 % |
| display pass on the GPU (SGSR + pointer) | 23 ms a second (2.3 % of the GPU, ~2.3 draws a picture) | 7.5 ms (70 %) - 10.3 ms (100 %) a second, one draw a picture; 5.8-7 ms with the display hardware scaling (100 %) |
| app's renderer thread | ~5 % of a core | ~3 % |
| memory | app 15-19 MB + X server 3-4 MB + proot 1 MB in RAM, ~75 MB swapped; GPU: 49 MB of display buffers + the root window (4-8 MB) | the same (38 MB / ~18 MB of display buffers with the display hardware scaling at 100 % / 70 %) |
| disk | Debian container 375-388 MB | the same |

Against what the frame costs (~45 ms of the engine's main thread a frame at 13-16 fps, the GPU 47-99 % busy depending
on the heat), the container layer is small: ~1 % of the main thread and ~2 % of the GPU as shipped, ~0.25 % and
~0.8-1 % with this branch. It is not what keeps the late 8v8 from 30 fps; the engine's own simulation and drawing are
(docs/ENGINE-SIM.md on `engine/sim`). What it does cost is power (~15 % of one core across proot, the X server and the
renderer, most of it on the little and middle cores) and ~150 MB of RAM and swap, which matter on a hot 8 GB phone, and
the first-run install.

## What was built (branch `no-proot`)

All of it app-side: nothing the simulation sees changes, so online play is unaffected.

- **The X connection around proot's traps** (`tools/pace/pace.c`, `libbardroid_pace.so`, already preloaded into the
  engine): `recvmsg` on a Unix stream socket without an address becomes `recvmmsg` with one message (passed
  descriptors still arrive), `sendmsg` without control data becomes `writev`; proot's filter stops neither, and it has
  nothing to do in either call on such a socket. Each descriptor's type is asked once (`getsockopt`, which proot also
  stops) and forgotten in the library's `close`/`dup2`/`dup3`. Datagram sockets (proot's fake netlink ones), calls with
  an address, control data or flags keep their real calls. `BARDROID_SOCKET_TRAPS=1` (dev-env.sh) switches it off.
  Checked by `tools/pace-test.ps1` (new cases: bytes, a passed descriptor, EAGAIN, datagram sockets): ALL PASS.
- **One display draw per picture** (termux-x11 patch `0011-lorie-display-cost-and-pointer-dedupe.patch`): a new
  pointer image alone waits up to 100 ms for the next picture (the engine's animated pointer changes on every frame
  it draws); a pointer set with the image already shown and a move to where the pointer already is are dropped in the
  X server; a pointer that is not drawn moving draws nothing. Every 5 s logcat has `[display-cost]` lines from the X
  server (CPU copies of the engine's pictures: count, ms each, MB/s, the wait for the renderer; pointer sets, new
  images, moves) and from the renderer (draws, of them new pictures and pointer only; the display pass's GPU time
  from `EXT_disjoint_timer_query`; the renderer's own time a draw).
- **Optional: the display hardware scales** (same patch, `LorieView.surfaceAtScreenSize`; on only with
  `files/bar/.bardroid-display-scales`, read by `GameActivity` at start): the SurfaceView's buffer is the X screen's
  size (`setFixedSize`), the renderer draws it 1:1 and SurfaceFlinger's hardware composer enlarges it (composition
  stays DEVICE: no GPU). About a third less GPU time for the display pass at 100 % (0.73 -> 0.52 ms a draw; more at 70 %,
  not measured), smaller display
  buffers, but the display's own scaler instead of SGSR's edge-adaptive sharpening: Kailil's eye decides, so it is
  off by default.
- **Probes** (`tools/container-cost/`): `stopsample` (a thread's time stopped by proot, by system call), `trapbench`
  (microseconds per stopped call), `threads.sh` + `thrdiff.ps1` (each thread's CPU), `measure.ps1` (a late 8v8 with
  all of them, on top of `replay-memory.ps1` from `engine/sim`).

Checked on the dev phone with this APK: `pace-test.ps1`, `pad-test.ps1`, `lobby-phone-test.ps1`,
`touch-phone-test.ps1` ALL PASS; late 8v8 runs C-E at x1.00 with 0 desync warnings.

Not done: the per-frame `faccessat`/`newfstatat`/`openat`/`close` stops that remain (~0.2 % of the main thread:
BAR's widgets and the engine looking for files; each needs proot's path translation); the CPU copy of every picture
(it needs the engine's Mesa to render into Android buffers: step 2 below); fps A/B runs (single runs swing +-2 fps
with the heat, far more than ~1 % of the main thread and of the GPU: the gains here are measured directly, by the
probes, not by fps).

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

What the three steps would buy, from the table above: step 1 the last ~0.25 % of the main thread and proot's ~2.7 % of
a core; step 2 the X server's ~6 % of a core, the CPU copy and most of the display pass (or all of it with the display
hardware scaling), ~50 MB of RAM and swap; step 3 the 375 MB container, its first-run install and Debian's update path.
None of them is worth more than a few percent of fps on its own: the reasons to do them are power, memory, install size
and a build BAR's developers can ship from their own CI, not the frame rate. Order of work for whoever picks it up:
step 2's present path first (the engine branch already has `BarDroidDeferSwap`, the place to hand a finished frame
over), measured with this branch's `[display-cost]` lines; then step 1; step 3 only together with BAR's own build of
the engine.
