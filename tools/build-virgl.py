"""Builds the virgl GPU server (virglrenderer 1.3.0 + libepoxy 1.5.10) for Android with the NDK and writes it to
app/src/main/jniLibs/<abi>/ as libvirgl_server.so (the executable), libvirglrenderer.so and libepoxy.so.

Same sources and patches as Termux's virglrenderer-android (termux-packages, pinned below), plus BAR Droid fixes:
  * DXT/S3TC: Termux's patch always decompresses DXT on the server and re-uploads it with glTexImage2D into a
    texture that already has immutable compressed storage -> GL_INVALID_OPERATION, every DXT texture stays black
    (BAR's map tiles and unit skins). Here it decompresses only when the host GLES has no S3TC; otherwise the
    compressed data goes through glCompressedTexSubImage* as upstream does.
  * ANGLE directory from $BARDROID_ANGLE_DIR (default "."), not Termux's prefix; default socket /tmp/.virgl_test.

Run through toolchain\\env.bat (needs the NDK, CMake's ninja, the portable Python and git on PATH):
  python tools/build-virgl.py x86_64        (or arm64-v8a)
"""
import hashlib, os, re, shutil, subprocess, sys, tarfile, urllib.request

ABI = sys.argv[1] if len(sys.argv) > 1 else "x86_64"
TRIPLE = {"x86_64": "x86_64-linux-android28", "arm64-v8a": "aarch64-linux-android28"}[ABI]
CPU = {"x86_64": "x86_64", "arm64-v8a": "aarch64"}[ABI]
HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
TC = os.environ.get("TC") or os.path.join(os.path.dirname(APP), "toolchain")
SDK = os.environ.get("ANDROID_HOME") or os.path.join(TC, "android-sdk")
NDK_BIN = os.path.join(SDK, "ndk", "29.0.14206865", "toolchains", "llvm", "prebuilt", "windows-x86_64", "bin")
NINJA_DIR = os.path.join(SDK, "cmake", "3.22.1", "bin")
WORK = os.path.join(APP, "build", "virgl")
DL = os.path.join(TC, "downloads")
OUT = os.path.join(APP, "app", "src", "main", "jniLibs", ABI)

SOURCES = {
    "virglrenderer": ("https://deb.debian.org/debian/pool/main/v/virglrenderer/virglrenderer_1.3.0.orig.tar.bz2",
                      "088040d130eaa0458a978fe7867fbfb1fcf1fdff52bf3b27a00658828bc4189f", "virglrenderer-1.3.0"),
    "libepoxy": ("https://github.com/anholt/libepoxy/archive/refs/tags/1.5.10.tar.gz",
                 "a7ced37f4102b745ac86d6a70a9da399cc139ff168ba6b8002b4d8d43c900c15", "libepoxy-1.5.10"),
    "meson": ("https://github.com/mesonbuild/meson/releases/download/1.12.1/meson-1.12.1.tar.gz", None, "meson-1.12.1"),
    # Mesa's u_format codegen (inside virglrenderer) imports yaml; the pure-Python package is enough.
    "pyyaml": ("https://files.pythonhosted.org/packages/05/8e/961c0007c59b8dd7729d542c61a4d537767a59645b82a0b521206e1e25c2/pyyaml-6.0.3.tar.gz",
               "d76623373421df22fb4cf8817020cbb7ef15c725b9d5e45f17e189bfc384190f", "pyyaml-6.0.3"),
}
TERMUX_COMMIT = "5952664fae176ea6929f354bf1b1af70c4a1cffb"
TERMUX_PATCHES = ["0001-do-not-use-gbm", "0002-avoid-gnu-offsetof-extensions-error", "0003-use-angle",
                  "0004-Fallback-to-ashmem", "0005-Enable-debug-for-EGL", "0006-Disable-feature-feat_dual_src_blend",
                  "0007-Ensure-EGL-GLES-ANGLE-help-and-socket-path",
                  "0008-Impl-DXTn-S3TC-texture-decompression-in-virglrenderer", "0009-disable-termux-detection",
                  "0010-disable-memfd_create-timespec_get", "0011-use-Android-Vulkan", "0012-fix-build-on-arm"]


def fetch(url, sha, name):
    path = os.path.join(DL, name)
    if not os.path.exists(path):
        print("download", url)
        req = urllib.request.Request(url, headers={"User-Agent": "BARDroid-build"})
        with urllib.request.urlopen(req, timeout=300) as r, open(path + ".part", "wb") as f:
            shutil.copyfileobj(r, f)
        os.replace(path + ".part", path)
    if sha:
        got = hashlib.sha256(open(path, "rb").read()).hexdigest()
        if got != sha:
            sys.exit(f"sha256 mismatch for {name}: {got}")
    return path


def extract(archive, dest):
    with tarfile.open(archive) as t:
        for m in t.getmembers():
            if m.issym() or m.islnk():
                continue        # only editor configs are links in these trees; Windows cannot create them anyway
            t.extract(m, dest, filter="data") if hasattr(tarfile, "data_filter") else t.extract(m, dest)


