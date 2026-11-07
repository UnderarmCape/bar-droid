/* stopsample: how much of a thread's time is spent stopped by its ptrace tracer (proot), and in which system
 * calls (docs/CONTAINER-COST.md). Reads /proc/<pid>/task/<tid>/stat at a fixed rate; a 't' (tracing stop) sample
 * also reads .../syscall for the system call number the thread is stopped in. Run as the app's user (run-as) so
 * .../syscall is readable:
 *   stopsample <pid> <seconds> [rate_hz] [tid ...]     (no tid: every thread of <pid>)
 * Prints per thread: samples, running/sleeping/stopped shares, and the stopped samples by system call number.
 * Built by tools/container-cost/build.ps1 with the NDK (static, arm64). */
#define _GNU_SOURCE
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define MAXT 256
#define MAXNR 512

struct thr {
    int tid, statfd, sysfd;
    char comm[32];
    long n, run, sleep, stop, disk, other;
    long nr[MAXNR + 1];
    int laststop;
    long stops;   /* distinct stopped episodes (consecutive 't' samples counted once) */
};

static struct thr T[MAXT];
static int nt;

static int openf(int pid, int tid, const char *f) {
    char p[96];
    snprintf(p, sizeof p, "/proc/%d/task/%d/%s", pid, tid, f);
    return open(p, O_RDONLY | O_CLOEXEC);
}

static void add(int pid, int tid) {
    if (nt >= MAXT) return;
    struct thr *t = &T[nt];
    memset(t, 0, sizeof *t);
    t->tid = tid;
    t->statfd = openf(pid, tid, "stat");
    t->sysfd = openf(pid, tid, "syscall");
    int cf = openf(pid, tid, "comm");
    if (cf >= 0) { int r = read(cf, t->comm, sizeof t->comm - 1); if (r > 0) t->comm[r - 1] = 0; close(cf); }
    if (t->statfd >= 0) nt++;
}

static double now(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return ts.tv_sec + ts.tv_nsec * 1e-9; }

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "stopsample <pid> <seconds> [rate_hz] [tid ...]\n"); return 2; }
    int pid = atoi(argv[1]);
    double secs = atof(argv[2]);
    double rate = argc > 3 ? atof(argv[3]) : 2000;
    if (argc > 4) for (int i = 4; i < argc; i++) add(pid, atoi(argv[i]));
    else {
        char p[64]; snprintf(p, sizeof p, "/proc/%d/task", pid);
        DIR *d = opendir(p); struct dirent *e;
        if (!d) { perror(p); return 1; }
        while ((e = readdir(d))) if (e->d_name[0] != '.') add(pid, atoi(e->d_name));
        closedir(d);
    }
    char buf[512];
    double t0 = now(), next = t0, step = 1.0 / rate;
    long rounds = 0;
    while (now() - t0 < secs) {
        for (int i = 0; i < nt; i++) {
            struct thr *t = &T[i];
            int r = pread(t->statfd, buf, sizeof buf - 1, 0);
            if (r <= 0) continue;
            buf[r] = 0;
            char *c = strrchr(buf, ')');
            if (!c || !c[1] || !c[2]) continue;
            char st = c[2];
            t->n++;
            if (st == 'R') { t->run++; t->laststop = 0; }
            else if (st == 'S') { t->sleep++; t->laststop = 0; }
            else if (st == 't' || st == 'T') {
                t->stop++;
                if (!t->laststop) t->stops++;
                t->laststop = 1;
                long nr = MAXNR;
                if (t->sysfd >= 0) {
                    int s = pread(t->sysfd, buf, sizeof buf - 1, 0);
                    if (s > 0) { buf[s] = 0; if (buf[0] >= '0' && buf[0] <= '9') nr = atol(buf); }
                }
                if (nr < 0 || nr > MAXNR) nr = MAXNR;
                t->nr[nr]++;
            } else if (st == 'D') { t->disk++; t->laststop = 0; }
            else { t->other++; t->laststop = 0; }
        }
        rounds++;
        next += step;
        double w = next - now();
        if (w > 0) { struct timespec ts = { (time_t) w, (long) ((w - (time_t) w) * 1e9) }; nanosleep(&ts, NULL); }
        else next = now();
    }
    double el = now() - t0;
    printf("rounds %ld in %.1f s (%.0f Hz)\n", rounds, el, rounds / el);
    for (int i = 0; i < nt; i++) {
        struct thr *t = &T[i];
        if (!t->n) continue;
        printf("tid %d %-16s n %ld run %.1f%% sleep %.1f%% stop %.2f%% (episodes %ld) disk %.1f%%",
               t->tid, t->comm, t->n, 100.0 * t->run / t->n, 100.0 * t->sleep / t->n, 100.0 * t->stop / t->n,
               t->stops, 100.0 * t->disk / t->n);
        if (t->stop) {
            printf(" |");
            for (int k = 0; k <= MAXNR; k++) if (t->nr[k]) printf(" %d:%ld", k == MAXNR ? -1 : k, t->nr[k]);
        }
        printf("\n");
    }
    return 0;
}
