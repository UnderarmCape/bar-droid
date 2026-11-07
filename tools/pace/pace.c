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
 * A steady 30 fps still looked rough (Kailil, 2026-10-30: "the frame time or frame pacing is rough"): the X server shows
 * a new picture at the display's next vsync, and a cap on its own clock lands the pictures right around a vsync, so
 * they fell on either side of it: of 300 pictures at 30 fps on 60 Hz, 240 stayed on screen for 2 vsyncs, 30 for one and
 * 30 for three (the dev phone, a light scene). So the cap follows the display: the X server shares each vsync
 * (/tmp/bardroid-vsync, termux-x11 patch 0008), the swap waits for its slot on the vsync grid instead of the next frame
 * waiting after it (the time a frame takes no longer moves the swap), the X server holds a picture for the slot's
 * vsyncs at least (lorieMinHold: one a moment early waits; a late one has its margin afterwards), and a frame starts as
 * late as the slowest recent frame allows (start_late), so that waiting adds no input lag. No vsync file, or
 * BARDROID_PACE_VSYNC=0: the old cap, the sleep after the swap on the engine's own clock.
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
 * The screen's size follows the phone folding and unfolding (the X server resizes its screen and the game window with
 * it), but SDL2 reads a display's desktop mode and bounds once, at startup, and never updates them for a display that
 * stays connected. The engine takes its screen size from them (GR::UpdateScreenMatrices ssx/ssy, and the largest
 * window it allows): a game started folded and then unfolded kept the folded 1680x720 "screen" with a 1152x1044
 * window, its screen-space view offset by the difference (vpy=-324) and stretched (Kailil, 2026-10-27: "The aspect
 * ratio ... is different" in game). The display queries below answer with the game window's size, which is the screen's
 * (the window always fills it; there is no window manager), once the window exists. BARDROID_FIT_SCREEN=0 leaves
 * them alone.
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

/*
 * BARDROID_SWAP_LOG=1 (dev-env.sh): where the engine's buffer swap spends its time, every 10 s in launcher.log: the swap
 * in all, and of it the waits for the X server (xcb replies and Present's special events) and the GPU driver's ioctls
 * made from the swapping thread; the rest is Mesa itself (flushing, waiting for its driver thread). The engine's own
 * profiler only knows the swap as one block ("Misc::SwapBuffers", 11-13% of a late 8v8's real time on the dev phone).
 */
static long long now_ns(void);
static void say(const char *s);
extern int snprintf(char *s, unsigned long n, const char *format, ...);
static void gl_count_text(char *out, unsigned long n, long long frames);
extern unsigned long pthread_self(void);
static int swap_log = -1;            /* -1: not read yet */
static volatile int in_swap;
static unsigned long swap_thread;
static long long swap_ns_sum, swap_xcb_ns, swap_ioctl_ns, swap_log_at;
static int swap_frames, swap_ioctls;
#define SWAP_TIMED (swap_log > 0 && in_swap && pthread_self() == swap_thread)

typedef void *(*xcb_reply_fn)(void *c, unsigned int request, void **e);
typedef void *(*xcb_special_fn)(void *c, void *se);
static xcb_reply_fn real_xcb_wait_for_reply;
static xcb_special_fn real_xcb_wait_for_special_event;
void *xcb_wait_for_reply(void *c, unsigned int request, void **e) {
    if (!real_xcb_wait_for_reply) real_xcb_wait_for_reply = (xcb_reply_fn) dlsym(RTLD_NEXT, "xcb_wait_for_reply");
    if (!SWAP_TIMED) return real_xcb_wait_for_reply(c, request, e);
    long long t = now_ns();
    void *r = real_xcb_wait_for_reply(c, request, e);
    swap_xcb_ns += now_ns() - t;
    return r;
}
void *xcb_wait_for_special_event(void *c, void *se) {
    if (!real_xcb_wait_for_special_event)
        real_xcb_wait_for_special_event = (xcb_special_fn) dlsym(RTLD_NEXT, "xcb_wait_for_special_event");
    if (!SWAP_TIMED) return real_xcb_wait_for_special_event(c, se);
    long long t = now_ns();
    void *r = real_xcb_wait_for_special_event(c, se);
    swap_xcb_ns += now_ns() - t;
    return r;
}

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
    if (!SWAP_TIMED) return real_ioctl(fd, request, arg);
    long long t = now_ns();
    int r = real_ioctl(fd, request, arg);
    swap_ioctl_ns += now_ns() - t;
    swap_ioctls++;
    return r;
}

/*
 * proot's stops on the X connection (docs/CONTAINER-COST.md). proot's seccomp filter stops the engine for every
 * recvmsg and sendmsg (it translates Unix socket addresses and fakes netlink sockets with them), and libxcb reads and
 * writes the X connection with exactly those two: in a late 8v8 on the dev phone the main thread spent 1.4 % of its
 * time stopped by proot, a third of it in recvmsg on the X socket. On a connected Unix stream socket and without an
 * address (the X connection) proot has nothing to do in either call, and two calls its filter lets through do the
 * same: recvmsg -> recvmmsg with one message (passed file descriptors arrive as before), sendmsg without control data
 * -> writev (the X requests; one with descriptors to pass keeps sendmsg). Any other socket, an address or flags keep
 * their own call. BARDROID_SOCKET_TRAPS=1 leaves both alone.
 */
struct bd_iovec { void *base; unsigned long len; };
struct bd_msghdr { void *name; unsigned int namelen; struct bd_iovec *iov; unsigned long iovlen; void *control;
                   unsigned long controllen; int flags; };
