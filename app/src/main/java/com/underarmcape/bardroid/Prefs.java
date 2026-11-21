package com.underarmcape.bardroid;

import android.content.Context;
import android.content.SharedPreferences;

/** Launcher settings. Loaded once at startup; the settings screen writes through {@link #save}. */
public final class Prefs {
    private static final String FILE = "bardroid";

    /**
     * The emulator build (x86_64, the default) runs amd64 Debian + the amd64 engine with Mesa's software renderer;
     * the phone build (arm64-v8a) runs arm64 Debian + the arm64 engine on Adreno through Mesa for Android containers.
     */
    public static final boolean EMULATOR_BUILD = "x86_64".equals(BuildConfig.TARGET_ABI);
    private static final String DEBIAN_ARCH = EMULATOR_BUILD ? "amd64" : "arm64v8";       // debuerreotype branch names
    private static final String ENGINE_ARCH = EMULATOR_BUILD ? "amd64-linux" : "arm64-linux";

    // Pinned content versions for a first install. The engine must match what BAR's servers run for online play:
    // after the install, Updater follows BAR's launcher config (engine and rapid tags, docs/UPDATES.md).
    public static String engineVersion = "2026.07.04";
    public static String engineUrl = "https://github.com/beyond-all-reason/RecoilEngine/releases/download/2026.07.04/recoil_2026.07.04_" + ENGINE_ARCH + ".7z";
    public static String rootfsManifestUrl = "https://github.com/debuerreotype/docker-debian-artifacts/raw/dist-" + DEBIAN_ARCH + "/trixie/oci/blobs/image-manifest.json";
    public static String rootfsBlobUrl = "https://github.com/debuerreotype/docker-debian-artifacts/raw/dist-" + DEBIAN_ARCH + "/trixie/oci/blobs/rootfs.tar.gz";
    /**
     * Adreno-only Mesa build; the emulator build keeps Debian's Mesa and skips this download. 27.0.0-devel-20261025 is
     * the first release with the KGSL Present wait fence (lfdevs PR #96): older ones flash black frames under
     * Termux:X11 because the X server reads frames before the GPU has finished them.
     */
    public static String mesaUrl = EMULATOR_BUILD ? "" : "https://github.com/lfdevs/mesa-for-android-container/releases/download/mesa-27.0.0-devel-20261025/mesa-for-android-container_27.0.0-devel-20261025_debian_trixie_arm64.tar.gz";
    /** Earlier defaults: a saved one of these follows the build's default instead of pinning the old Mesa. */
    static final String[] OLD_MESA_URLS = {
            "https://github.com/lfdevs/mesa-for-android-container/releases/download/mesa-26.2.0-devel-20260709/mesa-for-android-container_26.2.0-devel-20260709_debian_trixie_arm64.tar.gz",
    };
    public static String gameTag = "byar:test";
    public static String lobbyTag = "byar-chobby:test";
    /**
     * The skirmish map. An 8 GB phone (LauncherActivity.lowRam) gets the benchmark's smaller map until the player picks
     * one: in the low-memory mode 3 of 3 skirmishes on Starwatcher (75 MB) played through against 2 of 3 on Supreme
     * Isthmus (144 MB), the engine ~0.6 GB smaller (2026-10-30, docs/HISTORY.md "Fitting BAR into an 8 GB phone").
     * mapChosen: the player changed it in the launcher (the saved name is then theirs, whatever it is).
     */
    public static final String DEFAULT_MAP = "Supreme Isthmus v2.1";
    public static String mapName = DEFAULT_MAP;
    public static boolean mapChosen = false;

    // Runtime knobs
    /**
     * kgsl = Freedreno gallium on /dev/kgsl-3d0; zink = Turnip + Zink (phone build).
     * virpipe = Android's GLES through the bundled virgl server; llvmpipe = CPU rendering (emulator build).
     */
    public static String mesaDriver = EMULATOR_BUILD ? "virpipe" : "kgsl";
    public static boolean forceCompat45 = false;    // MESA_GL_VERSION_OVERRIDE=4.5COMPAT
    public static int workerThreads = 4;
    public static boolean noSeccomp = false;
    public static boolean verboseX = false;
    public static boolean audio = true;
    /** Finger gestures for an RTS (RtsTouch) instead of Termux:X11's desktop touch modes. */
    public static boolean rtsTouch = true;
    /** The game upright: the portrait dock for touch (Kailil, 2026-11-09; bardroid_portrait.lua, RtsTouch's pad). */
    public static boolean portrait = false;
    /**
     * With the phone's auto-rotate on, the lobby and the game turn upright or sideways as the phone is held, at any
     * time (Kailil, 2026-11-12: "so I can use vertical or landscape in one session anytime I want"); with it off,
     * {@link #portrait} decides. GameActivity.setRequestedOrientation.
     */
    public static boolean turnWithPhone = true;

