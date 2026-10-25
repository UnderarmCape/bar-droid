# BARb / CircuitAI on Linux arm64: missing AngelScript stub

**Symptom** (official `recoil_2026.07.04_arm64-linux.7z`, also current CircuitAI `barbarian` branch at f4a6ca3):

```
Skirmish AI <BARbarIAn-stable>: Load script: LuaRules/Configs/BARb/stable/script/hard/init.as
./spring-headless: symbol lookup error: .../AI/Skirmish/BARb/stable/libSkirmishAI.so: undefined symbol: CallARM64RetInMemory
```

`nm -D libSkirmishAI.so | grep CallARM64` shows `U CallARM64 CallARM64Double CallARM64Float CallARM64Ret128 CallARM64RetInMemory`.

**Cause:** AngelScript's native calling convention on arm64 needs a hand-written assembly stub.
`AI/Skirmish/BARb/CMakeLists.txt` only adds `as_callfunc_arm64_xcode.S` for `APPLE`; on Linux arm64 the
C++ half (`as_callfunc_arm64.cpp`) is compiled but `as_callfunc_arm64_gcc.S` never is, so the shared object
ships with unresolved symbols. The engine aborts the moment the first BARb AI loads its script.

**Workaround (phase 1, no rebuild):** `libasarm64.so` here is just `as_callfunc_arm64_gcc.S` assembled with
`aarch64-linux-gnu-gcc -shared -fPIC`. Preloading it resolves the symbols:

```
LD_PRELOAD=/root/bar-droid/phase1/arm64-ai-fix/libasarm64.so ./spring ...   # run-bar.sh does this
```

Verified 2026-10-25 under qemu-aarch64: with the preload both BARb instances initialize
("BARbarIAn 1.6.28 (0) Initialized!") and the game starts; without it the engine exits 127 at AI load.

**Proper fix:** `circuitai-cmake-arm64-linux.patch` (6 lines) in the CircuitAI repo
(github.com/rlcevg/CircuitAI, branch `barbarian`, vendored into RecoilEngine as `AI/Skirmish/BARb`).
File it as an issue on RecoilEngine first (their AI policy wants an accepted issue before a PR, and asks
that AI assistance be disclosed), attach the log lines above, then offer the patch.

License: `as_callfunc_arm64_gcc.S` is part of AngelScript (zlib license), redistributable.