struct bd_mmsghdr { struct bd_msghdr hdr; unsigned int len; };
extern long syscall(long number, ...);
#define BD_SYS_writev 66
#define BD_SYS_getsockopt 209
#define BD_SYS_sendmsg 211
#define BD_SYS_recvmsg 212
#define BD_SYS_recvmmsg 243
static int socket_traps = -1;   /* -1: not read yet */
static int unix_stream(int fd) {
    if (socket_traps < 0) {
        const char *s = getenv("BARDROID_SOCKET_TRAPS");
        socket_traps = s && s[0] == '1';
    }
    if (socket_traps) return 0;
    int v = 0;
    unsigned int l = sizeof v;
    if (syscall(BD_SYS_getsockopt, fd, 1 /* SOL_SOCKET */, 39 /* SO_DOMAIN */, &v, &l) || v != 1 /* AF_UNIX */) return 0;
    l = sizeof v;
    return !syscall(BD_SYS_getsockopt, fd, 1, 3 /* SO_TYPE */, &v, &l) && v == 1 /* SOCK_STREAM */;
}
typedef long (*recvmsg_fn)(int fd, struct bd_msghdr *msg, int flags);
typedef long (*sendmsg_fn)(int fd, const struct bd_msghdr *msg, int flags);
static recvmsg_fn real_recvmsg;
static sendmsg_fn real_sendmsg;
long recvmsg(int fd, struct bd_msghdr *msg, int flags) {
    if (msg && !msg->name && unix_stream(fd)) {
        struct bd_mmsghdr m = { *msg, 0 };
        long r = syscall(BD_SYS_recvmmsg, fd, &m, 1, flags, (void *) 0);   /* (-1 and errno as recvmsg's) */
        if (r < 0) return r;
        *msg = m.hdr;   /* the lengths and flags the kernel wrote back */
        return m.len;
    }
    if (!real_recvmsg) real_recvmsg = (recvmsg_fn) dlsym(RTLD_NEXT, "recvmsg");
    return real_recvmsg(fd, msg, flags);
}
long sendmsg(int fd, const struct bd_msghdr *msg, int flags) {
    if (msg && !msg->name && !msg->controllen && !flags && msg->iovlen <= 1024 && unix_stream(fd))
        return syscall(BD_SYS_writev, fd, msg->iov, (int) msg->iovlen);
    if (!real_sendmsg) real_sendmsg = (sendmsg_fn) dlsym(RTLD_NEXT, "sendmsg");
    return real_sendmsg(fd, msg, flags);
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
typedef void (*window_size_fn)(void *window, int *w, int *h);
static poll_fn real_poll;
static unsigned game_window;      /* the engine's window (SDL id), known after its first swap; 0 = do nothing */
static long long hidden_checked_ns;
static int engine_hidden;         /* what the engine was told last */
static int fit_screen;             /* answer display queries with the window's size (SDL2, BARDROID_FIT_SCREEN) */
static void *screen_window;       /* the window of the engine's last swap */
static window_size_fn window_size;

static void learn_window(void *window) {
    /* SDL_GetWindowWMInfo exists in SDL2 only: SDL3's events and structures look different */
    if (!dlsym(RTLD_DEFAULT, "SDL_GetWindowWMInfo")) return;
    const char *f = getenv("BARDROID_FIT_SCREEN");
    window_size = (window_size_fn) dlsym(RTLD_DEFAULT, "SDL_GetWindowSize");
    fit_screen = !(f && f[0] == '0') && window_size;
    const char *s = getenv("BARDROID_HIDDEN_PAUSE");
    if (s && s[0] == '0') return;
    window_id_fn id = (window_id_fn) dlsym(RTLD_DEFAULT, "SDL_GetWindowID");
    if (id) game_window = id(window);
}

/* SDL2's SDL_DisplayMode and SDL_Rect */
struct sdl2_display_mode { unsigned format; int w, h, refresh_rate; void *driverdata; };
struct sdl2_rect { int x, y, w, h; };
typedef int (*display_mode_fn)(int index, struct sdl2_display_mode *mode);
typedef int (*display_rect_fn)(int index, struct sdl2_rect *rect);

/* the screen as it is now: the game window's size (0 before the engine's first frame) */
static int screen_size(int *w, int *h) {
    *w = *h = 0;
    if (!screen_window) return 0;
    window_size(screen_window, w, h);
    return *w > 0 && *h > 0;
}

static int fit_mode(display_mode_fn real, int index, struct sdl2_display_mode *mode) {
    int r = real(index, mode), w, h;
    if (r == 0 && mode && screen_size(&w, &h)) { mode->w = w; mode->h = h; }
    return r;
}

static int fit_rect(display_rect_fn real, int index, struct sdl2_rect *rect) {
    int r = real(index, rect), w, h;
    if (r == 0 && rect && screen_size(&w, &h)) { rect->x = 0; rect->y = 0; rect->w = w; rect->h = h; }
    return r;
}

static display_mode_fn real_desktop_mode, real_current_mode;
static display_rect_fn real_bounds, real_usable_bounds;

int SDL_GetDesktopDisplayMode(int index, struct sdl2_display_mode *mode) {
    if (!real_desktop_mode) real_desktop_mode = (display_mode_fn) dlsym(RTLD_NEXT, "SDL_GetDesktopDisplayMode");
    return fit_mode(real_desktop_mode, index, mode);
}

int SDL_GetCurrentDisplayMode(int index, struct sdl2_display_mode *mode) {
    if (!real_current_mode) real_current_mode = (display_mode_fn) dlsym(RTLD_NEXT, "SDL_GetCurrentDisplayMode");
    return fit_mode(real_current_mode, index, mode);
}

int SDL_GetDisplayBounds(int index, struct sdl2_rect *rect) {
    if (!real_bounds) real_bounds = (display_rect_fn) dlsym(RTLD_NEXT, "SDL_GetDisplayBounds");
    return fit_rect(real_bounds, index, rect);
}

int SDL_GetDisplayUsableBounds(int index, struct sdl2_rect *rect) {
    if (!real_usable_bounds) real_usable_bounds = (display_rect_fn) dlsym(RTLD_NEXT, "SDL_GetDisplayUsableBounds");
    return fit_rect(real_usable_bounds, index, rect);
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

/* The display's vsync, shared by the X server (patch 0008): [0] the last one, [1] the time between two (ns) */
#define VSYNC_FILE "/tmp/bardroid-vsync"
#define VSYNC_STALE_NS 200000000LL
extern int open(const char *path, int flags, ...);
extern int close(int fd);
extern void *mmap(void *addr, unsigned long len, int prot, int flags, int fd, long off);
extern long lseek(int fd, long offset, int whence);
static volatile long long *vsync;
static int before_swap;

static long read_number(const char *name, long fallback) {
    const char *s = getenv(name);
    if (!s || !*s) return fallback;
    long v = 0;
    while (*s >= '0' && *s <= '9') v = v * 10 + (*s++ - '0');
    return v;
}

/* Tried until it works: the X server makes the file at its first vsync (none while the phone's screen is off), empty
   for a moment (a read of a map past the end of a file faults). BARDROID_VSYNC_FILE: tools/pace-test.ps1's own file. */
static void pace_setup(void) {
    if (read_number("BARDROID_PACE_VSYNC", 1) == 0) return;
    const char *path = getenv("BARDROID_VSYNC_FILE");
    int fd = open(path ? path : VSYNC_FILE, 2 /* O_RDWR */);
    if (fd < 0) return;
    void *m = lseek(fd, 0, 2 /* SEEK_END */) < 4096 ? (void *) -1L
        : mmap(0, 4096, 3 /* PROT_READ | PROT_WRITE */, 1 /* MAP_SHARED */, fd, 0);
    close(fd);
    if (m != (void *) -1L) { vsync = m; before_swap = 1; }
}

static void sleep_until(long long when) {
    struct timespec until = { (long) (when / 1000000000LL), (long) (when % 1000000000LL) };
    while (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &until, 0) == EINTR) {}
}

static long long slot_ns;   /* this frame's slot: the cap's interval, or the nearest whole number of vsyncs */
static long long pace_sleep_ns;   /* (BARDROID_SWAP_LOG: the cap's waits and the frames that came too late for one) */
static int pace_late_frames;

static void pace(long long interval) {
    long long now = now_ns();
    if (next_ns == 0) next_ns = now;
    long long t = vsync ? vsync[0] : 0, p = vsync ? vsync[1] : 0;
    slot_ns = interval;
    if (p > 0 && now - t < VSYNC_STALE_NS) {     /* on the display's own grid: every Nth vsync */
        long long ticks = (interval + p / 2) / p;
        if (ticks < 1) ticks = 1;
        vsync[2] = ticks;      /* the X server holds a picture that long */
        vsync[10] = t;
        slot_ns = ticks * p;
        next_ns += slot_ns;
        long long e = (next_ns - t) % p;
        if (e > p / 2) e -= p;
        else if (e < -p / 2) e += p;
        next_ns -= e;
    } else {
        next_ns += interval;   /* when this frame's slot ends */
    }
    if (now >= next_ns) {     /* the frame took the whole slot or more: no sleep, pace from here */
        next_ns = now;
        pace_late_frames++;
        return;
    }
    pace_sleep_ns += next_ns - now;
    sleep_until(next_ns);
}

/*
 * A late start: a frame that starts right after the last swap and then waits for its slot shows input as old as that
 * wait. So the time after the swap is slept away, as much as the slowest recent frame leaves: the next frame then ends
 * just before its slot.
 */
#define LATE_MARGIN_NS 4000000LL
#define WORK_PEAK_DECAY 64        /* the slowest recent frame fades by 1/64 a frame (half in ~1.5 s at 30 fps) */
static long long frame_start_ns, work_peak_ns;
static int late_start = -1;

static void frame_ended(void) {
    if (!frame_start_ns) return;
    long long work = now_ns() - frame_start_ns;
    if (work > slot_ns) work = slot_ns;   /* a slot's work leaves nothing to sleep; a stall of seconds would linger */
    work_peak_ns -= work_peak_ns / WORK_PEAK_DECAY;
    if (work > work_peak_ns) work_peak_ns = work;
}

static void start_late(void) {
    if (late_start < 0) late_start = read_number("BARDROID_PACE_LATE", 1) != 0;
    if (late_start) {
        long long wake = next_ns + slot_ns - work_peak_ns - LATE_MARGIN_NS;
        if (wake > now_ns()) sleep_until(wake);
    }
    frame_start_ns = now_ns();
}

void SDL_GL_SwapWindow(void *window) {
    if (!real_swap) {
        real_swap = (swap_fn) dlsym(RTLD_NEXT, "SDL_GL_SwapWindow");
        learn_window(window);
    }
    if (fit_screen) screen_window = window;
    if (interval_ns < 0) interval_ns = read_interval();
    long long now = now_ns();
    if (now - floating_checked_ns >= 500000000LL) {
        floating_checked_ns = now;
        floating = access(FLOATING_FLAG, F_OK) == 0;
        if (!before_swap) pace_setup();
    }
    long long interval = interval_ns;
    if (floating && interval < 1000000000LL / FLOATING_FPS) interval = 1000000000LL / FLOATING_FPS;
    if (before_swap && interval) {
        frame_ended();
        pace(interval);
    }
    if (swap_log < 0) swap_log = read_number("BARDROID_SWAP_LOG", 0) != 0;
    if (swap_log) {
        swap_thread = pthread_self();
        long long t = now_ns();
        in_swap = 1;
        real_swap(window);
        in_swap = 0;
        long long done = now_ns();
        swap_ns_sum += done - t;
        swap_frames++;
        if (!swap_log_at) swap_log_at = done;
        if (done - swap_log_at >= 10000000000LL) {
            char line[512], counts[256];
            long long n = swap_frames ? swap_frames : 1;
            gl_count_text(counts, sizeof counts, n);
            snprintf(line, sizeof line, "[pace] swap over %d frames: %lld us each, of it X server waits %lld us, GPU "
                "driver ioctls %lld us (%lld a frame), Mesa's own %lld us; the cap waited %lld us a frame, %d frames "
                "too late for their slot%s\n", swap_frames, swap_ns_sum / n / 1000,
                swap_xcb_ns / n / 1000, swap_ioctl_ns / n / 1000, (long long) swap_ioctls / n,
                (swap_ns_sum - swap_xcb_ns - swap_ioctl_ns) / n / 1000, pace_sleep_ns / n / 1000, pace_late_frames,
                counts);
            say(line);
            swap_ns_sum = swap_xcb_ns = swap_ioctl_ns = pace_sleep_ns = 0;
            swap_frames = swap_ioctls = pace_late_frames = 0;
            swap_log_at = done;
        }
    } else {
        real_swap(window);
    }
    if (before_swap && interval) start_late();
    if (!before_swap && interval) pace(interval);
}

/*
 * Phones with 8 GB (BARDROID_FBO_UNCOMPRESS=1, set by launch-bar.sh with CompressTextures = 1): the engine's runtime
 * texture compression is the one client setting that brings a BAR game into an 8 GB phone (GPU memory ~2.75 -> ~2.45
 * GB, docs/HISTORY.md), but the engine also compresses two textures it later draws into, the unit icon atlas and the
 * projectile drawer's perlin noise, and their framebuffers fail ("FBO-TEXTURE-RENDER-ATLAS: None/Unsupported
 * textures/buffers attached!", icons as black squares; on Windows too: docs/upstream/recoil-compresstextures-fbo.md).
 * The engine loads GL through GLAD's own loader: dlopen("libGL.so.1"), dlsym(that, "glXGetProcAddressARB"), then every
 * function through it (no SDL_GL_GetProcAddress, and a dlsym on a handle passes by every LD_PRELOAD). So dlsym itself
 * is wrapped: asked for glXGetProcAddress(ARB), it hands back a wrapper that, for glFramebufferTexture2D(EXT), hands
 * back the wrapper below, which gives a compressed 2D texture uncompressed RGBA8 storage of the same size (every level
 * that has one) before it is attached. Its contents go, which is right for a texture about to be drawn into. With
 * none of BARDROID_FBO_UNCOMPRESS=1, BARDROID_TEX_ZERO=1 and BARDROID_TEX_LOG=1 the dlsym wrapper only passes every call
 * on to glibc's.
 */
typedef unsigned int GLenum;
typedef unsigned int GLuint;
typedef int GLint;
typedef int GLsizei;
#define GL_TEXTURE_2D 0x0DE1
#define GL_TEXTURE_BINDING_2D 0x8069
#define GL_TEXTURE_WIDTH 0x1000
#define GL_TEXTURE_HEIGHT 0x1001
#define GL_TEXTURE_COMPRESSED 0x86A1
#define GL_RGBA8 0x8058
#define GL_RGBA 0x1908
#define GL_UNSIGNED_BYTE 0x1401
extern long write(int fd, const void *buf, unsigned long n);

typedef void *(*getproc_fn)(const char *name);
typedef void (*fbtex2d_fn)(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level);
static getproc_fn real_getproc;
static fbtex2d_fn real_fbtex2d, real_fbtex2d_ext;
static void (*gl_get_integerv)(GLenum, GLint *);
static void (*gl_bind_texture)(GLenum, GLuint);
static void (*gl_get_tex_level_parameteriv)(GLenum, GLint, GLenum, GLint *);
static void (*gl_tex_image_2d)(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void *);
static int fbo_uncompress = -1;   /* -1: not read yet */
static int uncompressed_count;

static int same(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return *a == *b;
}

static void say(const char *s) {
    unsigned long n = 0;
    while (s[n]) n++;
    write(2, s, n);
}

static void uncompress_target(GLenum textarget, GLuint texture) {
    if (!texture || textarget != GL_TEXTURE_2D || !gl_tex_image_2d || !gl_get_integerv || !gl_bind_texture
        || !gl_get_tex_level_parameteriv) return;
    GLint before = 0;
    gl_get_integerv(GL_TEXTURE_BINDING_2D, &before);
    gl_bind_texture(GL_TEXTURE_2D, texture);
    int changed = 0;
    for (GLint level = 0; level < 16; level++) {
        GLint compressed = 0, w = 0, h = 0;
        gl_get_tex_level_parameteriv(GL_TEXTURE_2D, level, GL_TEXTURE_WIDTH, &w);
        gl_get_tex_level_parameteriv(GL_TEXTURE_2D, level, GL_TEXTURE_HEIGHT, &h);
        if (w <= 0 || h <= 0) break;
        gl_get_tex_level_parameteriv(GL_TEXTURE_2D, level, GL_TEXTURE_COMPRESSED, &compressed);
        if (!compressed) break;
        gl_tex_image_2d(GL_TEXTURE_2D, level, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
        changed = 1;
    }
    gl_bind_texture(GL_TEXTURE_2D, (GLuint) before);
    if (changed && uncompressed_count++ < 8) say("[pace] a compressed texture attached to a framebuffer: stored uncompressed\n");
}

static void fbtex2d_wrap(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level) {
    uncompress_target(textarget, texture);
    real_fbtex2d(target, attachment, textarget, texture, level);
}

static void fbtex2d_ext_wrap(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level) {
    uncompress_target(textarget, texture);
    real_fbtex2d_ext(target, attachment, textarget, texture, level);
}

/*
 * A new texture starts as whatever its recycled GPU buffer last held: Mesa reuses freed buffers as they are (22 of 60
 * new textures on the dev phone, 2026-10-31), where a PC's driver hands out zeros, and BAR's widgets draw into new
 * textures without clearing them (its unit-groups panel as pink and white noise). So a plain RGBA texture made with no
 * data is made with zeros (BARDROID_TEX_ZERO=1, launch-bar.sh), with the upload settings at their defaults meanwhile: a
 * bound pixel buffer would make the pointer an offset, the others would read past the zeros.
 */
#define GL_UNPACK_ROW_LENGTH 0x0CF2
#define GL_UNPACK_SKIP_ROWS 0x0CF3
#define GL_UNPACK_SKIP_PIXELS 0x0CF4
#define GL_PIXEL_UNPACK_BUFFER 0x88EC
#define GL_PIXEL_UNPACK_BUFFER_BINDING 0x88EF
#define TEX_ZERO_MAX_SIDE 4096
extern void *calloc(unsigned long count, unsigned long size);
extern void free(void *p);
static void (*gl_pixel_storei)(GLenum, GLint);
static void (*gl_bind_buffer)(GLenum, GLuint);
static int tex_zero = -1;   /* -1: not read yet */

/*
 * BARDROID_TEX_LOG=1 (a developer's switch, dev-env.sh): every texture of 64x64 or more the engine makes, its size and
 * formats, to stderr (launcher.log), to see which one shows a recycled buffer (DELIVERY.md, the white lattice after
 * first person). Off, nothing changes.
 */
#define TEX_LOG_MIN (64 * 64)
extern int snprintf(char *s, unsigned long n, const char *format, ...);
static int tex_log = -1;   /* -1: not read yet */
static void (*real_tex_storage_2d)(GLenum, GLsizei, GLenum, GLsizei, GLsizei);
static void (*real_compressed_tex_image_2d)(GLenum, GLint, GLenum, GLsizei, GLsizei, GLint, GLsizei, const void *);

static void tex_said(const char *what, GLenum target, GLint internal, GLsizei w, GLsizei h, unsigned format,
                     unsigned type, int data) {
    if (tex_log != 1 || (long) w * (long) h < TEX_LOG_MIN) return;
    char line[160];
    snprintf(line, sizeof line, "[pace] %s %dx%d target 0x%x internal 0x%x format 0x%x type 0x%x %s\n", what, (int) w,
             (int) h, target, (unsigned) internal, format, type, data ? "with data" : "empty");
    say(line);
}

static void texstorage2d_wrap(GLenum target, GLsizei levels, GLenum internal, GLsizei w, GLsizei h) {
    tex_said("glTexStorage2D", target, (GLint) internal, w, h, (unsigned) levels, 0, 0);
    real_tex_storage_2d(target, levels, internal, w, h);
}

/*
 * And with BARDROID_TEX_LOG=1 every buffer of 64 KB or more the engine gives storage to (glBufferData, glBufferStorage,
 * the named forms): in a 1v1 skirmish on the dev phone the GPU driver held 2.0 GB, its textures ~0.5 GB (2026-11-04).
 */
#define BUF_LOG_MIN (64L * 1024)
typedef long GLsizeiptr;
static void (*real_buffer_data)(GLenum, GLsizeiptr, const void *, GLenum);
static void (*real_buffer_storage)(GLenum, GLsizeiptr, const void *, unsigned);
static void (*real_named_buffer_data)(GLuint, GLsizeiptr, const void *, GLenum);
static void (*real_named_buffer_storage)(GLuint, GLsizeiptr, const void *, unsigned);

static void buf_said(const char *what, unsigned target, GLsizeiptr size, unsigned usage) {
    if (tex_log != 1 || size < BUF_LOG_MIN) return;
    char line[128];
    snprintf(line, sizeof line, "[pace] %s %ld bytes target 0x%x usage 0x%x\n", what, size, target, usage);
    say(line);
}
static void bufferdata_wrap(GLenum target, GLsizeiptr size, const void *data, GLenum usage) {
    buf_said("glBufferData", target, size, usage);
    real_buffer_data(target, size, data, usage);
}
static void bufferstorage_wrap(GLenum target, GLsizeiptr size, const void *data, unsigned flags) {
    buf_said("glBufferStorage", target, size, flags);
    real_buffer_storage(target, size, data, flags);
}
static void namedbufferdata_wrap(GLuint buffer, GLsizeiptr size, const void *data, GLenum usage) {
    buf_said("glNamedBufferData", 0, size, usage);
    real_named_buffer_data(buffer, size, data, usage);
}
static void namedbufferstorage_wrap(GLuint buffer, GLsizeiptr size, const void *data, unsigned flags) {
    buf_said("glNamedBufferStorage", 0, size, flags);
    real_named_buffer_storage(buffer, size, data, flags);
}

/*
 * The map's ground tiles (BARDROID_TEX_ZERO, phones): when the camera jumps (first person ending, 2026-11-02) a frame
 * showed rows of white blocks over the map and the minimap. The engine fills each 128x128 DXT1 tile through one pixel
 * buffer, mapped unsynchronized for the next tile right after the last one's upload (SMFGroundTextures.cpp
 * LoadSquareTexture; VBO::New of the same size keeps the buffer), and Mesa copies from a pixel buffer later, on the
 * GPU: a tile got another's bytes, or a recycled buffer's. So a compressed texture from a pixel buffer is uploaded from
 * a copy of its bytes in memory, which the driver takes at once. With no data and no buffer: made with zeros.
 */
#define TEX_ZERO_MAX_BYTES (16L * 1024 * 1024)
#define GL_MAP_READ_BIT 0x0001
extern void *malloc(unsigned long size);
extern void *memcpy(void *to, const void *from, unsigned long n);
static void *(*gl_map_buffer_range)(GLenum, long, long, unsigned);
static unsigned char (*gl_unmap_buffer)(GLenum);
static int tile_copies;

static void compressedteximage2d_wrap(GLenum target, GLint level, GLenum internal, GLsizei w, GLsizei h, GLint border,
                                      GLsizei size, const void *data) {
    if (level == 0) tex_said("glCompressedTexImage2D", target, (GLint) internal, w, h, 0, 0, data != 0);
    GLint buffer = 0;
    if (tex_zero != 1 || size <= 0 || size > TEX_ZERO_MAX_BYTES || !gl_get_integerv) {
        real_compressed_tex_image_2d(target, level, internal, w, h, border, size, data);
        return;
    }
    gl_get_integerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &buffer);
    void *mem = buffer || !data ? (buffer ? malloc((unsigned long) size) : calloc((unsigned long) size, 1)) : 0;
    if (buffer && mem) {
        const void *bytes = gl_map_buffer_range && gl_unmap_buffer && gl_bind_buffer
            ? gl_map_buffer_range(GL_PIXEL_UNPACK_BUFFER, (long) data, (long) size, GL_MAP_READ_BIT) : 0;
        if (bytes) {
            memcpy(mem, bytes, (unsigned long) size);
            gl_unmap_buffer(GL_PIXEL_UNPACK_BUFFER);
            gl_bind_buffer(GL_PIXEL_UNPACK_BUFFER, 0);
            real_compressed_tex_image_2d(target, level, internal, w, h, border, size, mem);
            gl_bind_buffer(GL_PIXEL_UNPACK_BUFFER, (GLuint) buffer);
            free(mem);
            if (tile_copies++ == 0) say("[pace] compressed textures from a pixel buffer: uploaded from a copy\n");
            return;
        }
        free(mem);
        mem = 0;
    }
    real_compressed_tex_image_2d(target, level, internal, w, h, border, size, mem ? mem : data);
    if (mem) free(mem);
}

static void teximage2d_wrap(GLenum target, GLint level, GLint internal, GLsizei w, GLsizei h, GLint border, GLenum format,
                            GLenum type, const void *pixels) {
    void *zero = 0;
    if (level == 0) tex_said("glTexImage2D", target, internal, w, h, format, type, pixels != 0);
    if (tex_zero == 1 && !pixels && target == GL_TEXTURE_2D && level == 0 && (internal == GL_RGBA || internal == GL_RGBA8)
        && format == GL_RGBA && type == GL_UNSIGNED_BYTE && w > 0 && h > 0
        && w <= TEX_ZERO_MAX_SIDE && h <= TEX_ZERO_MAX_SIDE) zero = calloc((unsigned long) w * (unsigned long) h, 4);
    if (!zero) { gl_tex_image_2d(target, level, internal, w, h, border, format, type, pixels); return; }
    GLint buffer = 0, row = 0, skip_rows = 0, skip_pixels = 0;
    gl_get_integerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &buffer);
    gl_get_integerv(GL_UNPACK_ROW_LENGTH, &row);
    gl_get_integerv(GL_UNPACK_SKIP_ROWS, &skip_rows);
    gl_get_integerv(GL_UNPACK_SKIP_PIXELS, &skip_pixels);
    if (buffer) gl_bind_buffer(GL_PIXEL_UNPACK_BUFFER, 0);
    if (row) gl_pixel_storei(GL_UNPACK_ROW_LENGTH, 0);
    if (skip_rows) gl_pixel_storei(GL_UNPACK_SKIP_ROWS, 0);
    if (skip_pixels) gl_pixel_storei(GL_UNPACK_SKIP_PIXELS, 0);
    gl_tex_image_2d(target, level, internal, w, h, border, format, type, zero);
    if (buffer) gl_bind_buffer(GL_PIXEL_UNPACK_BUFFER, (GLuint) buffer);
    if (row) gl_pixel_storei(GL_UNPACK_ROW_LENGTH, row);
    if (skip_rows) gl_pixel_storei(GL_UNPACK_SKIP_ROWS, skip_rows);
    if (skip_pixels) gl_pixel_storei(GL_UNPACK_SKIP_PIXELS, skip_pixels);
    free(zero);
}

