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
    // (256 KB: the lobby's lines are short, a replay's path, a download's name, a second engine's start script)
    static final int LINE_MAX_CHARS = 256 << 10;
    static final int CLIENTS_MAX = 2;
    static final int DEPTH_MAX = 32;
    static final int LOG_MAX_CHARS = 300;

    /** How deep a JSON line nests: its { and [ outside strings (the lobby's messages: three or four). */
    static int depth(String line) {
        int d = 0, max = 0;
        boolean str = false, esc = false;
        for (int i = 0; i < line.length(); i++) {
            char c = line.charAt(i);
            if (str) {
                if (esc) esc = false;
                else if (c == '\\') esc = true;
                else if (c == '"') str = false;
            } else if (c == '"') str = true;
            else if (c == '{' || c == '[') max = Math.max(max, ++d);
            else if (c == '}' || c == ']') d--;
        }
        return max;
    }

    /**
     * A log line with a client's words in it, fit for launcher.log: at most LOG_MAX_CHARS, control characters (a JSON
     * escape's newline among them, which wrote lines of its own) as "?". Every client string had gone into the log
     * whole, and the log keeps its last 4,000 lines in memory: a few hundred lines of 1 MB from another app ran the
     * app out of memory (release overhaul audit, 2026-11-21).
     */
    static String clip(String s) {
        if (s == null) return "null";
        int n = Math.min(s.length(), LOG_MAX_CHARS);
        StringBuilder b = new StringBuilder(n + 3);
        for (int i = 0; i < n; i++) {
            char c = s.charAt(i);
            b.append(c < 0x20 || c == 0x7f ? '?' : c);
        }
        if (s.length() > n) b.append("...");
        return b.toString();
    }

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
