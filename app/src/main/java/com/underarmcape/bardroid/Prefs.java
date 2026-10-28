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
    public static String mapName = "Supreme Isthmus v2.1";

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
    public static String aiName = "BARb";
    public static String aiDifficulty = "Normal";
    public static int controllerPort = 28777;
    /** Finger gestures for an RTS (RtsTouch) instead of Termux:X11's desktop touch modes. */
    public static boolean rtsTouch = true;
    /**
     * A mouse and a keyboard played as on a PC (MouseKeyboard): the mouse captured as BAR's own pointer, every key and
     * Android's shortcuts to the game. Off: Termux:X11's handling (its Display settings).
     */
    public static boolean mouseKeyboard = true;
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
     */
    public static int renderScale = 100;
    /** Opening the app from its icon starts the lobby (LauncherActivity). */
    public static boolean autoLobby = true;
    /**
     * Singleplayer (skirmish, the lobby's own games) plays Kailil's controller build, BAR Controller Support v0.8.5, as
     * BAR's developer game (Installer.installGamepadGame); online games always play BAR's released game.
     */
    public static boolean gamepadGame = true;
    /** Each lobby/skirmish start first updates BAR like its PC launcher (Updater, docs/UPDATES.md). */
    public static boolean autoUpdate = true;
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
        mapName = s.getString("mapName", mapName);
        String driver = s.getString("mesaDriver", mesaDriver);
        boolean valid = EMULATOR_BUILD ? (driver.equals("virpipe") || driver.equals("llvmpipe"))
                                       : (driver.equals("kgsl") || driver.equals("zink"));
        if (valid) mesaDriver = driver;
        forceCompat45 = s.getBoolean("forceCompat45", forceCompat45);
        workerThreads = s.getInt("workerThreads", workerThreads);
        noSeccomp = s.getBoolean("noSeccomp", noSeccomp);
        verboseX = s.getBoolean("verboseX", verboseX);
        audio = s.getBoolean("audio", audio);
        rtsTouch = s.getBoolean("rtsTouch", rtsTouch);
        mouseKeyboard = s.getBoolean("mouseKeyboard", mouseKeyboard);
        fpsCap = s.getInt("frameCap", fpsCap);
        if (fpsCap != 0 && fpsCap != 30 && fpsCap != 60) fpsCap = 30;
        renderScale = s.getInt("renderScale", renderScale);
        if (renderScale != 85 && renderScale != 70) renderScale = 100;
        autoLobby = s.getBoolean("autoLobby", autoLobby);
        gamepadGame = s.getBoolean("gamepadGame", gamepadGame);
        autoUpdate = s.getBoolean("autoUpdate", autoUpdate);
        lobbyBridge = s.getBoolean("lobbyBridgeOn", lobbyBridge);
        upscale = s.getBoolean("upscale", upscale);
        upscaleCompare = s.getBoolean("upscaleCompareOn", upscaleCompare);
        aiName = s.getString("aiName", aiName);
        aiDifficulty = s.getString("aiDifficulty", aiDifficulty);
    }

    public static void save(Context ctx) {
        ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit()
                .putString("mesaUrl", mesaUrl)
                .putString("gameTag", gameTag)
                .putString("lobbyTag", lobbyTag)
                .putString("mapName", mapName)
                .putString("mesaDriver", mesaDriver)
                .putBoolean("forceCompat45", forceCompat45)
                .putInt("workerThreads", workerThreads)
                .remove("uiScale").remove("shadows")   // gone: launch-bar.sh sets ui_scale per Fold screen, shadows off
                .remove("compressTextures")   // gone: CompressTextures is always 0 (springsettings.cfg)
                .putBoolean("noSeccomp", noSeccomp)
                .putBoolean("verboseX", verboseX)
                .putBoolean("audio", audio)
                .putBoolean("rtsTouch", rtsTouch)
                .putBoolean("mouseKeyboard", mouseKeyboard)
                .remove("touchOnly")   // the touch-only mode is gone
                .remove("fps60").remove("fpsCap")   // the measuring days' cap, see fpsCap
                .putInt("frameCap", fpsCap)
                .putInt("renderScale", renderScale)
                .putBoolean("autoLobby", autoLobby)
                .putBoolean("gamepadGame", gamepadGame)
                .putBoolean("autoUpdate", autoUpdate)
                .remove("lobbyBridge")   // the old default (off), see lobbyBridge
                .putBoolean("lobbyBridgeOn", lobbyBridge)
                .putBoolean("upscale", upscale)
                .remove("upscaleCompare")   // the comparison's first default (on), see upscaleCompare
                .putBoolean("upscaleCompareOn", upscaleCompare)
                .putString("aiName", aiName)
                .putString("aiDifficulty", aiDifficulty)
                .apply();
    }

    /** The last lobby the app started exited with an error within a minute: show the launcher instead of retrying. */
    public static boolean lobbyFailedFast(Context ctx) {
        return ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).getBoolean("lobbyFailedFast", false);
    }

    public static void setLobbyFailedFast(Context ctx, boolean failed) {
        ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putBoolean("lobbyFailedFast", failed).apply();
    }
}
