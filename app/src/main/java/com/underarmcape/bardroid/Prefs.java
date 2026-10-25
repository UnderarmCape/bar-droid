package com.underarmcape.bardroid;

import android.content.Context;
import android.content.SharedPreferences;

/** Launcher settings. Loaded once at startup; the settings screen writes through {@link #save}. */
public final class Prefs {
    private static final String FILE = "bardroid";

    // Pinned content versions. The engine must match what BAR's servers run for online play.
    public static String engineVersion = "2026.07.04";
    public static String engineUrl = "https://github.com/beyond-all-reason/RecoilEngine/releases/download/2026.07.04/recoil_2026.07.04_arm64-linux.7z";
    public static String rootfsManifestUrl = "https://github.com/debuerreotype/docker-debian-artifacts/raw/dist-arm64v8/trixie/oci/blobs/image-manifest.json";
    public static String rootfsBlobUrl = "https://github.com/debuerreotype/docker-debian-artifacts/raw/dist-arm64v8/trixie/oci/blobs/rootfs.tar.gz";
    public static String mesaUrl = "https://github.com/lfdevs/mesa-for-android-container/releases/download/mesa-26.2.0-devel-20260709/mesa-for-android-container_26.2.0-devel-20260709_debian_trixie_arm64.tar.gz";
    public static String gameTag = "byar:test";
    public static String lobbyTag = "byar-chobby:test";
    public static String mapName = "Supreme Isthmus v2.1";

    // Runtime knobs
    public static String mesaDriver = "kgsl";      // kgsl = Freedreno gallium on /dev/kgsl-3d0; zink = Turnip + Zink
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

    public static void load(Context ctx) {
        SharedPreferences s = ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE);
        engineVersion = s.getString("engineVersion", engineVersion);
        engineUrl = s.getString("engineUrl", engineUrl);
        mesaUrl = s.getString("mesaUrl", mesaUrl);
        gameTag = s.getString("gameTag", gameTag);
        lobbyTag = s.getString("lobbyTag", lobbyTag);
        mapName = s.getString("mapName", mapName);
        mesaDriver = s.getString("mesaDriver", mesaDriver);
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
                .putString("engineVersion", engineVersion)
                .putString("engineUrl", engineUrl)
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
