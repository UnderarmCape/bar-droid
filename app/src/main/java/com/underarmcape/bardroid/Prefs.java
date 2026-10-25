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

    // Pinned content versions. The engine must match what BAR's servers run for online play.
    public static String engineVersion = "2026.07.04";
    public static String engineUrl = "https://github.com/beyond-all-reason/RecoilEngine/releases/download/2026.07.04/recoil_2026.07.04_" + ENGINE_ARCH + ".7z";
    public static String rootfsManifestUrl = "https://github.com/debuerreotype/docker-debian-artifacts/raw/dist-" + DEBIAN_ARCH + "/trixie/oci/blobs/image-manifest.json";
    public static String rootfsBlobUrl = "https://github.com/debuerreotype/docker-debian-artifacts/raw/dist-" + DEBIAN_ARCH + "/trixie/oci/blobs/rootfs.tar.gz";
    /** Adreno-only Mesa build; the emulator build keeps Debian's Mesa (llvmpipe) and skips this download. */
    public static String mesaUrl = EMULATOR_BUILD ? "" : "https://github.com/lfdevs/mesa-for-android-container/releases/download/mesa-26.2.0-devel-20260709/mesa-for-android-container_26.2.0-devel-20260709_debian_trixie_arm64.tar.gz";
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
    public static float uiScale = 1.4f;
    public static boolean shadows = false;
    public static boolean compressTextures = true;
    public static boolean noSeccomp = false;
    public static boolean verboseX = false;
    public static boolean audio = true;
    public static String aiName = "BARb";
    public static String aiDifficulty = "Normal";
    public static int controllerPort = 28777;

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
        if (!EMULATOR_BUILD) mesaUrl = s.getString("mesaUrl", mesaUrl);
        gameTag = s.getString("gameTag", gameTag);
        lobbyTag = s.getString("lobbyTag", lobbyTag);
        mapName = s.getString("mapName", mapName);
        String driver = s.getString("mesaDriver", mesaDriver);
        boolean valid = EMULATOR_BUILD ? (driver.equals("virpipe") || driver.equals("llvmpipe"))
                                       : (driver.equals("kgsl") || driver.equals("zink"));
        if (valid) mesaDriver = driver;
        forceCompat45 = s.getBoolean("forceCompat45", forceCompat45);
        workerThreads = s.getInt("workerThreads", workerThreads);
        uiScale = s.getFloat("uiScale", uiScale);
        shadows = s.getBoolean("shadows", shadows);
        compressTextures = s.getBoolean("compressTextures", compressTextures);
        noSeccomp = s.getBoolean("noSeccomp", noSeccomp);
        verboseX = s.getBoolean("verboseX", verboseX);
        audio = s.getBoolean("audio", audio);
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
                .putFloat("uiScale", uiScale)
                .putBoolean("shadows", shadows)
                .putBoolean("compressTextures", compressTextures)
                .putBoolean("noSeccomp", noSeccomp)
                .putBoolean("verboseX", verboseX)
                .putBoolean("audio", audio)
                .putString("aiName", aiName)
                .putString("aiDifficulty", aiDifficulty)
                .apply();
    }
}
