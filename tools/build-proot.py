"""Builds proot (Termux's fork, pinned below) and its loader for Android with the NDK and writes them to
app/src/main/jniLibs/<abi>/ as libproot.so and libproot-loader.so, replacing the Termux package binaries
fetched by tools/fetch-prebuilts.py (which still provides libtalloc.so and libandroid-shmem.so, linked here).

BAR Droid change: on Android, Termux's seccomp filter traps every ioctl(2) with an exit stop, although proot only
acts on a few terminal and network requests (SIOCGIFINDEX, TCSETSF, TCGETS2/TCSETS*2, FICLONE). The game's GPU
driver (Freedreno on KGSL) issues hundreds of ioctls per frame, each then costing two ptrace stops: on a Galaxy
Z Fold7 that was ~18,000 proot wake-ups per second, half a CPU core and audible audio gaps. The filter here traps
ioctl only for those request codes and lets the others through.

Run through toolchain\\env.bat (needs the NDK and the portable Python):
  python tools/build-proot.py arm64-v8a        (or x86_64)
"""
import hashlib, os, re, shutil, subprocess, sys, tarfile, urllib.request

ABI = sys.argv[1] if len(sys.argv) > 1 else "arm64-v8a"
TRIPLE = {"x86_64": "x86_64-linux-android28", "arm64-v8a": "aarch64-linux-android28"}[ABI]
LOADER_ADDRESS = {"x86_64": "0x600000000000", "arm64-v8a": "0x5400000000"}[ABI]   # src/arch.h
HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
TC = os.environ.get("TC") or os.path.join(os.path.dirname(APP), "toolchain")
SDK = os.environ.get("ANDROID_HOME") or os.path.join(TC, "android-sdk")
NDK_BIN = os.path.join(SDK, "ndk", "29.0.14206865", "toolchains", "llvm", "prebuilt", "windows-x86_64", "bin")
WORK = os.path.join(APP, "build", "proot", ABI)
DL = os.path.join(TC, "downloads")
OUT = os.path.join(APP, "app", "src", "main", "jniLibs", ABI)

PROOT_COMMIT = "b27d81a68d765f3462e807f4a14e01a03f8e89ea"   # termux/proot master, 2026-10-24
PROOT_SHA256 = "51af063ff92ed2d18a9011bee4cd1fb9483eea41f68d8a69068725afcca7b32a"
VERSION = "5.1.107-bardroid1"

OBJECTS_RE = re.compile(r"^OBJECTS \+= \\\n(.*?)\n\n", re.S | re.M)


def fetch(url, sha, name):
    path = os.path.join(DL, name)
    if not os.path.exists(path):
        print("download", url)
        req = urllib.request.Request(url, headers={"User-Agent": "BARDroid-build"})
        with urllib.request.urlopen(req, timeout=300) as r, open(path + ".part", "wb") as f:
            shutil.copyfileobj(r, f)
        os.replace(path + ".part", path)
    got = hashlib.sha256(open(path, "rb").read()).hexdigest()
    if sha and got != sha:
        sys.exit(f"sha256 mismatch for {name}: {got}")
    return path


def edit(path, old, new):
    s = open(path, encoding="utf-8").read()
    if s.count(old) != 1:
        sys.exit(f"edit failed in {path}: {old[:60]!r} found {s.count(old)} times")
    open(path, "w", encoding="utf-8", newline="\n").write(s.replace(old, new))