static void gl_lookups(void) {
    if (gl_tex_image_2d) return;
    gl_pixel_storei = (void (*)(GLenum, GLint)) real_getproc("glPixelStorei");
    gl_bind_buffer = (void (*)(GLenum, GLuint)) real_getproc("glBindBuffer");
    gl_map_buffer_range = (void *(*)(GLenum, long, long, unsigned)) real_getproc("glMapBufferRange");
    gl_unmap_buffer = (unsigned char (*)(GLenum)) real_getproc("glUnmapBuffer");
    gl_get_integerv = (void (*)(GLenum, GLint *)) real_getproc("glGetIntegerv");
    gl_bind_texture = (void (*)(GLenum, GLuint)) real_getproc("glBindTexture");
    gl_get_tex_level_parameteriv = (void (*)(GLenum, GLint, GLenum, GLint *)) real_getproc("glGetTexLevelParameteriv");
    gl_tex_image_2d = (void (*)(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void *))
        real_getproc("glTexImage2D");
}

#ifdef BARDROID_DEV_GL_COUNT
/*
 * A developer build only (tools/build-pace.py --dev: libbardroid_pace_dev.so, never in the APK; dev-env.sh points
 * LD_PRELOAD at it): the engine's draw calls and state binds counted, per drawn frame every 10 s in launcher.log (with
 * BARDROID_SWAP_LOG's line). Mesa's driver thread turns each into GPU commands: ~15 ms of its CPU a drawn frame in a
 * late 8v8 on the dev phone, and the swap waits for it. Each counted function is wrapped by a forwarder of eight
 * integer arguments (AArch64 and x86-64 pass them in registers; none of these takes a float). GL 1.1's own functions
 * are not looked up through glXGetProcAddress: exported here instead.
 */