    /** The phone's auto-rotate (Android's rotation lock off). */
    static boolean autoRotate(android.content.Context c) {
        return android.provider.Settings.System.getInt(c.getContentResolver(),
                android.provider.Settings.System.ACCELEROMETER_ROTATION, 0) == 1;
    }

    /**
     * A developer's build (debuggable: the debug APK the tools install): only then do the developer hooks work, a
     * dev-env.sh or dev-springsettings.cfg in the engine's write folder (launch-bar.sh, BARDROID_DEV) and the launcher's
     * "start" extra. A public release build ignores them: that folder is the engine's, which BAR's Lua can write, and a
     * dev-env.sh there runs as a shell script (2026-11-21).
     */
    static boolean developer(android.content.Context c) {
        return (c.getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    }

    /**
     * Whether a lobby or game starting now starts upright (its loading picture, launch-bar.sh's upright tweaks): the
     * setting, or turning with the phone, the screen's shape now (taller than 1.05 times its width, as
     * bardroid_portrait.lua's dock).
     */
    static boolean startsUpright(android.content.Context c) {
        if (!(turnWithPhone && autoRotate(c))) return portrait;
        android.view.Display d = c.getSystemService(android.hardware.display.DisplayManager.class)
                .getDisplay(android.view.Display.DEFAULT_DISPLAY);
        if (d == null) return portrait;
        android.util.DisplayMetrics m = new android.util.DisplayMetrics();
        d.getRealMetrics(m);
        return m.heightPixels > m.widthPixels * 1.05f;
    }
    /**
     * Sideways the same touch dock along the bottom (Kailil, 2026-11-12, layout A of the landscape mockups: build left,
     * minimap and resources in the middle, orders right); while a pad or mouse is used BAR's own screen layout.
     * launch-bar.sh: LuaUI/Config/bardroid_landdock.txt, read by bardroid_portrait.lua.
     */
    public static boolean landDock = true;
    /**
     * Android's, One UI's and DeX's keyboard shortcuts stay out of the game screen, their keys go to BAR
     * (KeyboardShortcuts). Off: Termux:X11's defaults.
     */
    public static boolean captureShortcuts = true;
    /**
     * Frame cap (phone build, libbardroid_pace.so): 30 or 60 fps, or 0 = none, the game drawing as fast as it can.
     * 30 by default: uncapped only for measuring (Kailil, 2026-10-27, after the benchmarks: "put the hard 30 fps lock
     * back on the phone. I resign to the fps tanking when the battle gets rough"). tools/phone-bench.ps1 -Cap sets it
     * for a run and puts the player's back. Saved as "frameCap": "fpsCap" (and the older "fps60" checkbox) held the
     * measuring days' none on Kailil's phone.
     */
    public static int fpsCap = 30;
    /**
     * The game's resolution, percent of the usual (GameActivity.MAX_SCREEN_PIXELS): 100, 85 or 70. Fewer pixels for the
     * GPU, enlarged onto the display (SGSR when "Sharper upscaling" is on). For the benchmark: does the GPU-bound late
     * game get faster with fewer pixels (Kailil, 2026-10-27: "find the best optimization to reduce that bottle neck")?
     * 0: native, the display's own pixels, no cap (Kailil, 2026-10-28: "put native res on now and run a test").
     * Values 5-99 other than those come only from the engine tools (profiling with next to no pixels).
     */
    public static int renderScale = 100;
    /** Opening the app from its icon starts the lobby (LauncherActivity). */
    public static boolean autoLobby = true;
    /** Each lobby/skirmish start first updates BAR like its PC launcher (Updater, docs/UPDATES.md). */
    public static boolean autoUpdate = true;
    /**
     * Games start on the phone engine, the APK's build of BAR's engine version (Installer.installPhoneEngine,
     * launch-bar.sh; docs/ENGINE-DEFAULT.md, Kailil 2026-11-13). Off: BAR's official engine.
     */
    public static boolean phoneEngine = true;
    /**
     * The app stands in for BAR's PC launcher behind the lobby (LobbyBridge): replays, web links, resource downloads.
     * On by default since 2026-10-27: the lobby assumes its launcher (the Replays tab hung on "Loading" without it).
     * Saved as "lobbyBridgeOn": the old key held the old default (off) on every phone that saved settings.
     */
    public static boolean lobbyBridge = true;
    /**
     * The X screen (smaller than the display: GameActivity.MAX_SCREEN_PIXELS) drawn onto the display through
     * Qualcomm's SGSR 1 instead of plain bilinear filtering (GameActivity, patch 0007).
     */
    public static boolean upscale = true;
    /**
     * SGSR on and off every 3 s with a label saying which, to judge it (Kailil, 2026-10-27: "Can it toggle on and off
     * every 3 seconds so I can see"; then "Turn off the compare and just leave the sgsr on"). Saved as
     * "upscaleCompareOn": the first key held the comparison's first default (on).
     */
    public static boolean upscaleCompare = false;
    /**
     * The late-game drop (Kailil, 2026-11-06: "Allow 50 percent resolution as the minimum late game drop. But make sure
     * the dev phone is running the max snapdragon upscaling sharpness. Upscaling should be doing the heavy lifting"):
     * when a game's frame rate stays under 27, bardroid_touch.lua asks for a lower resolution, a step at a time and only
     * while each step helps, never under 70 % of the render resolution's lines (GameActivity.updateRenderDrop; Kailil,
     * 2026-11-06, after watching 50 %: "keep it at 70 percent res drop as the minimum instead"). Off by default: on for
     * the dev phone's 30 fps target; on the Fold7 only with Kailil's say.
     */
    public static boolean lateDrop = false;
    /**
     * The downloaded maps kept under this many MB, the ones played longest ago deleted before a game or the lobby starts
     * (MapStore; Kailil, 2026-11-11: "Move forward with that. At the max map size to 3gb"). 0: no limit.
     */
    public static final int MAP_CAP_DEFAULT_MB = 3072;
    public static int mapCapMb = MAP_CAP_DEFAULT_MB;

    /** Guest environment that selects the OpenGL driver (used by the game launch and files/container.sh). */
    public static void putGpuEnv(java.util.Map<String, String> env) {
        env.put("BARDROID_GPU", mesaDriver);
        if ("llvmpipe".equals(mesaDriver) || "virpipe".equals(mesaDriver)) {
            env.put("LIBGL_ALWAYS_SOFTWARE", "1");
            env.put("GALLIUM_DRIVER", mesaDriver);
            if ("virpipe".equals(mesaDriver)) {
                env.put("VTEST_SOCKET_NAME", VirglServer.GUEST_SOCKET);
                // virgl on a GLES host only advertises a 2.1 compatibility context, but the host has the GL 4.3
                // features BAR uses (compute, SSBO, multi-draw-indirect): advertise 4.3 compatibility.
                env.put("MESA_GL_VERSION_OVERRIDE", "4.3COMPAT");
                env.put("MESA_GLSL_VERSION_OVERRIDE", "430");
            }
        } else {
            env.put("MESA_LOADER_DRIVER_OVERRIDE", mesaDriver);
        }
        if (forceCompat45) { env.put("MESA_GL_VERSION_OVERRIDE", "4.5COMPAT"); env.put("MESA_GLSL_VERSION_OVERRIDE", "450"); }
    }

    public static void load(Context ctx) {
        SharedPreferences s = ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE);
        // Engine version/URL are not user settings: they follow the build (and its ABI).
        if (!EMULATOR_BUILD) {
            String saved = s.getString("mesaUrl", mesaUrl);
            if (!java.util.Arrays.asList(OLD_MESA_URLS).contains(saved)) mesaUrl = saved;
        }
        gameTag = s.getString("gameTag", gameTag);
        lobbyTag = s.getString("lobbyTag", lobbyTag);
        mapChosen = s.getBoolean("mapChosen", false);
        mapName = s.getString("mapName", DEFAULT_MAP);
        if (!mapChosen && DEFAULT_MAP.equals(mapName) && LauncherActivity.lowRam(ctx)) mapName = Installer.BENCH_MAP;
        String driver = s.getString("mesaDriver", mesaDriver);
        boolean valid = EMULATOR_BUILD ? (driver.equals("virpipe") || driver.equals("llvmpipe"))
                                       : (driver.equals("kgsl") || driver.equals("zink"));
        if (valid) mesaDriver = driver;
        forceCompat45 = s.getBoolean("forceCompat45", forceCompat45);
        int workers = s.getInt("workerThreads", workerThreads);
        if (workers >= 1) workerThreads = workers;   // (as the launcher takes it; before it took any number)
        noSeccomp = s.getBoolean("noSeccomp", noSeccomp);
        verboseX = s.getBoolean("verboseX", verboseX);
        audio = s.getBoolean("audio", audio);
        rtsTouch = s.getBoolean("rtsTouch", rtsTouch);
        portrait = s.getBoolean("portrait", portrait);
        turnWithPhone = s.getBoolean("turnWithPhone", turnWithPhone);
        landDock = s.getBoolean("landDock", landDock);
        captureShortcuts = s.getBoolean("captureShortcuts", captureShortcuts);
        fpsCap = s.getInt("frameCap", fpsCap);
        if (fpsCap != 0 && fpsCap != 30 && fpsCap != 60) fpsCap = 30;
        renderScale = s.getInt("renderScale", renderScale);
        // (other values from 5 up are kept: the engine tools set them over adb to profile the CPU side alone, 10 = 1% of
        // the pixels; the launcher shows them as 100% and a Save there writes 100)
        if (renderScale != 0 && (renderScale < 5 || renderScale > 100)) renderScale = 100;
        autoLobby = s.getBoolean("autoLobby", autoLobby);
        autoUpdate = s.getBoolean("autoUpdate", autoUpdate);
        phoneEngine = s.getBoolean("phoneEngine", phoneEngine);
        lobbyBridge = s.getBoolean("lobbyBridgeOn", lobbyBridge);
        upscale = s.getBoolean("upscale", upscale);
        upscaleCompare = s.getBoolean("upscaleCompareOn", upscaleCompare);
        lateDrop = s.getBoolean("lateDrop", lateDrop);
        mapCapMb = s.getInt("mapCapMb", mapCapMb);
        if (mapCapMb != 0 && mapCapMb != 3072 && mapCapMb != 5120) {
            mapCapMb = MAP_CAP_DEFAULT_MB;
        }
    }

