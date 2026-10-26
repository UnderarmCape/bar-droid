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
    /** Frame cap (phone build, libbardroid_pace.so): 30 fps, or experimental 60 fps. */
    public static boolean fps60 = false;
    /** Opening the app from its icon starts the lobby (LauncherActivity). */
    public static boolean autoLobby = true;
    /**
     * Singleplayer (skirmish, the lobby's own games) plays Kailil's controller build, BAR Controller Support v0.8.5, as
     * BAR's developer game (Installer.installGamepadGame); online games always play BAR's released game.
     */
    public static boolean gamepadGame = true;
    /** Each lobby/skirmish start first updates BAR like its PC launcher (Updater, docs/UPDATES.md). */
    public static boolean autoUpdate = true;

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
        fps60 = s.getBoolean("fps60", fps60);
        autoLobby = s.getBoolean("autoLobby", autoLobby);
        gamepadGame = s.getBoolean("gamepadGame", gamepadGame);
        autoUpdate = s.getBoolean("autoUpdate", autoUpdate);
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
                .remove("touchOnly")   // the touch-only mode is gone
                .putBoolean("fps60", fps60)
                .putBoolean("autoLobby", autoLobby)
                .putBoolean("gamepadGame", gamepadGame)
                .putBoolean("autoUpdate", autoUpdate)
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