typedef unsigned long long u64;
typedef void (*gl8_fn)(u64, u64, u64, u64, u64, u64, u64, u64);
static int gl_count = -1;
#define GLC_KINDS 6   /* draws, programs, textures, buffers, vertex arrays, framebuffers */
static const char *const glc_kind_name[GLC_KINDS] = { "draws", "programs", "textures", "buffers", "VAOs", "FBOs" };
static long long glc_counts[GLC_KINDS];
static const struct { const char *name; int kind; } glc_names[] = {
    { "glDrawArrays", 0 }, { "glDrawElements", 0 }, { "glDrawArraysInstanced", 0 }, { "glDrawElementsInstanced", 0 },
    { "glDrawElementsBaseVertex", 0 }, { "glDrawElementsInstancedBaseVertex", 0 }, { "glDrawRangeElements", 0 },
    { "glDrawArraysInstancedBaseInstance", 0 }, { "glDrawElementsInstancedBaseVertexBaseInstance", 0 },
    { "glMultiDrawArrays", 0 }, { "glMultiDrawElements", 0 }, { "glMultiDrawArraysIndirect", 0 },
    { "glMultiDrawElementsIndirect", 0 }, { "glDrawArraysIndirect", 0 }, { "glDrawElementsIndirect", 0 },
    { "glUseProgram", 1 }, { "glBindTexture", 2 }, { "glBindBuffer", 3 }, { "glBindBufferBase", 3 },
    { "glBindBufferRange", 3 }, { "glBindVertexArray", 4 }, { "glBindFramebuffer", 5 }, { "glBindFramebufferEXT", 5 },
};
#define GLC_N ((int) (sizeof glc_names / sizeof glc_names[0]))
static gl8_fn glc_real[GLC_N];
#define GLC_WRAP(i) static void glc_wrap##i(u64 a, u64 b, u64 c, u64 d, u64 e, u64 f, u64 g, u64 h) { \
    glc_counts[glc_names[i].kind]++; glc_real[i](a, b, c, d, e, f, g, h); }