    public static void save(Context ctx) {
        ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit()
                .putString("mesaUrl", mesaUrl)
                .putString("gameTag", gameTag)
                .putString("lobbyTag", lobbyTag)
                .putString("mapName", mapName)
                .putBoolean("mapChosen", mapChosen)
                .putString("mesaDriver", mesaDriver)
                .putBoolean("forceCompat45", forceCompat45)
                .putInt("workerThreads", workerThreads)
                .remove("uiScale").remove("shadows")   // gone: launch-bar.sh sets ui_scale per Fold screen, shadows off
                .remove("compressTextures")   // gone: launch-bar.sh sets CompressTextures (1 only in its low-memory mode)
                .putBoolean("noSeccomp", noSeccomp)
                .putBoolean("verboseX", verboseX)
                .putBoolean("audio", audio)
                .putBoolean("rtsTouch", rtsTouch)
                .putBoolean("portrait", portrait)
                .putBoolean("turnWithPhone", turnWithPhone)
                .putBoolean("landDock", landDock)
                .remove("mouseKeyboard")   // the withdrawn mouse capture setting (b148e59)
                .putBoolean("captureShortcuts", captureShortcuts)
                .remove("touchOnly")   // the touch-only mode is gone
                .remove("fps60").remove("fpsCap")   // the measuring days' cap, see fpsCap
                .putInt("frameCap", fpsCap)
                .putInt("renderScale", renderScale)
                .putBoolean("autoLobby", autoLobby)
                .remove("gamepadGame")   // (v0.8.5's game, out of the app since 2026-11-06)
                .putBoolean("autoUpdate", autoUpdate)
                .putBoolean("phoneEngine", phoneEngine)
                .remove("lobbyBridge")   // the old default (off), see lobbyBridge
                .putBoolean("lobbyBridgeOn", lobbyBridge)
                .putBoolean("upscale", upscale)
                .remove("upscaleCompare")   // the comparison's first default (on), see upscaleCompare
                .putBoolean("upscaleCompareOn", upscaleCompare)
                .putBoolean("lateDrop", lateDrop)
                .putInt("mapCapMb", mapCapMb)
                .remove("aiName").remove("aiDifficulty")   // (stored, never used: the skirmish's AI is BARb, Installer)
                .apply();
    }

    /** The last lobby the app started exited with an error within a minute: show the launcher instead of retrying. */
    public static boolean lobbyFailedFast(Context ctx) {
        return ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).getBoolean("lobbyFailedFast", false);
    }

    public static void setLobbyFailedFast(Context ctx, boolean failed) {
        ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putBoolean("lobbyFailedFast", failed).apply();
    }

    /** The time of the last low-memory end of the app already told (GameService.noteLowMemoryExit). */
    public static long lowMemoryExitSeen(Context ctx) {
        return ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).getLong("lowMemoryExitSeen", 0);
    }

    public static void setLowMemoryExitSeen(Context ctx, long time) {
        ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putLong("lowMemoryExitSeen", time).apply();
    }
}
