/* trapbench: the cost of one system call that proot traps, against one it lets through (docs/CONTAINER-COST.md).
 * Run inside the container (tools/container-shell.bat, or the app's container.sh):
 *   trapbench [count]
 * Times <count> calls each of getppid (never trapped), fstat (trapped with an exit stop: link2symlink and the
 * ashmem/memfd extension), close of a bad fd (trapped at entry only), sendmsg on a socketpair (trapped at entry),
 * brk(0) (trapped with an exit stop) and openat+close of a file (path translation), and prints microseconds per call.
 * Built static for arm64 with the NDK (tools/container-cost/build.ps1): no container library is involved. */
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

static double now(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return ts.tv_sec + ts.tv_nsec * 1e-9; }

int main(int argc, char **argv) {
    int n = argc > 1 ? atoi(argv[1]) : 20000;
    struct stat st;
    int sv[2];
    socketpair(AF_UNIX, SOCK_DGRAM, 0, sv);
    char c = 0;
    struct iovec iov = { &c, 1 };
    struct msghdr mh = { 0 };
    mh.msg_iov = &iov; mh.msg_iovlen = 1;
    double t;
#define RUN(name, expr) do { t = now(); for (int i = 0; i < n; i++) { expr; } \
        printf("%-14s %8.2f us\n", name, (now() - t) * 1e6 / n); } while (0)
    RUN("getppid", syscall(SYS_getppid));
    RUN("fstat", fstat(0, &st));
    RUN("close(-1)", close(-1));
    RUN("sendmsg+recv", (sendmsg(sv[0], &mh, 0), recv(sv[1], &c, 1, 0)));
    RUN("brk(0)", syscall(SYS_brk, 0));
    RUN("openat+close", close(openat(AT_FDCWD, "/proc/self/stat", O_RDONLY)));
    return 0;
}
