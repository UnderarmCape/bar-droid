# Building BAR Droid

For developers. How the app works: [ARCHITECTURE.md](ARCHITECTURE.md). The rules for changes:
[CONTRIBUTING.md](../CONTRIBUTING.md).

## Toolchain (Windows 10/11 x64)

Everything goes into one folder: no global installs, nothing in the registry, AppData or the user profile.

1. `Install Toolchain.bat --accept-licenses` (one time; downloads a portable JDK 21, Git, the Android SDK/NDK and
   small host tools, about 6 GB; `--accept-licenses` accepts the
   [Android SDK terms](https://developer.android.com/studio/terms)). It also fetches Termux:X11 at the pinned commit
   and applies `patches/`.
2. `Build APK.bat phone` builds the phone app (arm64) into `apk\bar-droid-phone-debug.apk`; `Build APK.bat` alone
   builds the x86_64 app for the Android emulator.
3. `Install on Phone.bat` installs it on the phone connected over adb (USB debugging, or `Pair Phone.bat` for
   wireless debugging), then in the app: **Install / Update** (about 4 GB from BAR's servers), then the lobby or
   **Play vs AI**.

The toolchain folder is `toolchain\` inside the checkout, a `toolchain` folder beside it if one is installed there,
or wherever `BARDROID_TOOLCHAIN` points (`scripts\env.bat`). APKs land in `apk\` beside it (`BARDROID_OUT`
overrides). Logs from the phone: `Get Logs.bat phone`, or **Share logs** in the app. `Run in Emulator.bat` runs the
x86_64 build in an emulator (slow; a test bench only).

Versions: AGP 9.3.1, Gradle 9.8.2 (wrapper), NDK 29.0.14206865, CMake 3.22.1, JDK 21. One ABI per APK
(`-PbardroidAbi=arm64-v8a|x86_64`). On Linux, `tools/fetch-termux-x11.sh` and `./gradlew :app:assembleDebug
-PbardroidAbi=arm64-v8a` do the same as the launchers (with an Android SDK and NDK of those versions).

The prebuilt helpers in `app/src/main/jniLibs/` are committed; rebuild them with `tools/fetch-prebuilts.py <abi>`,
`tools/build-proot.py <abi>` (after fetch-prebuilts) and `tools/build-virgl.py <abi>`.

The phone engine (docs/ENGINE-DEFAULT.md) is not in the repository (42 MB a build): build the engine branch with the
engine worktree's `tools\engine-sim\build-engine.ps1`, run its gate, then `tools\phone-engine-release.ps1 -Build
<name>` puts it in `C:\Tools\BARANDROID\engine-sim\release\phone-engine\<version>`, and `bardroid.phoneEngine=<that
release folder>` in `local.properties` makes arm64 builds carry it (17-19 MB compressed). Without the line the APK
plays BAR's official engine only.

## Checks

`powershell -ExecutionPolicy Bypass -File tools\laptop-tests.ps1` runs every check that needs no phone (about
5 minutes): the downloader, settings merge, updater rollback and Share logs' redaction in Java, the lobby bridge and the lobby touch widget
in BAR's real lobby, the in-game widgets in a real skirmish, and the Lua lint. The game checks use BAR's Windows
install (`%LOCALAPPDATA%\Programs\Beyond-All-Reason`, read only, never changed; `BAR_DATA` points elsewhere).

On Linux (and in CI): `sh tools/java-checks.sh` runs the Java checks with the JDK on `JAVA_HOME` or the path. CI
(`.github/workflows/build.yml`: the phone APK, the Java checks, the Lua lint) runs on demand and on pull requests, not
on every push; on the project's private repository it is switched off between runs (Actions, build, "Enable
workflow", then "Run workflow").

Per widget: `tools\touch-widget-test.ps1 [-GamepadGame]`, `tools\spectate-test.ps1 [-Replay <file.sdfz>]`,
`tools\lobby-touch-test.ps1`, `tools\lobby-bridge-test.ps1`. On the phone: `tools\dock-phone-test.ps1` (the upright
dock by real taps, any screen shape), `tools\pad-test.ps1 [-Online | -Dgun | -Share | -Chat]` (the gamepad),
`tools\fp-save-test.ps1` (first person through BAR's settings save), `tools\pace-test.ps1` (the pace library),
`tools\lobby-phone-test.ps1` (the lobby widget, with a virtual pad's Start), `tools\touch-phone-test.ps1` (the touch
camera at the map's edge, driven through the touch log), `tools\remake-check.ps1` (the phone's remakes of the app's
copies of BAR's widgets), `tools\stripes-test.ps1` (skirmishes with Adreno's compressed render targets off and on, a
screenshot montage), `tools\phone-bench.ps1` (BAR's benchmark scenario or a replay on a hot phone, results in
`build\phone-bench.csv`).
Profiling on the laptop: `tools\profile-benchmark.ps1`, `tools\profile-big-game.ps1`. The full list with options is
in [CLAUDE.md](../CLAUDE.md) ("Build / run").

## Releasing

A release is built from a clean checkout of `main`, checked, and published by the project's owner.

1. `tools\laptop-tests.ps1` passes; the phone build was played on a phone (lobby, an online game, a skirmish).
2. Raise `bardroidVersionName` and `bardroidVersionCode` in `gradle.properties`; add the version's section to
   `CHANGELOG.md`.
3. `Build APK.bat phone release`: the project's own icon, signed with the release key, named
   `bar-droid-phone-<version>.apk`. The key is the publisher's: `bardroid.keystore=<path>` and
   `bardroid.keyAlias=<alias>` in `local.properties`, its password in `BARDROID_KEYSTORE_PASSWORD` (and
   `BARDROID_KEY_PASSWORD` if the key's differs). Make it once with the JDK's `keytool -genkeypair -keystore <path>
   -alias bardroid -keyalg RSA -keysize 4096 -validity 10000` and keep it safe: every later version must be signed
   with the same key, or phones refuse the update. Without a key Gradle itself (`gradlew :app:assembleRelease`,
   e.g. on Linux) builds `bar-droid-phone-<version>-unsigned.apk`, for signing elsewhere; phones refuse it unsigned.
4. `powershell -ExecutionPolicy Bypass -File tools\publish-check.ps1 -Apk apk\bar-droid-phone-<version>.apk`.
5. Tag the commit `v<version>`, push, and make a GitHub release with the APK and the CHANGELOG section.

Debug builds (`Build APK.bat phone`) are signed with the public debug key in `app/bardroid-debug.jks`: fine for
testing, not for anything others install and update.
