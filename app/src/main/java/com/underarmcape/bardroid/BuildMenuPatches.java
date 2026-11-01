package com.underarmcape.bardroid;

/**
 * The app's copy of BAR's Build menu, made on the phone when an update changes BAR's file: the pad's RB, PLACE and the
 * shapes live in that copy, and a phone cannot wait for a new app (Kailil, 2026-11-01, online after BAR's update: "RB to
 * focus the Build menu ... didn't allow me to use the build menu"). The patches are tools/make-buildmenu.py's, written
 * to assets/bardroid/bardroid_buildmenu.patches: the copy's header, then what to find and what goes in its place, all
 * parted by the ASCII record separator. No Android classes: tools/padgame-test checks it.
 */
final class BuildMenuPatches {
    private static final String SEPARATOR = "\u001e";

    private BuildMenuPatches() {}

    /**
     * The copy of BAR's file barFile, of the release named release, whose pool md5 is md5.
     * @throws IllegalArgumentException a patch does not find its one place: BAR rewrote that part
     */
    static String apply(String barFile, String patches, String release, String md5) {
        String[] parts = patches.split(SEPARATOR, -1);
        if (parts.length < 3 || parts.length % 2 == 0) throw new IllegalArgumentException("not a patch file");
        String text = barFile.replace("\r\n", "\n");
        for (int i = 1; i < parts.length; i += 2) {
            String find = parts[i];
            int at = text.indexOf(find);
            if (at < 0 || text.indexOf(find, at + find.length()) >= 0) {
                int end = find.indexOf('\n');
                throw new IllegalArgumentException("no one place for: " + (end < 0 ? find : find.substring(0, end)).trim());
            }
            text = text.substring(0, at) + parts[i + 1] + text.substring(at + find.length());
        }
        return parts[0].replace("{release}", release).replace("{md5}", md5) + text;
    }
}