GLC_WRAP(0) GLC_WRAP(1) GLC_WRAP(2) GLC_WRAP(3) GLC_WRAP(4) GLC_WRAP(5) GLC_WRAP(6) GLC_WRAP(7) GLC_WRAP(8) GLC_WRAP(9)
GLC_WRAP(10) GLC_WRAP(11) GLC_WRAP(12) GLC_WRAP(13) GLC_WRAP(14) GLC_WRAP(15) GLC_WRAP(16) GLC_WRAP(17) GLC_WRAP(18)
GLC_WRAP(19) GLC_WRAP(20) GLC_WRAP(21) GLC_WRAP(22)
static const gl8_fn glc_wraps[] = { glc_wrap0, glc_wrap1, glc_wrap2, glc_wrap3, glc_wrap4, glc_wrap5, glc_wrap6,
    glc_wrap7, glc_wrap8, glc_wrap9, glc_wrap10, glc_wrap11, glc_wrap12, glc_wrap13, glc_wrap14, glc_wrap15, glc_wrap16,
    glc_wrap17, glc_wrap18, glc_wrap19, glc_wrap20, glc_wrap21, glc_wrap22 };
typedef char glc_table_check[(sizeof glc_wraps / sizeof glc_wraps[0]) == GLC_N ? 1 : -1];

