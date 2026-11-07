/*
 * Test of libbardroid_pace.so's hidden-window events, run in the device's container without a display
 * (tools/pace-test.ps1 builds both and runs it):
 *   SDL_VIDEODRIVER=dummy BARDROID_VSYNC_FILE=<a file of its own> LD_PRELOAD=<pace .so>:<this .so> perl -e 1
 * Its constructor loads SDL2, makes a window, swaps once (the pace library learns the window), then creates and
 * removes /tmp/bardroid-hidden and checks that SDL_PollEvent hands out SDL2's HIDDEN, then SHOWN window event for that
 * window. Then the frame cap, and the cap on a vsync this test makes up in the X server's place. Prints PASS/FAIL
 * lines. Built like pace.c: no libc headers, symbols resolved at load time.
 */
extern void *dlopen(const char *file, int mode);
extern void *dlsym(void *handle, const char *symbol);
extern char *getenv(const char *name);
extern void *mmap(void *addr, unsigned long len, int prot, int flags, int fd, long off);
extern int ftruncate(int fd, long length);
extern int pthread_create(unsigned long *thread, const void *attr, void *(*run)(void *), void *arg);
extern int pthread_join(unsigned long thread, void **result);
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
#define RTLD_NEXT ((void *) -1L)
#define O_WRONLY 1
#define O_RDWR 2
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

static long long now_ns(void) {
    struct timespec t;
    clock_gettime(1, &t);
    return t.tv_sec * 1000000000LL + t.tv_nsec;
}

/* After the pace library in LD_PRELOAD, so its "real" swap: when a swap really happened (it sleeps on after it) */
static long long swap_ns;
static void (*sdl_swap)(void *);
void SDL_GL_SwapWindow(void *window) {
    if (!sdl_swap) sdl_swap = (void (*)(void *)) dlsym(RTLD_NEXT, "SDL_GL_SwapWindow");
    swap_ns = now_ns();
    sdl_swap(window);
}

/* In the X server's place: a 60 Hz vsync in the shared file */
#define VSYNC_PERIOD 16666667LL
static volatile long long *shared;
static volatile int writer_stop;
static long long grid_start;

static void *vsync_writer(void *unused) {
    (void) unused;
    long long t = grid_start;
    shared[1] = VSYNC_PERIOD;
    while (!writer_stop) {
        shared[0] = t;
        t += VSYNC_PERIOD;
        struct timespec until = { (long) (t / 1000000000LL), (long) (t % 1000000000LL) };
        clock_nanosleep(1, 1 /* TIMER_ABSTIME */, &until, 0);
    }
    return 0;
}

/* a frame's work: 5 ms, then the swap; the time the pace library slept after the swap, in ms */
static long work_and_swap(void (*swap)(void *), void *win) {
    struct timespec work = { 0, 5000000 };
    clock_nanosleep(1, 0, &work, 0);
    swap(win);
    return (long) ((now_ns() - swap_ns) / 1000000);
}

static void vsync_tests(void (*swap)(void *), void *win, long plain) {
    long slack_ns = (plain - 300) * 1000000 / 9;   /* how late this phone wakes */
    const char *file = getenv("BARDROID_VSYNC_FILE");
    int fd = file ? open(file, O_RDWR | O_CREAT, 0600) : -1;
    if (fd < 0) { check("BARDROID_VSYNC_FILE set and writable", 0); return; }
    usleep(600000);
    swap(win);
    check("an empty vsync file is left alone (no fault)", 1);
    ftruncate(fd, 4096);
    shared = (volatile long long *) mmap(0, 4096, 3, 1, fd, 0);
    close(fd);
    grid_start = now_ns();
    unsigned long writer;
    pthread_create(&writer, 0, vsync_writer, 0);
    usleep(600000);
    swap(win);   /* the library finds the file now: tried until it works */
    swap(win);

    int frames = 40, on_grid = 0, even = 0;
    long slept = 0;
    for (int i = 0; i < frames; i++) {
        long long last = swap_ns;
        slept = work_and_swap(swap, win);
        long long off = (swap_ns - grid_start) % VSYNC_PERIOD, gap = swap_ns - last;
        if (off < 4000000 + slack_ns) on_grid++;
        if (gap > 30000000 && gap < 37000000 + slack_ns) even++;
    }
    printf("     %d of %d swaps on a vsync, %d of them 33 ms apart, %ld ms slept after the last\n", on_grid, frames, even, slept);
    check("the swaps fall on the vsync grid", on_grid >= frames * 8 / 10);
    check("every 2nd vsync at 30 fps on 60 Hz", even >= frames * 8 / 10);
    check("the X server is told to hold 2 vsyncs", shared[2] == 2);
    check("and that the cap runs", shared[0] - shared[10] < 200000000);
    check("a light frame starts late (33 - 5 - 4 ms)", slept >= 15);

    usleep(300000);   /* a stall of 300 ms: it must not put the late start off for long */
    work_and_swap(swap, win);
    for (int i = 0; i < 40; i++) slept = work_and_swap(swap, win);
    printf("     %ld ms slept after the swap, 1.3 s after a stall\n", slept);
    check("a stall fades within 1.3 s", slept >= 5);

    writer_stop = 1;
    pthread_join(writer, 0);
    usleep(300000);   /* the display stopped: the file goes stale */
    swap(win);
    long long t0 = now_ns();
    for (int i = 0; i < 9; i++) swap(win);
    long ms = (long) ((now_ns() - t0) / 1000000);
    printf("     no vsync: 9 frames in %ld ms\n", ms);
    check("a stale vsync: the cap on its own clock", ms >= 290 && ms <= plain + 90);
}

