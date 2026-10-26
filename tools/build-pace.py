"""Builds app/src/main/assets/bardroid/libbardroid_pace.so (the engine's frame cap and hidden-window events,
tools/pace/pace.c) for the phone build, and libbardroid_pace-x86_64.so for the emulator build: glibc shared libraries
made with the NDK's clang, no sysroot (pace.c declares what it uses).

  python -I tools/build-pace.py
"""
import glob, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
NDK = glob.glob(os.path.join(HERE, "..", "..", "toolchain", "android-sdk", "ndk", "*"))
if not NDK:
    sys.exit("no NDK under toolchain/android-sdk/ndk")
CLANG = os.path.join(sorted(NDK)[-1], "toolchains", "llvm", "prebuilt", "windows-x86_64", "bin", "clang.exe")
SRC = os.path.join(HERE, "pace", "pace.c")
ASSETS = os.path.join(HERE, "..", "app", "src", "main", "assets", "bardroid")

for target, name in (("aarch64-linux-gnu", "libbardroid_pace.so"), ("x86_64-linux-gnu", "libbardroid_pace-x86_64.so")):
    out = os.path.join(ASSETS, name)
    subprocess.run([CLANG, "--target=" + target, "-O2", "-fPIC", "-shared", "-nostdlib", "-fuse-ld=lld",
                    "-ffreestanding", "-fno-stack-protector", "-Wall", "-Wextra",
                    "-Wl,--hash-style=gnu,--build-id=none,-soname,libbardroid_pace.so,-z,noexecstack",
                    "-o", out, SRC], check=True)
    print("built", os.path.normpath(out), os.path.getsize(out), "bytes")
