/*
 * libbardroid_pace.so: BAR Droid's frame cap, LD_PRELOADed into the engine (Debian glibc, aarch64).
 *
 * Why: the phone's Mesa (lfdevs, KGSL Present-fence path) lets the CPU build the next frame while the GPU draws the
 * last one only with a third back buffer, which it allocates for swap interval 0. The 30 fps cap used to be swap
 * interval 2 (VSync), which left two buffers: the engine's main thread then waited for the GPU 43-58% of every frame
 * and the GPU, idle in between, stayed at a third of its clock (measured 2026-10-26). So the app runs Mesa with
 * vblank_mode=0 (never wait for vblank) and caps the frame rate here instead: after each SDL_GL_SwapWindow (which
 * returns at once) the main thread sleeps until the next frame slot while the GPU works on the frame just submitted.
 *
 * BARDROID_FPS: frames per second (30 default, 0 = no cap).
 *
 * The swap itself still made the main thread wait for the GPU (2026-10-26, spectating an 8v8: 42-51% of each frame
 * in SDL_GL_SwapWindow -> glXSwapBuffers -> dri_flush -> fd_flush_resource -> KGSL wait). lfdevs' Mesa (PR #96) has
 * two ways to hand a finished frame to the X server: an explicit Present fence (a "present" thread waits for the
 * GPU and triggers an X Sync fence; the game goes on) or, as a fallback, a CPU wait in fd_flush_resource until the
 * GPU has finished the frame. It takes the explicit path only when the window buffer's dma-buf cannot export a sync
 * file (DMA_BUF_IOCTL_EXPORT_SYNC_FILE fails with ENOTTY). The Fold7's kernel supports that ioctl, but KGSL never
 * attaches its fences to the dma-buf, so the export is empty and Mesa fell back to the wait on every frame. ioctl()
 * below answers ENOTTY for that request, and Mesa takes the explicit path (our lorie has the X server's Present
 * wait-fence fix, termux-x11 b36dac08). BARDROID_PRESENT_FENCE=0 leaves the ioctl alone.
 *
 * Built by tools/build-pace.py without glibc headers: the few declarations it needs are below, and the symbols
 * resolve against the engine's libc at load time.
 */
struct timespec { long tv_sec; long tv_nsec; };
extern int clock_gettime(int clock, struct timespec *ts);
extern int clock_nanosleep(int clock, int flags, const struct timespec *request, struct timespec *remain);
extern void *dlsym(void *handle, const char *symbol);
extern char *getenv(const char *name);
extern int *__errno_location(void);
#define RTLD_NEXT ((void *) -1L)
#define CLOCK_MONOTONIC 1
#define TIMER_ABSTIME 1
#define EINTR 4
#define ENOTTY 25
#define DMA_BUF_IOCTL_EXPORT_SYNC_FILE 0xc0086202UL   /* _IOWR('b', 2, struct dma_buf_export_sync_file) */

typedef int (*ioctl_fn)(int fd, unsigned long request, void *arg);
static ioctl_fn real_ioctl;
static int hide_sync_export = -1;   /* -1: not read yet */

int ioctl(int fd, unsigned long request, ...) {
    __builtin_va_list ap;
    __builtin_va_start(ap, request);
    void *arg = __builtin_va_arg(ap, void *);
    __builtin_va_end(ap);
    if (request == DMA_BUF_IOCTL_EXPORT_SYNC_FILE) {
        if (hide_sync_export < 0) {
            const char *s = getenv("BARDROID_PRESENT_FENCE");
            hide_sync_export = !(s && s[0] == '0');
        }
        if (hide_sync_export) {
            *__errno_location() = ENOTTY;
            return -1;
        }
    }
    if (!real_ioctl) real_ioctl = (ioctl_fn) dlsym(RTLD_NEXT, "ioctl");
    return real_ioctl(fd, request, arg);
}

typedef void (*swap_fn)(void *window);
static swap_fn real_swap;
static long long interval_ns = -1;   /* -1: not read yet */
static long long next_ns;

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

static long long read_interval(void) {
    const char *s = getenv("BARDROID_FPS");
    long fps = 30;
    if (s && *s) {
        fps = 0;
        while (*s >= '0' && *s <= '9') fps = fps * 10 + (*s++ - '0');
    }
    return fps > 0 ? 1000000000LL / fps : 0;
}

void SDL_GL_SwapWindow(void *window) {
    if (!real_swap) real_swap = (swap_fn) dlsym(RTLD_NEXT, "SDL_GL_SwapWindow");
    if (interval_ns < 0) interval_ns = read_interval();
    real_swap(window);
    if (interval_ns == 0) return;
    long long now = now_ns();
    if (next_ns == 0) next_ns = now;
    next_ns += interval_ns;   /* when this frame's slot ends */
    if (now >= next_ns) {     /* the frame took the whole slot or more: no sleep, pace from here */
        next_ns = now;
        return;
    }
    struct timespec until = { (long) (next_ns / 1000000000LL), (long) (next_ns % 1000000000LL) };
    while (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &until, 0) == EINTR) {}
}
