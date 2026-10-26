# DRAFT (not posted): lfdevs/mesa-for-android-container

**Title:** KGSL: the explicit Present fence is skipped when the kernel supports DMA_BUF_IOCTL_EXPORT_SYNC_FILE, so every swap CPU-waits for the GPU

**Body:**

Thanks for the KGSL Present wait fence in 27.0.0-devel-20261025 (#96): it fixed the black-frame flicker we had with
older builds.

We run a desktop OpenGL game (Beyond All Reason on the Recoil engine) in a Debian trixie proot container with
Termux:X11's X server, `MESA_LOADER_DRIVER_OVERRIDE=kgsl`, `vblank_mode=0`, on a Galaxy Z Fold7 (Snapdragon 8 Elite /
SM8750, Adreno 830, Android 17).

**What we saw:** the game's main thread was blocked 42-51% of every frame in `IOCTL_KGSL_DEVICE_WAITTIMESTAMP_CTXTID`
(stack: `SDL_GL_SwapWindow` → `__glXSwapBuffers` → `loader_dri3_swap_buffers_msc` → `dri_flush` → `st_context_flush`
→ `tc_flush` → `_tc_sync` → `tc_batch_execute` → `__fd_resource_wait` → `fd_bo_cpu_prep`). CPU and GPU took turns; the
GPU idled ~35% and its governor stayed at the bottom clock (342 MHz of 1200). 15-24 fps in a busy scene.

**Why (as far as we can read the source):** the explicit path (the `present` thread that waits for the fence and
triggers the X Sync fence for Present) is only taken when `DMA_BUF_IOCTL_EXPORT_SYNC_FILE` fails with ENOTTY/ENOSYS
(`dri3_dmabuf_sync_file_unavailable`). This kernel supports the ioctl, but KGSL never attaches its fences to the
dma-buf, so the export succeeds with nothing in it, the explicit path is off, and `fd_flush_resource` falls back to
the CPU wait (`FD_BO_PREP_READ`) on every swap.

**Test:** an `LD_PRELOAD` that makes that one ioctl fail with ENOTTY (nothing else changed). A `present` thread
appears, the main thread no longer waits (0 of 200 stack samples, was 42-51%), the GPU runs 78-91% busy at its
thermal maximum, and the same kind of scene (a spectated 8v8, 829 units, hot phone) went to 28.8 fps (our 30 fps
cap). No flicker in play so far. (Before posting: Kailil's check of fold/unfold, where the X screen resizes, and the
floating window.)

**Suggestion:** on KGSL, decide by whether the export actually carries a fence (or always use the explicit path), not
by whether the ioctl exists. Happy to test a build.

The preload: https://github.com/UnderarmCape/... (link once the repo is public) — 20 lines of C.

_This report was written with the help of an AI assistant (Claude); the measurements were made on the device._
