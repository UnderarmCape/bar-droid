"""Builds app/src/main/assets/bardroid/libbardroid_pace.so (the engine's frame cap, tools/pace/pace.c) for the phone
build: an aarch64 glibc shared library made with the NDK's clang, no sysroot (pace.c declares what it uses).

  python -I tools/build-pace.py
"""
import glob, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
NDK = glob.glob(os.path.join(HERE, "..", "..", "toolchain", "android-sdk", "ndk", "*"))
if not NDK:
    sys.exit("no NDK under toolchain/android-sdk/ndk")
CLANG = os.path.join(sorted(NDK)[-1], "toolchains", "llvm", "prebuilt", "windows-x86_64", "bin", "clang.exe")
SRC = os.path.join(HERE, "pace", "pace.c")
OUT = os.path.join(HERE, "..", "app", "src", "main", "assets", "bardroid", "libbardroid_pace.so")

subprocess.run([CLANG, "--target=aarch64-linux-gnu", "-O2", "-fPIC", "-shared", "-nostdlib", "-fuse-ld=lld",
                "-ffreestanding", "-fno-stack-protector", "-Wall", "-Wextra",
                "-Wl,--hash-style=gnu,--build-id=none,-soname,libbardroid_pace.so,-z,noexecstack",
                "-o", OUT, SRC], check=True)
print("built", os.path.normpath(OUT), os.path.getsize(OUT), "bytes")
