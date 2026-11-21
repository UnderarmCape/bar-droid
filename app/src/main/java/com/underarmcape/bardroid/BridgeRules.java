package com.underarmcape.bardroid;

import java.io.File;
import java.io.IOException;
import java.net.URI;
import java.util.Locale;

/**
 * What the lobby bridge ({@link LobbyBridge}) lets a client do. The bridge listens on 127.0.0.1 and Android cannot say
 * which app connects: any app on the phone could, and its resource downloads wrote any file in the engine's write
 * folder, a widget into LuaUI/Widgets among them (the release audit, 2026-11-21). So, whoever it is: a resource only
 * over https from BAR's own hosts (*.beyondallreason.dev), only into the places BAR's lobby downloads plain files to
 * (Chobby's plugins_window.lua: the plugin manifest, the plugins' pictures and readmes; gui_open_skill_snapshot.lua:
 * the skill ratings), as data, at most {@link #RESOURCE_MAX_BYTES}; a replay read only from demos/; a line at most
 * {@link #LINE_MAX_CHARS}, at most {@link #CLIENTS_MAX} connections at once. Archives to unpack (engines, a plugin's
 * zip) the bridge refuses as before. Pure Java: tools/status-text-test.ps1 checks it on the laptop.
 */
final class BridgeRules {
    private BridgeRules() {}

    static final long RESOURCE_MAX_BYTES = 64L << 20;
    static final int LINE_MAX_CHARS = 1 << 20;
    static final int CLIENTS_MAX = 2;

    /** Null when the resource download is allowed, else why not. */
    static String resource(String url, String dest) {
        URI u;
        try { u = new URI(url); } catch (Exception e) { return "not a URL"; }
        if (!"https".equalsIgnoreCase(u.getScheme())) return "not https";
        String host = u.getHost() == null ? "" : u.getHost().toLowerCase(Locale.ROOT);
        if (!(host.equals("beyondallreason.dev") || host.endsWith(".beyondallreason.dev")))
            return "not one of BAR's hosts: " + host;
        if (u.getRawUserInfo() != null || (u.getPort() != -1 && u.getPort() != 443)) return "an unusual URL";
        if (dest == null || dest.isEmpty() || dest.startsWith("/") || dest.contains("\\") || dest.contains("\0"))
            return "a bad destination";
        for (String part : dest.split("/", -1))
            if (part.isEmpty() || part.startsWith(".")) return "a bad destination";   // (no "..", no hidden files)
        if (dest.equals("LuaUI/Widgets/manifests.json")) return null;
        if (dest.matches("plugins/[^/]+\\.(png|jpg|jpeg|md)")) return null;
        if (dest.matches("data-processing-main/data_export/[^/]+\\.(csv|json)")) return null;
        return "not a place the lobby downloads to";
    }

    /** The replay file under base/demos for the lobby's relative path, or null when it is anywhere else. */
    static File replay(File base, String rel) throws IOException {
        if (rel == null || !rel.startsWith("demos/")) return null;
        File demos = new File(base, "demos").getCanonicalFile();
        File f = new File(base, rel).getCanonicalFile();
        return f.getPath().startsWith(demos.getPath() + File.separator) ? f : null;
    }
}
