"""Fetches the native helpers BAR Droid execs (proot + its libs and ANGLE from Termux, a static busybox from Debian;
the virgl GPU server comes from tools/build-virgl.py) for one
Android ABI and writes them into app/src/main/jniLibs/<abi>/ under the lib*.so names Android extracts and lets
the app exec. Termux's proot looks for libtalloc.so.2 in Termux's prefix; it is patched in place to load
libtalloc.so from its own directory ($ORIGIN), the same way the bundled arm64 copies were prepared.

  python -I tools/fetch-prebuilts.py x86_64        (or arm64-v8a)
"""
import io, lzma, os, re, struct, sys, tarfile, urllib.request

ABI = sys.argv[1] if len(sys.argv) > 1 else "x86_64"
TERMUX_ARCH = {"x86_64": "x86_64", "arm64-v8a": "aarch64"}[ABI]
DEBIAN_ARCH = {"x86_64": "amd64", "arm64-v8a": "arm64"}[ABI]
TERMUX = "https://packages.termux.dev/apt/termux-main"
DEBIAN = "https://deb.debian.org/debian"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "app", "src", "main", "jniLibs", ABI)


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "BARDroid-fetch-prebuilts"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def index(url):
    data = get(url)
    if url.endswith(".xz"):
        data = lzma.decompress(data)
    pkgs = {}
    for st in data.decode("utf-8", "replace").split("\n\n"):
        m = re.search(r"^Package: (.+)$", st, re.M)
        if m:
            pkgs[m.group(1)] = dict(re.findall(r"^([A-Za-z-]+): (.*)$", st, re.M))
    return pkgs


def deb_files(blob):
    """Returns {path: bytes} for regular files in a .deb's data.tar.*."""
    assert blob[:8] == b"!<arch>\n"
    pos, files = 8, {}
    while pos < len(blob):
        name = blob[pos:pos + 16].decode().strip().rstrip("/")
        size = int(blob[pos + 48:pos + 58].decode().strip())
        body = blob[pos + 60:pos + 60 + size]
        pos += 60 + size + (size & 1)
        if name.startswith("data.tar"):
            with tarfile.open(fileobj=io.BytesIO(body)) as t:
                for m in t.getmembers():
                    if m.isfile():
                        files[m.name.lstrip("./")] = t.extractfile(m).read()
    return files


def replace_dynstr(data, old, new):
    """Overwrites a string in .dynstr with a shorter or equal one (NUL-padded). The ELF layout is untouched."""
    assert len(new) <= len(old)
    data = bytearray(data)
    e_shoff, = struct.unpack_from("<Q", data, 0x28)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 0x3A)
    secs = [struct.unpack_from("<IIQQQQ", data, e_shoff + i * e_shentsize) for i in range(e_shnum)]
    shstr = secs[e_shstrndx][4]
    for name, typ, flags, addr, offset, size in secs:
        sname = bytes(data[shstr + name:data.index(b"\0", shstr + name)])
        if sname != b".dynstr":
            continue
        region = bytes(data[offset:offset + size])
        needle = b"\0" + old.encode() + b"\0"
        i = region.find(needle)
        if i < 0:
            return bytes(data), False
        start = offset + i + 1
        data[start:start + len(old)] = new.encode() + b"\0" * (len(old) - len(new))
        return bytes(data), True
    return bytes(data), False


def main():
    os.makedirs(OUT, exist_ok=True)
    tx = index(f"{TERMUX}/dists/stable/main/binary-{TERMUX_ARCH}/Packages")
    written = []

    def termux_pkg(name):
        p = tx[name]
        print(f"termux {name} {p['Version']}")
        return deb_files(get(f"{TERMUX}/{p['Filename']}"))

    proot = termux_pkg("proot")
    talloc = termux_pkg("libtalloc")
    shmem = termux_pkg("libandroid-shmem")
    prefix = "data/data/com.termux/files/usr/"

    exe = proot[prefix + "bin/proot"]
    exe, ok = replace_dynstr(exe, "libtalloc.so.2", "libtalloc.so"); print("  proot NEEDED libtalloc.so.2 -> libtalloc.so:", ok)
    exe, ok = replace_dynstr(exe, "/data/data/com.termux/files/usr/lib", "$ORIGIN"); print("  proot RUNPATH -> $ORIGIN:", ok)
    written.append(("libproot.so", exe))
    written.append(("libproot-loader.so", proot[prefix + "libexec/proot/loader"]))

    lib = next(v for k, v in talloc.items() if re.match(re.escape(prefix) + r"lib/libtalloc\.so\.2\.\d+\.\d+$", k))
    lib, ok = replace_dynstr(lib, "libtalloc.so.2", "libtalloc.so"); print("  talloc SONAME -> libtalloc.so:", ok)
    written.append(("libtalloc.so", lib))
    written.append(("libandroid-shmem.so", shmem[prefix + "lib/libandroid-shmem.so"]))

    # ANGLE (GLES on Vulkan) for the virgl GPU server, which itself is built from source by tools/build-virgl.py
    # (Termux's virglrenderer-android binary turns every DXT texture black). The emulator's own EGL lacks
    # EGL_KHR_surfaceless_context, which virglrenderer needs; ANGLE has it.
    angle = termux_pkg("angle-android")
    for lib in ("libEGL_angle.so", "libGLESv2_angle.so", "libGLESv1_CM_angle.so", "libfeature_support_angle.so"):
        written.append((lib, angle[prefix + "opt/angle-android/vulkan/" + lib]))

    deb = index(f"{DEBIAN}/dists/trixie/main/binary-{DEBIAN_ARCH}/Packages.xz")["busybox-static"]
    print(f"debian busybox-static {deb['Version']}")
    bb = deb_files(get(f"{DEBIAN}/{deb['Filename']}"))
    written.append(("libbusybox.so", next(v for k, v in bb.items() if k.endswith("bin/busybox"))))

    for name, blob in written:
        with open(os.path.join(OUT, name), "wb") as f:
            f.write(blob)
        print(f"wrote {ABI}/{name} ({len(blob)} bytes)")


if __name__ == "__main__":
    main()
