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
        return;
    }
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
    real_swap(window);
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
 * neither BARDROID_FBO_UNCOMPRESS=1 nor BARDROID_TEX_ZERO=1 the dlsym wrapper only passes every call on to glibc's.
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

static void teximage2d_wrap(GLenum target, GLint level, GLint internal, GLsizei w, GLsizei h, GLint border, GLenum format,
                            GLenum type, const void *pixels) {
    void *zero = 0;
    if (!pixels && target == GL_TEXTURE_2D && level == 0 && (internal == GL_RGBA || internal == GL_RGBA8)
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
    gl_get_integerv = (void (*)(GLenum, GLint *)) real_getproc("glGetIntegerv");
    gl_bind_texture = (void (*)(GLenum, GLuint)) real_getproc("glBindTexture");
    gl_get_tex_level_parameteriv = (void (*)(GLenum, GLint, GLenum, GLint *)) real_getproc("glGetTexLevelParameteriv");
    gl_tex_image_2d = (void (*)(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void *))
        real_getproc("glTexImage2D");
}

/* glXGetProcAddress(ARB) as the engine gets it: the functions above wrapped, the rest as they are */
static void *glx_getproc_wrap(const char *proc) {
    void *p = real_getproc ? real_getproc(proc) : 0;
    if (!p || !proc) return p;
    if (tex_zero && same(proc, "glTexImage2D")) {
        gl_lookups();
        say("[pace] new textures start as zeros (BARDROID_TEX_ZERO)\n");
        return (void *) teximage2d_wrap;
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
    }
    if ((!fbo_uncompress && !tex_zero) || !symbol || handle == RTLD_NEXT || handle == RTLD_DEFAULT
        || !(same(symbol, "glXGetProcAddressARB") || same(symbol, "glXGetProcAddress")))
        __attribute__((musttail)) return glibc_dlsym(handle, symbol);
    void *p = glibc_dlsym(handle, symbol);
    if (!p) return p;
    real_getproc = (getproc_fn) p;
    return (void *) glx_getproc_wrap;
}
