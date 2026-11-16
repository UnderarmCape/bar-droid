package com.underarmcape.bardroid;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;

/**
 * BAR's load screen pictures for an upright screen (Installer's .bardroid-loadpictures-upright, tools/make-loadpictures.ps1)
 * under BAR's names in the write folder while the screen is upright, listed in .bardroid-loadpictures-ours. launch-bar.sh
 * does it at each engine start, but a game started from the lobby loads in the same engine: after a turn of the phone
 * ("Turn with the phone") the start's choice was the other shape's (upright a narrow strip of BAR's 16:9 pictures, or
 * sideways the upright ones, 1080 wide and cut). GameActivity calls this when the screen turns; the same steps as
 * launch-bar.sh's. Off the UI thread.
 */
final class LoadPictures {
    private LoadPictures() {}

    private static final java.util.concurrent.ExecutorService ONE = java.util.concurrent.Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "loadpictures");
        t.setDaemon(true);
        return t;
    });
    /**
     * The screen's new shape: applied in order on a thread of its own. first: the game screen's first shape, which
     * launch-bar.sh handles at the engine's start: after launch-bar.sh is done with the same files (both at once: a
     * removal could take pictures it was still putting in place), and also when it is the shape the engine started with
     * (apply changes nothing then): a game screen made again over a running game, after the old one had turned, left
     * the files in the turned shape for the next game; review 2026-11-16.
     */
    static void follow(File bar, boolean upright, boolean first) {
        if (first) {
            ONE.execute(() -> {
                try { Thread.sleep(8000); } catch (InterruptedException e) { return; }
                apply(bar, upright);
            });
            return;
        }
        ONE.execute(() -> apply(bar, upright));
    }

    static synchronized void apply(File bar, boolean upright) {
        File from = new File(bar, ".bardroid-loadpictures-upright");
        File ours = new File(bar, ".bardroid-loadpictures-ours");
        File pics = new File(bar, "bitmaps/loadpictures");
        try {
            if (upright && from.isDirectory() && !ours.isFile()) {
                File[] fs = from.listFiles((d, n) -> n.endsWith(".jpg"));
                if (fs == null || fs.length == 0) return;
                StringBuilder list = new StringBuilder();
                for (File f : fs) {
                    String rel = f.getName().replace("__", "/");   // (manual__scavengers__x.jpg: manual/scavengers/x.jpg)
                    File to = new File(pics, rel);
                    File dir = to.getParentFile();
                    if (dir != null && !dir.isDirectory() && !dir.mkdirs()) throw new IOException("cannot make " + dir);
                    Files.copy(f.toPath(), to.toPath(), StandardCopyOption.REPLACE_EXISTING);
                    list.append(rel).append('\n');
                }
                Files.write(ours.toPath(), list.toString().getBytes(StandardCharsets.UTF_8));
                Log.i("app", "loading screen: BAR's pictures for the upright screen in place (the screen turned)");
            } else if (!upright && ours.isFile()) {
                for (String rel : Files.readAllLines(ours.toPath(), StandardCharsets.UTF_8)) {
                    if (!rel.isEmpty()) Files.deleteIfExists(new File(pics, rel).toPath());
                }
                // (the folders only when empty, as launch-bar.sh's rmdir)
                for (String d : new String[]{"manual/scavengers", "manual", ""}) {
                    File f = d.isEmpty() ? pics : new File(pics, d);
                    String[] left = f.list();
                    if (left != null && left.length == 0) Files.deleteIfExists(f.toPath());
                }
                Files.deleteIfExists(ours.toPath());
                Log.i("app", "loading screen: BAR's own pictures back (the screen turned sideways)");
            }
        } catch (IOException e) {
            Log.e("app", "loading screen pictures: " + e);
        }
    }
}