/* recvmsg / sendmsg on a Unix stream socket without an address go around proot's traps (recvmmsg, writev): the same
   bytes, a passed file descriptor still arrives, an empty non-blocking socket still says EAGAIN, a datagram socket
   keeps the real calls (docs/CONTAINER-COST.md) */
struct t_iovec { void *base; unsigned long len; };
struct t_msghdr { void *name; unsigned int namelen; struct t_iovec *iov; unsigned long iovlen; void *control;
                  unsigned long controllen; int flags; };
struct t_cmsg { unsigned long len; int level; int type; int fd; int pad; };
extern int socketpair(int domain, int type, int protocol, int sv[2]);
extern long write(int fd, const void *buf, unsigned long n);
extern long read(int fd, void *buf, unsigned long n);
static void socket_tests(void) {
    long (*rcv)(int, struct t_msghdr *, int) = (long (*)(int, struct t_msghdr *, int)) dlsym(RTLD_DEFAULT, "recvmsg");
    long (*snd)(int, const struct t_msghdr *, int) = (long (*)(int, const struct t_msghdr *, int)) dlsym(RTLD_DEFAULT, "sendmsg");
    int sv[2];
    if (socketpair(1 /* AF_UNIX */, 1 /* SOCK_STREAM */ | 04000 /* SOCK_NONBLOCK */, 0, sv)) { check("socketpair", 0); return; }
    char a[] = "hello ", b[] = "x11", got[32] = { 0 };
    struct t_iovec iv[2] = { { a, 6 }, { b, 3 } };
    struct t_msghdr m = { 0, 0, iv, 2, 0, 0, 0 };
    check("sendmsg, two pieces, no control data: 9 bytes", snd(sv[0], &m, 0) == 9);
    struct t_iovec ri = { got, sizeof got };
    struct t_cmsg cm = { 0 };
    struct t_msghdr r = { 0, 0, &ri, 1, &cm, sizeof cm, 0 };
    long n = rcv(sv[1], &r, 0);
    int same = n == 9;
    for (int i = 0; same && i < 9; i++) same = got[i] == "hello x11"[i];
    check("recvmsg: the same 9 bytes, no control data back", same && r.controllen == 0);
    *__errno_location() = 0;
    r.controllen = sizeof cm;
    check("recvmsg on an empty socket: -1, EAGAIN", rcv(sv[1], &r, 0) == -1 && *__errno_location() == 11);
    /* a descriptor passed along (SCM_RIGHTS): sendmsg keeps its own call, recvmsg (recvmmsg) gets it */
    int pv[2];
    socketpair(1, 1, 0, pv);
    struct t_cmsg out = { sizeof(long) + 2 * sizeof(int) + sizeof(int), 1 /* SOL_SOCKET */, 1 /* SCM_RIGHTS */, pv[0], 0 };
    struct t_iovec oi = { "f", 1 };
    struct t_msghdr fm = { 0, 0, &oi, 1, &out, sizeof out, 0 };
    check("sendmsg with a descriptor: 1 byte", snd(sv[0], &fm, 0) == 1);
    struct t_cmsg in = { 0 };
    struct t_msghdr fr = { 0, 0, &ri, 1, &in, sizeof in, 0 };
    n = rcv(sv[1], &fr, 0);
    int ok = n == 1 && in.level == 1 && in.type == 1 && in.fd >= 0;
    if (ok) { write(in.fd, "z", 1); char c = 0; ok = read(pv[1], &c, 1) == 1 && c == 'z'; close(in.fd); }
    check("recvmsg: the descriptor arrives and works", ok);
    close(pv[0]); close(pv[1]); close(sv[0]); close(sv[1]);
    /* a datagram pair: the real calls (proot may act on those) */
    if (!socketpair(1, 2 /* SOCK_DGRAM */, 0, sv)) {
        struct t_msghdr dm = { 0, 0, iv, 2, 0, 0, 0 };
        check("datagram sendmsg: 9 bytes", snd(sv[0], &dm, 0) == 9);
        ri.len = sizeof got;
        struct t_msghdr dr = { 0, 0, &ri, 1, 0, 0, 0 };
        check("datagram recvmsg: 9 bytes", rcv(sv[1], &dr, 0) == 9);
        close(sv[0]); close(sv[1]);
    }
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
    /* catching up with a running game: the same with /tmp/bardroid-catchup */
    fd = open("/tmp/bardroid-catchup", O_WRONLY | O_CREAT, 0600);
    close(fd);
    check("catch-up flag set: HIDDEN (2)", wait_window_event(poll, id, &ev) && ev == 2);
    unlink("/tmp/bardroid-catchup");
    check("catch-up flag gone: SHOWN (1)", wait_window_event(poll, id, &ev) && ev == 1);

    /* the ioctl answer: the sync-file export fails with ENOTTY, anything else reaches the kernel (EBADF on fd -1) */
    int (*io)(int, unsigned long, ...) = (int (*)(int, unsigned long, ...)) dlsym(RTLD_DEFAULT, "ioctl");
    long arg = 0;
    int rc = io(-1, 0xc0086202UL, &arg);
    check("DMA_BUF_IOCTL_EXPORT_SYNC_FILE: -1, ENOTTY", rc == -1 && *__errno_location() == 25);
    rc = io(-1, 0x5401UL, &arg);   /* TCGETS */
    check("another ioctl goes through (EBADF)", rc == -1 && *__errno_location() == 9);

    socket_tests();

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

    usleep(600000);   /* the floating flag gone */
    swap(win);
    vsync_tests(swap, win, plain);

    printf("%s\n", fails ? "FAILED" : "ALL PASS");
    fflush(0);
}
