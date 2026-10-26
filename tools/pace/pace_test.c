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
    printf("%s\n", fails ? "FAILED" : "ALL PASS");
    fflush(0);
}
