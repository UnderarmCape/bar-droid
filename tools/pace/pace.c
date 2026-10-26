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
 * BARDROID_FPS: frames per second (30 default, 0 = no cap). Built by tools/build-pace.py without glibc headers:
 * the few declarations it needs are below, and the symbols resolve against the engine's libc at load time.
 */
struct timespec { long tv_sec; long tv_nsec; };
extern int clock_gettime(int clock, struct timespec *ts);
extern int clock_nanosleep(int clock, int flags, const struct timespec *request, struct timespec *remain);
extern void *dlsym(void *handle, const char *symbol);
extern char *getenv(const char *name);
#define RTLD_NEXT ((void *) -1L)
#define CLOCK_MONOTONIC 1
#define TIMER_ABSTIME 1
#define EINTR 4

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