def edit(path, old, new, count=1):
    s = open(path, encoding="utf-8").read()
    if s.count(old) < 1:
        sys.exit(f"edit failed in {path}: {old[:60]!r} not found")
    s = s.replace(old, new) if count == 0 else s.replace(old, new, count)
    open(path, "w", encoding="utf-8", newline="\n").write(s)


def main():
    os.makedirs(DL, exist_ok=True)
    src_root = os.path.join(WORK, "src")
    meson_dir = os.path.join(WORK, SOURCES["meson"][2])
    if not os.path.isdir(meson_dir):
        extract(fetch(SOURCES["meson"][0], None, "meson-1.12.1.tar.gz"), WORK)
    pydeps = os.path.join(WORK, "pydeps")
    if not os.path.isdir(os.path.join(pydeps, "yaml")):
        extract(fetch(*SOURCES["pyyaml"][:2], "pyyaml-6.0.3.tar.gz"), WORK)
        shutil.copytree(os.path.join(WORK, SOURCES["pyyaml"][2], "lib", "yaml"), os.path.join(pydeps, "yaml"))
    # The embeddable Python ignores PYTHONPATH and does not put a script's own folder on sys.path (python314._pth):
    # list meson, yaml and the codegen scripts' folder there (meson's sub-invocations must import mesonbuild).
    pth = os.path.join(os.path.dirname(sys.executable), "python314._pth")
    codegen = os.path.join(src_root, SOURCES["virglrenderer"][2], "src", "gallium", "auxiliary", "util")
    for d in (meson_dir, pydeps, codegen):
        if os.path.exists(pth) and d not in open(pth).read():
            open(pth, "a").write("\n" + d + "\n")
            print("added to", pth, ":", d)

    virgl = os.path.join(src_root, SOURCES["virglrenderer"][2])
    stamp = os.path.join(virgl, ".bardroid-patched")
    if not os.path.exists(stamp):
        shutil.rmtree(src_root, ignore_errors=True)
        os.makedirs(src_root)
        extract(fetch(*SOURCES["virglrenderer"][:2], "virglrenderer_1.3.0.orig.tar.bz2"), src_root)
        extract(fetch(*SOURCES["libepoxy"][:2], "libepoxy-1.5.10.tar.gz"), src_root)
        shutil.move(os.path.join(src_root, SOURCES["libepoxy"][2]), os.path.join(virgl, "libepoxy"))   # Termux layout
        for name in TERMUX_PATCHES:
            url = (f"https://raw.githubusercontent.com/termux/termux-packages/{TERMUX_COMMIT}/packages/"
                   f"virglrenderer-android/{name}.patch.beforehostbuild")
            raw = fetch(url, None, f"termux-virgl-{TERMUX_COMMIT[:8]}-{name}.patch")
            # Termux applies these with GNU patch (offsets, fuzz); Debian's 1.3.0 tree needs that.
            subprocess.check_call([sys.executable, os.path.join(HERE, "apply-patch.py"), raw, virgl])
            print("applied", name)
        # --- BAR Droid fixes -------------------------------------------------------------------------------
        r = os.path.join(virgl, "src", "vrend", "vrend_renderer.c")
        edit(r, "const int dxtn_decompress = 1;", "int dxtn_decompress = 1;   /* BAR Droid: set in vrend_formats.c */")
        f = os.path.join(virgl, "src", "vrend", "vrend_formats.c")
        s = open(f, encoding="utf-8").read()
        m = re.search(r"\n([ \t]*)if \(([^;{]*epoxy_has_gl_extension\(\"GL_ANGLE_texture_compression_dxt\"\) \|\| dxtn_decompress)\)", s)
        if not m:
            sys.exit("could not find the S3TC capability check in vrend_formats.c")
        native = m.group(2).replace("|| dxtn_decompress", "").strip()
        # ANGLE names its S3TC support per format; none of the upstream names match it.
        angle = ('(epoxy_has_gl_extension("GL_EXT_texture_compression_dxt1") && '
                 'epoxy_has_gl_extension("GL_ANGLE_texture_compression_dxt3") && '
                 'epoxy_has_gl_extension("GL_ANGLE_texture_compression_dxt5"))')
        s = s[:m.start()] + (f"\n{m.group(1)}/* BAR Droid: decompress only when the host cannot sample S3TC itself. */\n"
                             f"{m.group(1)}dxtn_decompress = !({native} ||\n{m.group(1)}    {angle});\n") + s[m.start():]
        open(f, "w", encoding="utf-8", newline="\n").write(s)
        v = os.path.join(virgl, "vtest", "vtest_server.c")
        for flavor in ("gl", "vulkan-null", "vulkan"):
            edit(v, f'epoxy_set_library_path("@TERMUX_PREFIX@/opt/angle-android/{flavor}");',
                 'epoxy_set_library_path(getenv("BARDROID_ANGLE_DIR") ? getenv("BARDROID_ANGLE_DIR") : ".");')
        edit(v, '"@TERMUX_PREFIX@/tmp/.virgl_test"', '"/tmp/.virgl_test"')
        # On Windows find_installation('python3') goes through the py launcher (a system Python); use meson's own.
        for dirpath, _, files in os.walk(virgl):
            for fn in files:
                if fn == "meson.build":
                    p = os.path.join(dirpath, fn)
                    s = open(p, encoding="utf-8").read()
                    if "find_installation('python3'" in s:
                        s = s.replace("find_installation('python3', ", "find_installation(").replace(
                            "find_installation('python3')", "find_installation()")
                        open(p, "w", encoding="utf-8", newline="\n").write(s)
        # epoxy is a subproject here (built with EGL): compiler probes cannot use internal dependencies
        edit(os.path.join(virgl, "meson.build"),
             "if cc.has_header('epoxy/egl.h', dependencies: epoxy_dep) and epoxy_dep.get_variable(pkgconfig: 'epoxy_has_egl') == '1'",
             "if true  # BAR Droid: epoxy subproject is built with EGL")
        # libepoxy as a meson subproject (no pkg-config on Windows)
        os.makedirs(os.path.join(virgl, "subprojects"), exist_ok=True)
        shutil.move(os.path.join(virgl, "libepoxy"), os.path.join(virgl, "subprojects", "epoxy"))
        open(os.path.join(virgl, "subprojects", "epoxy.wrap"), "w").write(
            "[wrap-file]\ndirectory = epoxy\n\n[provide]\nepoxy = libepoxy_dep\n")
        open(stamp, "w").write("ok\n")

    build = os.path.join(WORK, "build-" + ABI)
    cross = os.path.join(WORK, f"android-{ABI}.ini")
    q = lambda p: "'" + p.replace("\\", "/") + "'"
    open(cross, "w").write(
        "[binaries]\n"
        f"c = [{q(os.path.join(NDK_BIN, 'clang.exe'))}, '--target={TRIPLE}']\n"
        f"cpp = [{q(os.path.join(NDK_BIN, 'clang++.exe'))}, '--target={TRIPLE}']\n"
        f"ar = {q(os.path.join(NDK_BIN, 'llvm-ar.exe'))}\n"
        f"strip = {q(os.path.join(NDK_BIN, 'llvm-strip.exe'))}\n"
        f"python3 = {q(sys.executable)}\n"          # meson's python module looks here in cross builds
        "[host_machine]\n"
        f"system = 'android'\ncpu_family = '{CPU}'\ncpu = '{CPU}'\nendian = 'little'\n")
    # Build-machine tools: this portable Python (with yaml), never one found in the registry.
    native = os.path.join(WORK, "native.ini")
    open(native, "w").write(f"[binaries]\npython3 = {q(sys.executable)}\npython = {q(sys.executable)}\n")
    env = dict(os.environ)
    env["PATH"] = NINJA_DIR + os.pathsep + env["PATH"]
    meson = [sys.executable, os.path.join(meson_dir, "meson.py")]
    if not os.path.isdir(os.path.join(build, "meson-private")):
        subprocess.check_call(meson + [
            "setup", build, virgl, "--cross-file", cross, "--native-file", native,
            "--buildtype=release", "-Db_ndebug=true",
            "--force-fallback-for=epoxy", "-Depoxy:egl=yes", "-Depoxy:glx=no", "-Depoxy:x11=false",
            "-Depoxy:tests=false", "-Depoxy:docs=false",
            "-Dplatforms=egl", "-Dvenus=false", "-Ddrm-renderers=[]", "-Dvideo=false", "-Dtests=false"], env=env)
    subprocess.check_call(meson + ["compile", "-C", build], env=env)

    strip = os.path.join(NDK_BIN, "llvm-strip.exe")
    for src, name in ((os.path.join(build, "vtest", "virgl_test_server"), "libvirgl_server.so"),
                      (os.path.join(build, "src", "libvirglrenderer.so"), "libvirglrenderer.so"),
                      (os.path.join(build, "subprojects", "epoxy", "src", "libepoxy.so"), "libepoxy.so")):
        dst = os.path.join(OUT, name)
        subprocess.check_call([strip, "-o", dst, src])
        # meson leaves build-tree RUNPATHs ("$ORIGIN\..\src:..."); everything ships in one directory.
        sys.path.insert(0, HERE)
        from importlib import import_module
        fp = import_module("fetch-prebuilts")
        data = open(dst, "rb").read()
        for rp in set(re.findall(rb"\$ORIGIN[^\0]*", data)):
            if rp != b"$ORIGIN":
                data, _ = fp.replace_dynstr(data, rp.decode(), "$ORIGIN")
        open(dst, "wb").write(data)
        print(f"wrote {ABI}/{name} ({os.path.getsize(dst)} bytes)")


if __name__ == "__main__":
    main()
