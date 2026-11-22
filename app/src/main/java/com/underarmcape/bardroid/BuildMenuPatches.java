package com.underarmcape.bardroid;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * The app's copy of BAR's Build menu, made on the phone when an update changes BAR's file: the pad's RB, PLACE and the
 * shapes live in that copy, and a phone cannot wait for a new app (Kailil, 2026-11-01, online after BAR's update: "RB to
 * focus the Build menu ... didn't allow me to use the build menu"). The patches are tools/make-buildmenu.py's, written
 * to assets/bardroid/bardroid_buildmenu.patches: the copy's header, then what to find and what goes in its place, all
 * parted by the ASCII record separator. No Android classes: tools/padgame-test checks it.
 */
final class BuildMenuPatches {
    private static final String SEPARATOR = "\u001e";
    /** Lua 5.1's limit of local variables in one function: a main chunk over it does not load at all. */
    static final int LOCALS_LIMIT = 200;
    // (tools/lua-locals.py's count: a top-level statement starts at the line's first column, the files' own style)
    private static final Pattern LOCAL_FUNCTION = Pattern.compile("local\\s+function\\s+[A-Za-z_]\\w*");
    private static final Pattern LOCAL_NAMES = Pattern.compile("local\\s+([A-Za-z_][\\w\\s,<>]*?)\\s*(?:=|--|$)");

    private BuildMenuPatches() {}

    /**
     * The copy of BAR's file barFile, of the release named release, whose pool md5 is md5.
     * @throws IllegalArgumentException a patch does not find its one place (BAR rewrote that part), or the copy would
     *         declare more top-level locals than Lua allows (BAR's file grew to the limit: the copy would not load, and
     *         that game would have no build menu)
     */
    static String apply(String barFile, String patches, String release, String md5) {
        // (patches checked out with Windows line endings, or saved with a byte order mark, as BAR's file can be: their
        // text found no place, and a mark in the header went before the copy's first line, which Lua refuses)
        patches = patches.replace("\r\n", "\n");
        if (patches.startsWith("﻿")) patches = patches.substring(1);
        String[] parts = patches.split(SEPARATOR, -1);
        if (parts.length < 3 || parts.length % 2 == 0) throw new IllegalArgumentException("not a patch file");
        String text = barFile.replace("\r\n", "\n");
        if (text.startsWith("﻿")) text = text.substring(1);
        for (int i = 1; i < parts.length; i += 2) {
            String find = parts[i];
            int at = text.indexOf(find);
            if (at < 0 || text.indexOf(find, at + find.length()) >= 0) {
                int end = find.indexOf('\n');
                throw new IllegalArgumentException("no one place for: " + (end < 0 ? find : find.substring(0, end)).trim());
            }
            text = text.substring(0, at) + parts[i + 1] + text.substring(at + find.length());
        }
        String made = parts[0].replace("{release}", release).replace("{md5}", md5) + text;
        int locals = topLevelLocals(made);
        if (locals > LOCALS_LIMIT)
            throw new IllegalArgumentException(locals + " top-level locals, over Lua's " + LOCALS_LIMIT + " (release overhaul audit, 2026-11-21)");
        return made;
    }

    /** The locals a Lua file declares at its top level, counted as tools/lua-locals.py does. */
    static int topLevelLocals(String lua) {
        int n = 0;
        boolean inLongComment = false;
        for (String line : lua.split("\n", -1)) {
            if (inLongComment) {
                if (line.contains("]]")) inLongComment = false;
                continue;
            }
            if (line.startsWith("--[[")) {
                inLongComment = !line.contains("]]");
                continue;
            }
            if (LOCAL_FUNCTION.matcher(line).lookingAt()) {
                n++;
                continue;
            }
            Matcher m = LOCAL_NAMES.matcher(line);
            if (m.lookingAt()) for (String name : m.group(1).split(",")) if (!name.trim().isEmpty()) n++;
        }
        return n;
    }
}