def patch_seccomp(path):
    """Trap ioctl only for the request codes proot handles (syscall/enter.c and exit.c, case PR_ioctl)."""
    edit(path, '#include <assert.h>        /* assert(3), */',
         '#include <assert.h>        /* assert(3), */\n'
         '#include <sys/ioctl.h>     /* _IOW, BAR Droid */\n'
         '#include <termios.h>       /* TCSETS, TCGETS2, ... */\n'
         '#include <linux/sockios.h> /* SIOCGIFINDEX */')
    edit(path, '/**\n * Append to @program->filter the statements that allow anything (if\n',
         '/* BAR Droid: the ioctl requests PRoot acts on (syscall/enter.c and syscall/exit.c, case\n'
         ' * PR_ioctl). Any other ioctl -- GPU drivers make hundreds per frame -- runs without a\n'
         ' * ptrace stop.  */\n'
         'static const uint32_t traced_ioctls[] = {\n'
         '\tSIOCGIFINDEX,\n'
         '\tTCSETS + 2, /* TCSAFLUSH, rewritten to TCSANOW on Android */\n'
         '#ifdef TCGETS2\n'
         '\tTCGETS2, TCSETS2, TCSETSW2, TCSETSF2,\n'
         '#endif\n'
         '\t_IOW(0x94, 9, int), /* FICLONE */\n'
         '};\n'
         '#define NB_TRACED_IOCTLS (sizeof(traced_ioctls) / sizeof(traced_ioctls[0]))\n'
         '/* syscall check, request load, one check per request, allow, trace */\n'
         '#define LENGTH_TRACE_IOCTL (NB_TRACED_IOCTLS + 4)\n'
         '#define EXTRA_LENGTH_IOCTL (LENGTH_TRACE_IOCTL - LENGTH_TRACE_SYSCALL)\n\n'
         'static int add_trace_ioctl(struct sock_fprog *program, word_t syscall, int flag)\n'
         '{\n'
         '\tstruct sock_filter statements[LENGTH_TRACE_IOCTL];\n'
         '\tsize_t i, n = 0;\n\n'
         '\tif (syscall > UINT32_MAX)\n'
         '\t\treturn -ERANGE;\n\n'
         '\t/* Not this syscall: skip the block, the accumulator still holds the syscall number.  */\n'
         '\tstatements[n++] = (struct sock_filter) BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, syscall, 0, LENGTH_TRACE_IOCTL - 1);\n'
         '\t/* The request: low 32 bits of the second argument (little-endian targets only).  */\n'
         '\tstatements[n++] = (struct sock_filter) BPF_STMT(BPF_LD + BPF_W + BPF_ABS, offsetof(struct seccomp_data, args[1]));\n'
         '\tfor (i = 0; i < NB_TRACED_IOCTLS; i++)\n'
         '\t\tstatements[n++] = (struct sock_filter) BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, traced_ioctls[i], NB_TRACED_IOCTLS - i, 0);\n'
         '\tstatements[n++] = (struct sock_filter) BPF_STMT(BPF_RET + BPF_K, SECCOMP_RET_ALLOW);\n'
         '\tstatements[n++] = (struct sock_filter) BPF_STMT(BPF_RET + BPF_K, SECCOMP_RET_TRACE + flag);\n\n'
         '\tDEBUG_FILTER("FILTER:     trace if syscall == %ld and its request is one PRoot handles\\n", syscall);\n'
         '\treturn add_statements(program, n, statements);\n'
         '}\n\n'
         '/**\n * Append to @program->filter the statements that allow anything (if\n')
    # Section lengths: the arch-mismatch jump and the sanity checks must count the longer ioctl block.
    edit(path, 'static int end_arch_section(struct sock_fprog *program, size_t nb_traced_syscalls)',
         'static int end_arch_section(struct sock_fprog *program, size_t nb_traced_syscalls, size_t extra)')
    edit(path, '\t    != LENGTH_END_SECTION + nb_traced_syscalls * LENGTH_TRACE_SYSCALL)',
         '\t    != LENGTH_END_SECTION + nb_traced_syscalls * LENGTH_TRACE_SYSCALL + extra)')
    edit(path, 'static int start_arch_section(struct sock_fprog *program, uint32_t arch, size_t nb_traced_syscalls)',
         'static int start_arch_section(struct sock_fprog *program, uint32_t arch, size_t nb_traced_syscalls,\n'
         '\t\t\t      size_t extra)')
    edit(path, '\t\t\t\t\tnb_traced_syscalls * LENGTH_TRACE_SYSCALL;',
         '\t\t\t\t\tnb_traced_syscalls * LENGTH_TRACE_SYSCALL + extra;')
    edit(path, '\tsize_t nb_traced_syscalls;\n\tsize_t i, j, k;',
         '\tsize_t nb_traced_syscalls;\n\tsize_t extra;\n\tsize_t i, j, k;')
    edit(path, '\t\tnb_traced_syscalls = 0;\n',
         '\t\tnb_traced_syscalls = 0;\n\t\textra = 0;\n')
    edit(path, '\t\t\t\tif (syscall != SYSCALL_AVOIDER)\n\t\t\t\t\tnb_traced_syscalls++;',
         '\t\t\t\tif (syscall != SYSCALL_AVOIDER) {\n'
         '\t\t\t\t\tnb_traced_syscalls++;\n'
         '\t\t\t\t\tif (sysnums[k].value == PR_ioctl)\n'
         '\t\t\t\t\t\textra += EXTRA_LENGTH_IOCTL;\n'
         '\t\t\t\t}')
    edit(path, 'status = start_arch_section(&program, seccomp_archs[i].value, nb_traced_syscalls);',
         'status = start_arch_section(&program, seccomp_archs[i].value, nb_traced_syscalls, extra);')
    edit(path, '\t\t\t\tstatus = add_trace_syscall(&program, syscall, sysnums[k].flags);',
         '\t\t\t\tstatus = sysnums[k].value == PR_ioctl\n'
         '\t\t\t\t\t? add_trace_ioctl(&program, syscall, sysnums[k].flags)\n'
         '\t\t\t\t\t: add_trace_syscall(&program, syscall, sysnums[k].flags);')
    edit(path, 'status = end_arch_section(&program, nb_traced_syscalls);',
         'status = end_arch_section(&program, nb_traced_syscalls, extra);')


