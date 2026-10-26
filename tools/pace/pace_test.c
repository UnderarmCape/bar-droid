/*
 * Test of libbardroid_pace.so's hidden-window events, run in the device's container without a display
 * (tools/pace-test.ps1 builds both and runs it):
 *   SDL_VIDEODRIVER=dummy LD_PRELOAD=<pace .so>:<this .so> perl -e 1
 * Its constructor loads SDL2, makes a window, swaps once (the pace library learns the window), then creates and
 * removes /tmp/bardroid-hidden and checks that SDL_PollEvent hands out SDL2's HIDDEN, then SHOWN window event for that
 * window. Prints PASS/FAIL lines. Built like pace.c: no libc headers, symbols resolved at load time.
 */
extern void *dlopen(const char *file, int mode);
extern void *dlsym(void *handle, const char *symbol);
extern int printf(const char *format, ...);
extern int fflush(void *stream);
extern int usleep(unsigned usec);
extern int open(const char *path, int flags, ...);
extern int close(int fd);
extern int unlink(const char *path);
extern int *__errno_location(void);
struct timespec { long tv_sec; long tv_nsec; };
extern int clock_gettime(int clock, struct timespec *ts);
extern int clock_nanosleep(int clock, int flags, const struct timespec *request, struct timespec *remain);
#define RTLD_NOW 2
#define RTLD_GLOBAL 0x100
#define RTLD_DEFAULT ((void *) 0)
#define O_WRONLY 1
#define O_CREAT 0100
#define SDL_INIT_VIDEO 0x20
#define SDL_WINDOWEVENT 0x200

struct window_event {
    unsigned type, timestamp, window_id;
    unsigned char event, padding1, padding2, padding3;
    int data1, data2;
};
union sdl_event { unsigned type; struct window_event window; unsigned char padding[56]; };

static int fails;

static void check(const char *what, int ok) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) fails++;
}

/* polls for up to 1.5 s and returns the first window event the pace library made (type 0x200 with the given id) */
static int wait_window_event(int (*poll)(void *), unsigned id, unsigned char *event) {
    union sdl_event e;
    for (int i = 0; i < 150; i++) {
        while (poll(&e)) {
            if (e.type == SDL_WINDOWEVENT && e.window.window_id == id && (e.window.event == 1 || e.window.event == 2)) {
                *event = e.window.event;
                return 1;
            }
        }
        usleep(10000);
    }
    return 0;
}

__attribute__((constructor)) static void pace_test(void) {
    if (!dlopen("libSDL2-2.0.so.0", RTLD_NOW | RTLD_GLOBAL)) { printf("FAIL no libSDL2\n"); return; }
    int (*init)(unsigned) = (int (*)(unsigned)) dlsym(RTLD_DEFAULT, "SDL_Init");
    void *(*create)(const char *, int, int, int, int, unsigned) =
            (void *(*)(const char *, int, int, int, int, unsigned)) dlsym(RTLD_DEFAULT, "SDL_CreateWindow");
    unsigned (*window_id)(void *) = (unsigned (*)(void *)) dlsym(RTLD_DEFAULT, "SDL_GetWindowID");
    void (*swap)(void *) = (void (*)(void *)) dlsym(RTLD_DEFAULT, "SDL_GL_SwapWindow");     /* the pace library's */
    int (*poll)(void *) = (int (*)(void *)) dlsym(RTLD_DEFAULT, "SDL_PollEvent");           /* the pace library's */
    void *pace_poll = dlsym(dlopen("libbardroid_pace.so", RTLD_NOW), "SDL_PollEvent");
    check("SDL_PollEvent resolves to the pace library", poll && poll == pace_poll);
    if (!init || !create || !window_id || !swap || !poll || init(SDL_INIT_VIDEO) != 0) { printf("FAIL SDL setup\n"); return; }
    void *win = create("pace test", 0, 0, 64, 64, 0);
    unsigned id = win ? window_id(win) : 0;
    check("window made", id != 0);
    swap(win);
    union sdl_event e;
    while (poll(&e)) {}   /* SDL's own events of the new window */

    unsigned char ev = 0;
    check("no event without the flag", !wait_window_event(poll, id, &ev));
    int fd = open("/tmp/bardroid-hidden", O_WRONLY | O_CREAT, 0600);
    close(fd);
    check("flag set: HIDDEN (2) for the game window", wait_window_event(poll, id, &ev) && ev == 2);
    check("then nothing more", !wait_window_event(poll, id, &ev));
    unlink("/tmp/bardroid-hidden");
    check("flag gone: SHOWN (1)", wait_window_event(poll, id, &ev) && ev == 1);

    /* the ioctl answer: the sync-file export fails with ENOTTY, anything else reaches the kernel (EBADF on fd -1) */
    int (*io)(int, unsigned long, ...) = (int (*)(int, unsigned long, ...)) dlsym(RTLD_DEFAULT, "ioctl");
    long arg = 0;
    int rc = io(-1, 0xc0086202UL, &arg);
    check("DMA_BUF_IOCTL_EXPORT_SYNC_FILE: -1, ENOTTY", rc == -1 && *__errno_location() == 25);
    rc = io(-1, 0x5401UL, &arg);   /* TCGETS */
    check("another ioctl goes through (EBADF)", rc == -1 && *__errno_location() == 9);

    /* how long nine plain 33.3 ms sleeps take here (a dozing phone wakes late: the cap cannot be more exact) */
    struct timespec t0, t1, nap = { 0, 33333333 };
    clock_gettime(1, &t0);
    for (int i = 0; i < 9; i++) clock_nanosleep(1, 0, &nap, 0);
    clock_gettime(1, &t1);
    long plain = (t1.tv_sec - t0.tv_sec) * 1000 + (t1.tv_nsec - t0.tv_nsec) / 1000000;
    printf("     9 plain sleeps of 33.3 ms: %ld ms\n", plain);

    /* the frame cap (BARDROID_FPS unset: 30): ten swaps take nine frame slots */
    swap(win);
    clock_gettime(1, &t0);
    for (int i = 0; i < 9; i++) swap(win);
    clock_gettime(1, &t1);
    long ms = (t1.tv_sec - t0.tv_sec) * 1000 + (t1.tv_nsec - t0.tv_nsec) / 1000000;
    printf("     9 frames in %ld ms\n", ms);
    /* never faster than 30 fps; no slower than plain sleeps of a frame each, plus 10 ms a frame (an awake phone wakes on
       time: 300 ms; a dozing one wakes ~20 ms late, which the cap cannot beat) */
    check("frame cap: 30 fps at most, as exact as this phone's sleeps", ms >= 290 && ms <= plain + 90);

    /* the floating window: with /tmp/bardroid-floating the cap is 15 fps (checked twice a second) */
    fd = open("/tmp/bardroid-floating", O_WRONLY | O_CREAT, 0600);
    close(fd);
    usleep(600000);
    swap(win);   /* sees the flag */
    clock_gettime(1, &t0);
    for (int i = 0; i < 6; i++) swap(win);
    clock_gettime(1, &t1);
    unlink("/tmp/bardroid-floating");
    ms = (t1.tv_sec - t0.tv_sec) * 1000 + (t1.tv_nsec - t0.tv_nsec) / 1000000;
    printf("     floating: 6 frames in %ld ms\n", ms);
    check("floating window: 15 fps (6 frames in 380-500 ms)", ms >= 380 && ms <= 500 + (plain - 300) * 6 / 9);

    printf("%s\n", fails ? "FAILED" : "ALL PASS");
    fflush(0);
}
