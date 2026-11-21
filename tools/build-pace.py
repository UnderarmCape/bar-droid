"""Builds app/src/abi-arm64-v8a/assets/bardroid/libbardroid_pace.so (the engine's frame cap and hidden-window events,
tools/pace/pace.c) for the phone build, and app/src/abi-x86_64/assets/bardroid/libbardroid_pace-x86_64.so for the
emulator build: glibc shared libraries
made with the NDK's clang, no sysroot (pace.c declares what it uses).

  python -I tools/build-pace.py
  python -I tools/build-pace.py --dev   # also build/libbardroid_pace_dev.so (arm64): the GL call counter
                                        # (BARDROID_DEV_GL_COUNT), never in the APK; dev-env.sh preloads it instead
"""
import glob, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
NDK = glob.glob(os.path.join(HERE, "..", "..", "toolchain", "android-sdk", "ndk", "*"))
if not NDK:
    sys.exit("no NDK under toolchain/android-sdk/ndk")
CLANG = os.path.join(sorted(NDK)[-1], "toolchains", "llvm", "prebuilt", "windows-x86_64", "bin", "clang.exe")
SRC = os.path.join(HERE, "pace", "pace.c")
# (each ABI's in its own assets folder, which only that ABI's build packs: app/build.gradle)
ASSETS = {"aarch64-linux-gnu": os.path.join(HERE, "..", "app", "src", "abi-arm64-v8a", "assets", "bardroid"),
          "x86_64-linux-gnu": os.path.join(HERE, "..", "app", "src", "abi-x86_64", "assets", "bardroid")}

for target, name in (("aarch64-linux-gnu", "libbardroid_pace.so"), ("x86_64-linux-gnu", "libbardroid_pace-x86_64.so")):
    out = os.path.join(ASSETS[target], name)
    subprocess.run([CLANG, "--target=" + target, "-O2", "-fPIC", "-shared", "-nostdlib", "-fuse-ld=lld",
                    "-ffreestanding", "-fno-stack-protector", "-Wall", "-Wextra",
                    "-Wl,--hash-style=gnu,--build-id=none,-soname,libbardroid_pace.so,-z,noexecstack",
                    "-o", out, SRC], check=True)
    print("built", os.path.normpath(out), os.path.getsize(out), "bytes")

if "--dev" in sys.argv:
    out = os.path.join(HERE, "..", "build", "libbardroid_pace_dev.so")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run([CLANG, "--target=aarch64-linux-gnu", "-O2", "-fPIC", "-shared", "-nostdlib", "-fuse-ld=lld",
                    "-ffreestanding", "-fno-stack-protector", "-Wall", "-Wextra", "-DBARDROID_DEV_GL_COUNT",
                    "-Wl,--hash-style=gnu,--build-id=none,-soname,libbardroid_pace.so,-z,noexecstack",
                    "-o", out, SRC], check=True)
    print("built", os.path.normpath(out), os.path.getsize(out), "bytes (dev: GL call counter)")
