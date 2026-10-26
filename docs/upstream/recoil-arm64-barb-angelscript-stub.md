# DRAFT (not posted): beyond-all-reason/RecoilEngine

**Title:** arm64 Linux: BARb (CircuitAI) fails to load: undefined symbol CallARM64RetInMemory

**Body:**

With the official `recoil_2026.07.04_arm64-linux.7z` (also CircuitAI `barbarian` at f4a6ca3), the first BARb AI
aborts the engine when it loads its script:

```
Skirmish AI <BARbarIAn-stable>: Load script: LuaRules/Configs/BARb/stable/script/hard/init.as
./spring-headless: symbol lookup error: .../AI/Skirmish/BARb/stable/libSkirmishAI.so: undefined symbol: CallARM64RetInMemory
```

`nm -D libSkirmishAI.so | grep CallARM64` lists `U CallARM64 CallARM64Double CallARM64Float CallARM64Ret128
CallARM64RetInMemory`.

**Cause:** AngelScript's native calling convention on arm64 needs its assembly stub. `AI/Skirmish/BARb/CMakeLists.txt`
adds `as_callfunc_arm64_xcode.S` for `APPLE` only; on Linux arm64 `as_callfunc_arm64.cpp` is compiled but
`as_callfunc_arm64_gcc.S` never is, so the library ships with unresolved symbols.

**Check:** `as_callfunc_arm64_gcc.S` assembled on its own (`aarch64-linux-gnu-gcc -shared -fPIC`) and preloaded makes
both BARb instances initialize ("BARbarIAn 1.6.28 (0) Initialized!") and the game run (qemu-aarch64 and an arm64
phone); without it the engine exits 127 at AI load.

**Fix:** add `as_callfunc_arm64_gcc.S` to the BARb sources on non-Apple aarch64 (a 6-line CMake change; we have it
ready as a CircuitAI PR if this issue is accepted).

_This report was written with the help of an AI assistant (Claude); the failure and the fix were checked by running
the engine._
