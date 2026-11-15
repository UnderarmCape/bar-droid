# Draft: a report for lfdevs' Mesa for Android containers (KGSL submit fails with EDEADLK)

A draft for Kailil to post (or not) as an issue at https://github.com/lfdevs/mesa-for-android-container (DELIVERY.md:
"if it repeats, a report for lfdevs' Mesa"). Nothing is posted from here. Logs on the laptop:
`C:\Tools\BARANDROID\engine-sim\runs\20261105-0546-gpu-hang-launcher.log`; on the dev phone:
`files/logs/hang-2026-11-02.log`.

---

**Title:** freedreno (KGSL): `flush_submit_list: submit failed -1 (Resource deadlock avoided)`, then the app hangs

**Setup**
- Galaxy S23 Ultra (SM-S918U, Snapdragon 8 Gen 2 / Adreno 740, `kalama`), Android 17 / One UI 9, kernel
  `5.15.197-android13-8`, build `S918USQU8GZIF`.
- `mesa-for-android-container_27.0.0-devel-20261025_debian_trixie_arm64`, Gallium freedreno on KGSL (not Turnip/Zink),
  in a Debian trixie proot container; the X server is Termux:X11 (built into the app).
- The program: the Recoil RTS engine (Beyond All Reason), OpenGL, playing back a recorded game.

**What happens** (11 times over two weeks of daily test runs, 2026-11-02 to 15, several hundred game starts; at
its most frequent about 1 in 25)
```
MESA: error: flush_submit_list:89: submit failed -1 (Resource deadlock avoided)
MESA: error: flush_submit_list:89: submit failed -1 (Resource deadlock avoided)
... (13-72 times within a second)
```
then no frame is ever presented again; the engine's watchdog reports the main thread hung 30 s later. The process
must be killed. The phone itself recovers (the next start works).

**When**
- 2026-11-02 22:32 and 2026-11-05 05:46: a replay's opening seconds, before the first simulated frame (the world is
  drawn at 20-30 fps with no units, the GPU 20% busy at 220 of 615 MHz, 49 C: a cool, nearly idle GPU); the 05:46 one
  ~25 s after the playback began.
- 2026-11-04: a replay being fast-forwarded on a hot phone, after ~40 s of the engine's "GPU fence wasn't signalled
  within 100 ms" warnings.
- In skirmishes too since: 2026-11-05 19:52 (frame 741, a minute in), 2026-11-09 06:43 (frame 776) and 11:14
  (frame 104, 5 s after loading, right after a 13-minute benchmark: GPU capped at 615 MHz, thermal level 2, 96 %
  busy, 59 C). Cool and hot phones, idle and busy GPUs, early and a minute in: no pattern yet.
- Since: 2026-11-09 15:54 and 16:37 (skirmishes, the phone upright), 2026-11-12 21:25 and 11-13 06:50 (skirmishes);
  2026-11-15 09:58 a recorded 8v8 fast-forwarded at frame 17906 on a hot phone (GPU held at 295-348 MHz by thermal
  limits, 99 % busy), 72 of the lines in one second, the watchdog 31 s later.

**What we know**
- EDEADLK from the KGSL submit ioctl usually means the context was invalidated after a GPU fault; the kernel's log,
  which would say what faulted, is not readable without root.
- The app answers one ioctl itself (via an LD_PRELOADed library): the query for the explicit present fence, so that
  the swap does not wait for the GPU; this has run in every game since 2026-10-25 with no other failure.

**Asks**: is a context loss on KGSL expected to surface as a hang, or could Mesa report it as a lost context
(`GL_ARB_robustness`) so the application can exit cleanly? Any debug environment variable that would show the fault
from userspace?