/* the counts per frame since the last call, as text (empty when not counting) */
static void gl_count_text(char *out, unsigned long n, long long frames) {
    out[0] = 0;
    if (gl_count <= 0 || frames <= 0) return;
    snprintf(out, n, "; per frame %lld %s, %lld %s, %lld %s, %lld %s, %lld %s, %lld %s", glc_counts[0] / frames,
        glc_kind_name[0], glc_counts[1] / frames, glc_kind_name[1], glc_counts[2] / frames, glc_kind_name[2],
        glc_counts[3] / frames, glc_kind_name[3], glc_counts[4] / frames, glc_kind_name[4], glc_counts[5] / frames,
        glc_kind_name[5]);
    for (int k = 0; k < GLC_KINDS; k++) glc_counts[k] = 0;
}

typedef void (*gl3_fn)(u64, u64, u64);
typedef void (*gl4_fn)(u64, u64, u64, u64);
static gl3_fn real_draw_arrays;
static gl4_fn real_draw_elements;
static void (*real_bind_texture)(u64, u64);
void glDrawArrays(u64 mode, u64 first, u64 count) {
    if (!real_draw_arrays) real_draw_arrays = (gl3_fn) dlsym(RTLD_NEXT, "glDrawArrays");
    glc_counts[0]++;
    real_draw_arrays(mode, first, count);
}
void glDrawElements(u64 mode, u64 count, u64 type, u64 indices) {
    if (!real_draw_elements) real_draw_elements = (gl4_fn) dlsym(RTLD_NEXT, "glDrawElements");
    glc_counts[0]++;
    real_draw_elements(mode, count, type, indices);
}
void glBindTexture(u64 target, u64 texture) {
    if (!real_bind_texture) real_bind_texture = (void (*)(u64, u64)) dlsym(RTLD_NEXT, "glBindTexture");
    glc_counts[2]++;
    real_bind_texture(target, texture);
}
#else
#define gl_count 0
static void gl_count_text(char *out, unsigned long n, long long frames) { (void) n; (void) frames; out[0] = 0; }
#endif

