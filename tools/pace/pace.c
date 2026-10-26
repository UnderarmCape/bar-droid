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
 * While nobody sees the game (the app's game screen stopped: phone locked, another app in front), the app keeps
 * /tmp/bardroid-hidden. The engine stops drawing by itself when its window is hidden or minimized (SpringApp's
 * SDL_WINDOWEVENT_HIDDEN: Game::Draw returns early, two frames a minute; sound muted, as minimizing BAR on a PC does),
 * but without a window manager nothing ever hides its window, so it drew 30 frames a second for nobody: heat the next
 * minutes of play pay for. SDL_PollEvent below hands the engine SDL2's HIDDEN / SHOWN window event when the flag comes
 * and goes (checked twice a second; the engine polls events every loop, drawn or not). The simulation and the
 * network keep running. Only with SDL2 (its event layout); BARDROID_HIDDEN_PAUSE=0 turns it off.
 * The same while the game catches up with a running game far behind (/tmp/bardroid-catchup, set by the app from the
 * touch widget's progress file): no drawing, every pass of the engine's loop to the simulation, the GPU cool.
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
extern int access(const char *path, int mode);
#define F_OK 0
#define RTLD_DEFAULT ((void *) 0)
#define HIDDEN_FLAG "/tmp/bardroid-hidden"
#define CATCHUP_FLAG "/tmp/bardroid-catchup"
/* The floating window (picture-in-picture): the X screen shrinks to it, so the engine already draws few pixels; the
   app keeps this flag meanwhile and the cap drops to FLOATING_FPS too (Kailil, 2026-10-26). Checked twice a second. */
#define FLOATING_FLAG "/tmp/bardroid-floating"
#define FLOATING_FPS 15
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

/* SDL2's SDL_WindowEvent (SDL_events.h), the start of the 56-byte SDL_Event union */
struct sdl2_window_event {
    unsigned type, timestamp, window_id;
    unsigned char event, padding1, padding2, padding3;
    int data1, data2;
};
#define SDL2_EVENT_SIZE 56
#define SDL2_WINDOWEVENT 0x200
#define SDL2_WINDOWEVENT_SHOWN 1
#define SDL2_WINDOWEVENT_HIDDEN 2

typedef int (*poll_fn)(void *event);
typedef unsigned (*window_id_fn)(void *window);
static poll_fn real_poll;
static unsigned game_window;      /* the engine's window (SDL id), known after its first swap; 0 = do nothing */
static long long hidden_checked_ns;
static int engine_hidden;         /* what the engine was told last */

static void learn_window(void *window) {
    const char *s = getenv("BARDROID_HIDDEN_PAUSE");
    /* SDL_GetWindowWMInfo exists in SDL2 only: SDL3's events look different */
    if ((s && s[0] == '0') || !dlsym(RTLD_DEFAULT, "SDL_GetWindowWMInfo")) return;
    window_id_fn id = (window_id_fn) dlsym(RTLD_DEFAULT, "SDL_GetWindowID");
    if (id) game_window = id(window);
}

int SDL_PollEvent(void *event) {
    if (!real_poll) real_poll = (poll_fn) dlsym(RTLD_NEXT, "SDL_PollEvent");
    if (event && game_window) {
        long long now = now_ns();
        if (now - hidden_checked_ns >= 500000000LL) {
            hidden_checked_ns = now;
            int hidden = access(HIDDEN_FLAG, F_OK) == 0 || access(CATCHUP_FLAG, F_OK) == 0;
            if (hidden != engine_hidden) {
                engine_hidden = hidden;
                unsigned char *b = (unsigned char *) event;
                for (int i = 0; i < SDL2_EVENT_SIZE; i++) b[i] = 0;
                struct sdl2_window_event *w = (struct sdl2_window_event *) event;
                w->type = SDL2_WINDOWEVENT;
                w->window_id = game_window;
                w->event = hidden ? SDL2_WINDOWEVENT_HIDDEN : SDL2_WINDOWEVENT_SHOWN;
                return 1;
            }
        }
    }
    return real_poll(event);
}

static long long floating_checked_ns;
static int floating;

void SDL_GL_SwapWindow(void *window) {
    if (!real_swap) {
        real_swap = (swap_fn) dlsym(RTLD_NEXT, "SDL_GL_SwapWindow");
        learn_window(window);
    }
    if (interval_ns < 0) interval_ns = read_interval();
    real_swap(window);
    long long now = now_ns();
    if (now - floating_checked_ns >= 500000000LL) {
        floating_checked_ns = now;
        floating = access(FLOATING_FLAG, F_OK) == 0;
    }
    long long interval = interval_ns;
    if (floating && interval < 1000000000LL / FLOATING_FPS) interval = 1000000000LL / FLOATING_FPS;
    if (interval == 0) return;
    if (next_ns == 0) next_ns = now;
    next_ns += interval;   /* when this frame's slot ends */
    if (now >= next_ns) {     /* the frame took the whole slot or more: no sleep, pace from here */
        next_ns = now;
        return;
    }
    struct timespec until = { (long) (next_ns / 1000000000LL), (long) (next_ns % 1000000000LL) };
    while (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &until, 0) == EINTR) {}
}