def termux_headers(inc):
    """Headers of Termux's libtalloc and libandroid-shmem packages (talloc.h, sys/shm.h); the libraries themselves
    are the ones in jniLibs."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("prebuilts", os.path.join(HERE, "fetch-prebuilts.py"))
    fp = importlib.util.module_from_spec(spec)
    sys.argv = [sys.argv[0], ABI]   # fetch-prebuilts reads its ABI at import
    spec.loader.exec_module(fp)
    tx = fp.index(f"{fp.TERMUX}/dists/stable/main/binary-{fp.TERMUX_ARCH}/Packages")
    for pkg, want in (("libtalloc", "talloc.h"), ("libandroid-shmem", "sys/shm.h")):
        files = fp.deb_files(fp.get(f"{fp.TERMUX}/{tx[pkg]['Filename']}"))
        found = False
        for k, v in files.items():
            if "/usr/include/" in k and not k.endswith("/"):
                rel = k.split("/usr/include/", 1)[1]
                os.makedirs(os.path.dirname(os.path.join(inc, rel)), exist_ok=True)
                open(os.path.join(inc, rel), "wb").write(v)
                found |= rel == want
        if not found:
            sys.exit(f"{want} not in Termux's {pkg} package")


def run(cmd):
    print(" ".join(os.path.basename(c) if i == 0 else c for i, c in enumerate(cmd))[:200])
    subprocess.check_call(cmd)


def main():
    clang = os.path.join(NDK_BIN, "clang.exe")
    for f in ("libtalloc.so", "libandroid-shmem.so"):
        if not os.path.exists(os.path.join(OUT, f)):
            sys.exit(f"{OUT}\\{f} missing: run tools/fetch-prebuilts.py {ABI} first")
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)
    tgz = fetch(f"https://codeload.github.com/termux/proot/tar.gz/{PROOT_COMMIT}", PROOT_SHA256,
                f"termux-proot-{PROOT_COMMIT[:12]}.tar.gz")
    with tarfile.open(tgz) as t:
        for m in t.getmembers():
            if m.issym() or m.islnk():
                continue        # only CLAUDE.md -> AGENTS.md; Windows cannot create it
            t.extract(m, WORK, filter="data") if hasattr(tarfile, "data_filter") else t.extract(m, WORK)
    src = os.path.join(WORK, f"proot-{PROOT_COMMIT}", "src")
    patch_seccomp(os.path.join(src, "syscall", "seccomp.c"))

    inc = os.path.join(WORK, "include")
    termux_headers(inc)
    build = os.path.join(WORK, "obj")
    os.makedirs(build)
    with open(os.path.join(build, "build.h"), "w", newline="\n") as f:
        f.write("/* BAR Droid: written by tools/build-proot.py (the probes need a target to run on).  */\n"
                "#ifndef BUILD_H\n#define BUILD_H\n"
                f'#undef VERSION\n#define VERSION "{VERSION}"\n'
                "#define HAVE_PROCESS_VM\n#define HAVE_SECCOMP_FILTER\n#endif /* BUILD_H */\n")

    common = [clang, f"--target={TRIPLE}", "-D_FILE_OFFSET_BITS=64", "-D_GNU_SOURCE", "-I" + build, "-I" + src]
    # --- the loader: static, freestanding, at the fixed address proot maps it to
    loader_dir = os.path.join(build, "loader")
    os.makedirs(loader_dir)
    lflags = ["-fPIC", "-ffreestanding", "-O2"]
    for s in ("loader.c", "assembly.S"):
        run(common + lflags + ["-c", os.path.join(src, "loader", s), "-o", os.path.join(loader_dir, s + ".o")])
    loader = os.path.join(loader_dir, "loader")
    run([clang, f"--target={TRIPLE}", "-static", "-nostdlib", "-o", loader,
         os.path.join(loader_dir, "loader.c.o"), os.path.join(loader_dir, "assembly.S.o"),
         f"-Wl,--build-id=none,-Ttext={LOADER_ADDRESS},--rosegment,-z,noexecstack"])   # as GNUmakefile with lld
    extra_objects = []
    if ABI == "arm64-v8a":
        # HAS_POKEDATA_WORKAROUND (src/arch.h): proot needs the stub's offset from _start (loader/loader-info.awk)
        nm = subprocess.check_output([os.path.join(NDK_BIN, "llvm-nm.exe"), loader], text=True)
        sym = {p[2]: int(p[0], 16) for p in (l.split() for l in nm.splitlines()) if len(p) == 3}
        info = os.path.join(build, "loader-info.c")
        with open(info, "w", newline="\n") as f:
            f.write("#include <unistd.h>\n"
                    f"const ssize_t offset_to_pokedata_workaround={sym['pokedata_workaround'] - sym['_start']};\n")
        extra_objects.append(info)

    # --- proot itself
    mk = open(os.path.join(src, "GNUmakefile"), encoding="utf-8").read()
    objects = re.findall(r"([\w/-]+)\.o", OBJECTS_RE.findall(mk)[0])
    # -include string.h: ashmem_memfd.c uses strcmp/memset without it (an error in NDK 29's clang)
    cflags = ["-I" + inc, "-O2", "-Wall", "-Wno-unused-parameter", "-include", "string.h", "-DWITH_LIBANDROID_SHMEM",
              '-DPROOT_UNBUNDLE_LOADER="/bardroid-uses-PROOT_LOADER"']
    objs = []
    for o in objects + [os.path.splitext(os.path.relpath(e, src))[0] if e.startswith(src) else e for e in extra_objects]:
        c = o if o.endswith(".c") else os.path.join(src, o + ".c")
        out = os.path.join(build, os.path.basename(o) + "-" + str(len(objs)) + ".o")
        run(common + cflags + ["-c", c, "-o", out])
        objs.append(out)
    exe = os.path.join(build, "proot")
    run([clang, f"--target={TRIPLE}", "-o", exe] + objs +
        ["-L" + OUT, "-ltalloc", "-landroid-shmem", "-Wl,-z,noexecstack", "-Wl,-rpath,$ORIGIN"])

    strip = os.path.join(NDK_BIN, "llvm-strip.exe")
    for path, name in ((exe, "libproot.so"), (loader, "libproot-loader.so")):
        dst = os.path.join(OUT, name)
        shutil.copyfile(path, dst)
        subprocess.check_call([strip, "--strip-unneeded", dst])
        print(f"wrote {ABI}/{name} ({os.path.getsize(dst)} bytes)")


if __name__ == "__main__":
    main()