/* glXGetProcAddress(ARB) as the engine gets it: the functions above wrapped, the rest as they are */
static void *glx_getproc_wrap(const char *proc) {
    void *p = real_getproc ? real_getproc(proc) : 0;
    if (!p || !proc) return p;
#ifdef BARDROID_DEV_GL_COUNT
    if (gl_count < 0) gl_count = 1;
    for (int i = 0; i < GLC_N; i++) {
        if (same(proc, glc_names[i].name)) {
            glc_real[i] = (gl8_fn) p;
            return (void *) glc_wraps[i];
        }
    }
#endif
    if ((tex_zero || tex_log) && same(proc, "glTexImage2D")) {
        gl_lookups();
        if (tex_zero) say("[pace] new textures start as zeros (BARDROID_TEX_ZERO)\n");
        if (tex_log) say("[pace] textures of 128x128 or more logged (BARDROID_TEX_LOG)\n");
        return (void *) teximage2d_wrap;
    }
    if (tex_log && same(proc, "glTexStorage2D")) {
        real_tex_storage_2d = (void (*)(GLenum, GLsizei, GLenum, GLsizei, GLsizei)) p;
        return (void *) texstorage2d_wrap;
    }
    if (tex_log && (same(proc, "glBufferData") || same(proc, "glBufferDataARB"))) {
        real_buffer_data = (void (*)(GLenum, GLsizeiptr, const void *, GLenum)) p;
        return (void *) bufferdata_wrap;
    }
    if (tex_log && same(proc, "glBufferStorage")) {
        real_buffer_storage = (void (*)(GLenum, GLsizeiptr, const void *, unsigned)) p;
        return (void *) bufferstorage_wrap;
    }
    if (tex_log && same(proc, "glNamedBufferData")) {
        real_named_buffer_data = (void (*)(GLuint, GLsizeiptr, const void *, GLenum)) p;
        return (void *) namedbufferdata_wrap;
    }
    if (tex_log && same(proc, "glNamedBufferStorage")) {
        real_named_buffer_storage = (void (*)(GLuint, GLsizeiptr, const void *, unsigned)) p;
        return (void *) namedbufferstorage_wrap;
    }
    if ((tex_zero || tex_log) && same(proc, "glCompressedTexImage2D")) {
        gl_lookups();
        real_compressed_tex_image_2d = (void (*)(GLenum, GLint, GLenum, GLsizei, GLsizei, GLint, GLsizei, const void *)) p;
        return (void *) compressedteximage2d_wrap;
    }
    int ext = same(proc, "glFramebufferTexture2DEXT");
    if (!fbo_uncompress || (!ext && !same(proc, "glFramebufferTexture2D"))) return p;
    gl_lookups();
    if (ext) { real_fbtex2d_ext = (fbtex2d_fn) p; return (void *) fbtex2d_ext_wrap; }
    real_fbtex2d = (fbtex2d_fn) p;
    say("[pace] framebuffer textures: compressed ones stored uncompressed when attached (BARDROID_FBO_UNCOMPRESS)\n");
    return (void *) fbtex2d_wrap;
}

