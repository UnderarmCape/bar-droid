package com.underarmcape.bardroid;

import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * springsettings.cfg at every start (Installer.writeGameFiles). BAR and the player change it during games (sound
 * volumes, BAR's options; BAR's settings migrations count "version" up in it), so the existing file is kept and only
 * completed: the template's keys where it has none, and at every start the keys the Android setup needs (ALWAYS) and
 * the user's knobs. Rewriting it from the template at every start reset BAR's settings and re-ran BAR's first-start
 * migrations each time (2026-10-26). launch-bar.sh sets the phone graphics and the interface scale on top.
 * Plain Java, tested on the laptop (tools/settings-merge-test).
 */
final class SettingsMerge {
    private SettingsMerge() {}

    /** springsettings.cfg keys (of the template) that the Android setup needs at every start. */
    static final String[] ALWAYS = {
            "Fullscreen", "WindowBorderless", "WindowPosX", "WindowPosY", "XResolutionWindowed", "YResolutionWindowed",
            "MinimizeOnFocusLoss", "BlockCompositing", "CompressTextures", "ForceDisableGL4", "ThreadPinPolicy",
            "HardwareCursor", "WindowedEdgeMove", "FullscreenEdgeMove", "UseSDLAudio", "snd_device",
            "VFSCacheArchiveFiles", "TextureMemPoolSize", "LogFlushLevel",
    };

    /** The key of a springsettings.cfg line, or null for comments and blank lines. */
    static String configKey(String line) {
        int eq = line.indexOf('=');
        String t = line.trim();
        return eq > 0 && !t.isEmpty() && !t.startsWith("#") ? line.substring(0, eq).trim() : null;
    }

    /** Keys and values of a springsettings.cfg, in file order (the first of a repeated key). */
    static Map<String, String> keys(List<String> lines) {
        Map<String, String> m = new LinkedHashMap<>();
        for (String l : lines) {
            String key = configKey(l);
            if (key != null && !m.containsKey(key)) m.put(key, l.substring(l.indexOf('=') + 1).trim());
        }
        return m;
    }

    /**
     * @param template the app's springsettings.cfg
     * @param existing the write dir's springsettings.cfg, or null when there is none yet (the template is the start)
     * @param set      keys and values set at every start
     * @return the new springsettings.cfg: the existing lines in their order (a key twice: the first one counts), the
     *         set keys replaced, then the template's keys it lacked, then the set keys neither had
     */
    static String merge(List<String> template, List<String> existing, Map<String, String> set) {
        StringBuilder cfg = new StringBuilder();
        Set<String> seen = new HashSet<>();
        for (String l : existing != null ? existing : template) {
            String key = configKey(l);
            if (key != null) {
                if (!seen.add(key)) continue;
                if (set.containsKey(key)) l = key + " = " + set.get(key);
            }
            cfg.append(l).append('\n');
        }
        for (Map.Entry<String, String> kv : keys(template).entrySet())
            if (seen.add(kv.getKey()))
                cfg.append(kv.getKey()).append(" = ").append(set.containsKey(kv.getKey()) ? set.get(kv.getKey()) : kv.getValue()).append('\n');
        for (Map.Entry<String, String> kv : set.entrySet())
            if (seen.add(kv.getKey())) cfg.append(kv.getKey()).append(" = ").append(kv.getValue()).append('\n');
        return cfg.toString();
    }
}