/* glibc's dlsym (2.34 and later in libc, before that in libdl; aarch64's and x86_64's first versions) */
extern void *dlvsym(void *handle, const char *symbol, const char *version);
typedef void *(*dlsym_fn)(void *handle, const char *symbol);
static dlsym_fn glibc_dlsym;

/* glibc's dlsym finds RTLD_NEXT's "next" from its caller's return address: every call that is not the GL lookup is a
   tail call (musttail), so glibc sees the real caller, not this library */
void *dlsym(void *handle, const char *symbol) {
    if (!glibc_dlsym) {
        glibc_dlsym = (dlsym_fn) dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.34");
        if (!glibc_dlsym) glibc_dlsym = (dlsym_fn) dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.17");
        if (!glibc_dlsym) glibc_dlsym = (dlsym_fn) dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.2.5");
        if (!glibc_dlsym) return 0;
    }
    if (fbo_uncompress < 0) {
        const char *v = getenv("BARDROID_FBO_UNCOMPRESS");
        fbo_uncompress = v && v[0] == '1';
        v = getenv("BARDROID_TEX_ZERO");
        tex_zero = v && v[0] == '1';
        v = getenv("BARDROID_TEX_LOG");
        tex_log = v && v[0] == '1';
    }
#ifdef BARDROID_DEV_GL_COUNT   /* (the dev build always wraps the GL lookup: its counters live there) */
    if (!symbol || handle == RTLD_NEXT || handle == RTLD_DEFAULT
#else
    if ((!fbo_uncompress && !tex_zero && !tex_log) || !symbol || handle == RTLD_NEXT || handle == RTLD_DEFAULT
#endif
        || !(same(symbol, "glXGetProcAddressARB") || same(symbol, "glXGetProcAddress")))
        __attribute__((musttail)) return glibc_dlsym(handle, symbol);
    void *p = glibc_dlsym(handle, symbol);
    if (!p) return p;
    real_getproc = (getproc_fn) p;
    return (void *) glx_getproc_wrap;
}
