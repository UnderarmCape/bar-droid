package com.underarmcape.bardroid;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.DataInputStream;
import java.io.EOFException;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.zip.GZIPInputStream;

/**
 * Stands in for BAR's PC launcher behind the lobby (opt-in, launcher setting "Lobby bridge"). Chobby talks to the
 * launcher through WG.Connector (libs/spring-launcher api_spring_launcher.lua): it reads host and port from
 * sl-connection.json in the write dir and sends {"name": …, "command": {…}} JSON lines over TCP; sl_loopback.lua
 * (WG.WrapperLoopback) makes the calls. Without it the lobby's Replays tab cannot read replays, web links do nothing
 * and "resource" downloads (the OpenSkill ratings, clan images) are refused. With it every lobby download goes
 * through here, so each one is answered (DownloadFinished), success or not, or the lobby's queue would stall.
 *   OpenFile        web links open in Android's browser; the replays folder (the Replays tab's "Add") Android's file
 *                   picker for replays ({@link ReplayImportActivity}); other folders are ignored
 *   Download        game and map: the engine's pr-downloader in the container; resource: an HTTP download into the
 *                   write dir (archives that would have to be extracted, i.e. other engines, fail)
 *   ReadReplayInfo  engine, game, map, players and game time from the replay's header and start script (a game left
 *                   before its end, game time 0 there: its last key frame's)
 *   StartNewSpring  a second engine for a save or battle of another engine version: not on a phone, said on the screen
 *   ParseMiniMap, UploadLog, DiscordSetActivity, LoadArchiveExtensions: not here (logged)
 */
final class LobbyBridge {
    private final Context ctx;
    private final Paths p;
    private final File connectionFile;
    private final ExecutorService downloads = Executors.newSingleThreadExecutor();
    private final ExecutorService replays = Executors.newSingleThreadExecutor();
    private ServerSocket server;
    private Thread acceptThread;

    LobbyBridge(Context ctx, Paths p) {
        this.ctx = ctx;
        this.p = p;
        connectionFile = new File(p.bar, "sl-connection.json");
    }

    /** Without the bridge the lobby must not look for one (a stale file would make it connect to nothing). */
    static void removeConnectionFile(Paths p) {
        //noinspection ResultOfMethodCallIgnored
        new File(p.bar, "sl-connection.json").delete();
    }

    void start() throws IOException {
        // 127.0.0.1 itself, as written below for the lobby: Android's InetAddress.getLoopbackAddress() is ::1 (the
        // desktop JDK's, where tools/lobby-bridge-test.ps1 runs, is 127.0.0.1), so the lobby connected to nothing and
        // every download it handed over stayed at "Connecting..." (2026-10-27)
        server = new ServerSocket(0, 8, InetAddress.getByAddress(new byte[]{127, 0, 0, 1}));
        JSONObject info = new JSONObject();
        try {
            info.put("_sl_address", "127.0.0.1").put("_sl_port", server.getLocalPort()).put("_sl_write_path", "/root/bar");
        } catch (JSONException e) { throw new IOException(e); }
        try (OutputStream o = new FileOutputStream(connectionFile)) { o.write(info.toString().getBytes(StandardCharsets.UTF_8)); }
        acceptThread = new Thread(() -> {
            while (!server.isClosed()) {
                try {
                    Socket s = server.accept();
                    new Thread(() -> serve(s), "lobby-bridge-client").start();
                } catch (IOException e) { if (!server.isClosed()) Log.e("bridge", "accept: " + e); }
            }
        }, "lobby-bridge");
        acceptThread.start();
        Log.i("bridge", "lobby bridge on 127.0.0.1:" + server.getLocalPort());
        // (the lobby connects within seconds of starting; without it its downloads wait forever: say so)
        Thread check = new Thread(() -> {
            try { Thread.sleep(30000); } catch (InterruptedException e) { return; }
            if (!connected && !server.isClosed())
                Log.e("bridge", "!!! the lobby has not connected in 30 s: its downloads and the Replays tab will wait");
        }, "lobby-bridge-check");
        check.setDaemon(true);
        check.start();
    }

    private volatile boolean connected;

    void stop() {
        removeConnectionFile(p);
        try { if (server != null) server.close(); } catch (IOException ignored) {}
        downloads.shutdownNow();
        replays.shutdownNow();
    }

    private void serve(Socket s) {
        connected = true;
        Log.i("bridge", "lobby connected");
        try (Socket sock = s; BufferedReader in = new BufferedReader(new InputStreamReader(sock.getInputStream(), StandardCharsets.UTF_8))) {
            OutputStream out = sock.getOutputStream();
            for (String line; (line = in.readLine()) != null; ) {
                if (line.trim().isEmpty()) continue;
                try {
                    JSONObject msg = new JSONObject(line);
                    handle(msg.optString("name"), msg.optJSONObject("command"), out);
                } catch (JSONException e) { Log.e("bridge", "not JSON: " + line); }
                catch (RuntimeException e) {   // (uncaught on this thread it would end the app's process, the lobby with it)
                    Log.e("bridge", "a lobby message failed: " + e);
                }
            }
        } catch (IOException e) { Log.i("bridge", "lobby connection closed: " + e.getMessage()); }
    }

    private void handle(String name, JSONObject cmd, OutputStream out) {
        if (cmd == null) cmd = new JSONObject();
        switch (name) {
            case "OpenFile": {
                String path = cmd.optString("path");
                if (path.startsWith("http://") || path.startsWith("https://")) {
                    try {
                        ctx.startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(path)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
                        Log.i("bridge", "opened " + path);
                    } catch (Exception e) { Log.e("bridge", "could not open " + path + ": " + e); }
                } else if (path.matches("file://.*/demos/?")) {   // (the Replays tab's Open Folder, "Add" on a phone)
                    try {
                        ctx.startActivity(new Intent(ctx, ReplayImportActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
                    } catch (Exception e) { Log.e("bridge", "replay import: " + e); }
                } else Log.i("bridge", "not opened (no file manager here): " + path);
                break;
            }
            case "Download": {
                final JSONObject c = cmd;
                try { downloads.execute(() -> download(c, out)); }
                catch (java.util.concurrent.RejectedExecutionException e) { Log.i("bridge", "stopped: download not started"); }
                break;
            }
            case "StartNewSpring": {
                // (Chobby's second engine window: a saved game or a battle on another engine version, gui_loadgame.lua and
                // lobby.lua. No second engine on a phone; the lobby said "it will be opened in a new window" and then
                // nothing happened, only "not handled on Android" in the log, dev phone 2026-11-17: said on the screen)
                String engine = cmd.optString("Engine").replaceFirst("^(recoil_|rel\\d{4}\\.)", "");
                // (two lines at most: Android cuts a toast's words there, "...the app has 2026..." on the dev phone)
                String why = engine.isEmpty() || engine.equals(Prefs.engineVersion)
                        ? "no second game window here"
                        : "needs engine " + engine + " (app: " + Prefs.engineVersion + ")";
                Log.i("bridge", "StartNewSpring (" + cmd.optString("Engine") + "): not possible on Android, " + why);
                new android.os.Handler(android.os.Looper.getMainLooper()).post(() ->
                        android.widget.Toast.makeText(ctx, "Can't open on a phone: " + why, android.widget.Toast.LENGTH_LONG).show());
                break;
            }
            case "ReadReplayInfo": {
                final String rel = cmd.optString("relativePath");
                try { replays.execute(() -> replayInfo(rel, out)); }
                catch (java.util.concurrent.RejectedExecutionException e) { Log.i("bridge", "stopped: replay not read"); }
                break;
            }
            default:
                Log.i("bridge", "not handled on Android: " + name);
        }
    }

    // ---- downloads -----------------------------------------------------------------------------------

    private void download(JSONObject cmd, OutputStream out) {
        String name = cmd.optString("name"), type = cmd.optString("type");
        boolean ok = false;
        String why = null;   // (a failure's reason on the same line: offline, the lobby asks for each resource four times)
        try {
            if (("game".equals(type) || "map".equals(type) || "resource".equals(type)) && noNetwork()) {
                why = "no connection (no network on the phone)";
            } else if ("game".equals(type) || "map".equals(type)) {
                Proot proot = new Proot(p);
                int rc = proot.runScript("bridge:" + type, "/opt/bardroid/setup-container.sh", new HashMap<>(),
                        Arrays.asList("game".equals(type) ? "rapid" : "map", name, Prefs.engineVersion));
                ok = rc == 0;
            } else if ("resource".equals(type)) {
                ok = downloadResource(cmd.optJSONObject("resource"));
            } else Log.e("bridge", "download type " + type + " is not supported: " + name);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } catch (java.net.UnknownHostException e) {
            why = "no connection (" + e.getMessage() + ")";
        } catch (Exception e) { why = e.toString(); }
        Log.i("bridge", "download " + type + " " + name + (ok ? " done" : " failed" + (why != null ? ": " + why : "")));
        JSONObject r = new JSONObject();
        try { r.put("name", name).put("isSuccess", ok).put("isAborted", false); } catch (JSONException ignored) {}
        send(out, "DownloadFinished", r);
    }

    /** No network at all (Wi-Fi and mobile data off): a download fails at once. Offline the lobby asks for a missing
     *  map four times, and each ask started the container's downloader (proot, pr-downloader: about a second) only to
     *  fail on the CDN's name (dev phone, the Skirmish screen); its two web files (the widget list, the skill ratings)
     *  four times at every lobby start, each a name lookup first. A network without internet still tries. */
    private boolean noNetwork() {
        android.net.ConnectivityManager cm =
                (android.net.ConnectivityManager) ctx.getSystemService(Context.CONNECTIVITY_SERVICE);
        return cm != null && cm.getActiveNetwork() == null;
    }

    /** A plain file into the write dir; archives to extract (engines) are not supported. */
    private boolean downloadResource(JSONObject res) throws IOException {
        if (res == null) return false;
        String url = res.optString("url"), dest = res.optString("destination");
        if (url.isEmpty() || dest.isEmpty() || res.optBoolean("extract")) {
            Log.e("bridge", "resource not supported here: " + res);
            return false;
        }
        File target = new File(p.bar, dest).getCanonicalFile();
        if (!target.getPath().startsWith(p.bar.getCanonicalPath() + File.separator)) {
            Log.e("bridge", "resource destination outside the write dir: " + dest);
            return false;
        }
        //noinspection ResultOfMethodCallIgnored
        target.getParentFile().mkdirs();
        File tmp = new File(target.getPath() + ".part");
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setConnectTimeout(15000);
        c.setReadTimeout(30000);
        c.setRequestProperty("User-Agent", "BARDroid/" + BuildConfig.VERSION_NAME);
        boolean done = false;
        try {
            if (c.getResponseCode() != 200) { Log.e("bridge", url + ": HTTP " + c.getResponseCode()); return false; }
            try (InputStream in = c.getInputStream(); OutputStream o = new FileOutputStream(tmp)) {
                byte[] buf = new byte[65536];
                for (int n; (n = in.read(buf)) > 0; ) o.write(buf, 0, n);
            }
            done = tmp.renameTo(target) || (target.delete() && tmp.renameTo(target));
            return done;
        } finally {
            c.disconnect();
            //noinspection ResultOfMethodCallIgnored
            if (!done) tmp.delete();   // (a transfer cut short left its .part file in the write dir)
        }
    }

    // ---- replays --------------------------------------------------------------------------------------

    private static final int HEADER_FIXED = 16 + 4 + 4 + 256 + 16 + 8 + 12 * 4;   // demofile.h DemoFileHeader, packed

    private void replayInfo(String rel, OutputStream out) {
        File f = new File(p.bar, rel);
        try (DataInputStream in = new DataInputStream(new GZIPInputStream(new FileInputStream(f), 65536))) {
            byte[] h = new byte[HEADER_FIXED];
            in.readFully(h);
            if (!new String(h, 0, 15, StandardCharsets.US_ASCII).equals("spring demofile")) throw new IOException("not a demo file");
            int headerSize = le(h, 20);
            String engine = cString(h, 24, 256);
            int ints = 24 + 256 + 16 + 8;   // scriptSize, demoStreamSize, gameTime, ... winningAllyTeamsSize (the 12th)
            int scriptSize = le(h, ints), demoStreamSize = le(h, ints + 4), gameTime = le(h, ints + 8);
            int winnersSize = le(h, ints + 44);
            skip(in, headerSize - HEADER_FIXED);
            if (scriptSize <= 0 || scriptSize > 4 << 20) throw new IOException("start script size " + scriptSize);
            byte[] script = new byte[scriptSize];
            in.readFully(script);
            Map<String, Map<String, String>> sections = parseScript(new String(script, StandardCharsets.UTF_8));
            Map<String, String> game = sections.getOrDefault("game", new HashMap<>());
            // The engine writes the game's length only when the game ends: one left or quit before its end has 0, which
            // the lobby shows as "time unknown" (dev phone, 2026-11-15: every game quit early, an online game left
            // midway too). Its last key frame's number is how far it got (finished games: within seconds of the header's).
            boolean streamRead = false;
            if (gameTime <= 0) {
                int frame = lastKeyFrame(in, demoStreamSize);
                if (frame > 0) gameTime = frame / GAME_SPEED;
                streamRead = true;
            }
            // The winning ally teams follow the demo stream, one byte each (the lobby shows Won/Lost for the player's
            // own replays). An engine that did not end cleanly wrote neither (demoStreamSize 0): "Unknown Result".
            JSONArray winners = new JSONArray();
            if (demoStreamSize > 0 && winnersSize > 0 && winnersSize <= 255) {
                try {
                    if (!streamRead) skip(in, demoStreamSize);
                    for (int i = 0; i < winnersSize; i++) winners.put(in.readUnsignedByte());
                } catch (IOException e) {   // (a damaged file: its result unknown, the replay still listed)
                    winners = new JSONArray();
                }
            }
            JSONObject r = new JSONObject();
            r.put("relativePath", rel).put("engine", engine).put("game", game.getOrDefault("gametype", ""))
                    .put("map", game.getOrDefault("mapname", "")).put("gameTime", gameTime)
                    .put("players", players(sections)).put("winningAllyTeamIds", winners);
            send(out, "ReplayInfo", r);
        } catch (Exception e) {
            Log.i("bridge", "replay " + rel + " not read: " + e.getMessage());   // e.g. a game the app was closed in
        }
    }

    /** The start script's sections ([game], [player0], [team1], [ai0], …) as key → value maps, keys lower case. */
    static Map<String, Map<String, String>> parseScript(String script) {
        Map<String, Map<String, String>> sections = new LinkedHashMap<>();
        List<String> stack = new ArrayList<>();
        String pending = null;
        for (String raw : script.split("[\r\n]+")) {
            String l = raw.trim();
            if (l.startsWith("[") && l.endsWith("]")) pending = l.substring(1, l.length() - 1).toLowerCase(java.util.Locale.ROOT);
            else if (l.equals("{")) { stack.add(pending != null ? pending : ""); pending = null; }
            else if (l.equals("}")) { if (!stack.isEmpty()) stack.remove(stack.size() - 1); }
            else if (!stack.isEmpty() && l.contains("=")) {
                int eq = l.indexOf('=');
                String v = l.substring(eq + 1).trim();
                if (v.endsWith(";")) v = v.substring(0, v.length() - 1);
                sections.computeIfAbsent(stack.get(stack.size() - 1), k -> new HashMap<>())
                        .put(l.substring(0, eq).trim().toLowerCase(java.util.Locale.ROOT), v);
            }
        }
        return sections;
    }

    /** Players and AIs (no spectators) the way BAR's launcher reports them to Chobby's replay list. */
    static JSONArray players(Map<String, Map<String, String>> sections) throws JSONException {
        JSONArray list = new JSONArray();
        for (Map.Entry<String, Map<String, String>> e : sections.entrySet()) {
            String sec = e.getKey();
            Map<String, String> v = e.getValue();
            boolean ai = sec.matches("ai\\d+");
            if (!ai && !sec.matches("player\\d+")) continue;
            if ("1".equals(v.get("spectator"))) continue;
            Map<String, String> team = sections.getOrDefault("team" + v.getOrDefault("team", "-1"), new HashMap<>());
            JSONObject pl = new JSONObject();
            pl.put("name", v.getOrDefault("name", "?"));
            pl.put("allyTeamId", parseInt(team.get("allyteam"), 0));
            pl.put("teamId", parseInt(v.get("team"), 0));
            if (team.containsKey("side")) pl.put("faction", team.get("side"));
            if (ai) pl.put("aiId", v.getOrDefault("shortname", ""));
            else {
                if (v.containsKey("countrycode")) pl.put("countryCode", v.get("countrycode"));
                if (v.containsKey("rank")) pl.put("rank", parseInt(v.get("rank"), 0));
                if (v.containsKey("skill")) pl.put("skill", v.get("skill"));
                if (v.containsKey("skilluncertainty")) pl.put("skillUncertainty", v.get("skilluncertainty"));
            }
            list.put(pl);
        }
        return list;
    }

    private static int parseInt(String s, int dflt) {
        try { return Integer.parseInt(s.trim()); } catch (Exception e) { return dflt; }
    }

    private static final int GAME_SPEED = 30;   // game frames a second
    private static final int NETMSG_KEYFRAME = 1;   // BaseNetProtocol.h: the id byte, then the frame number (int32)

    /**
     * The demo stream read to its end (size bytes; 0: an engine that did not end cleanly wrote no size, so up to where
     * the file stops): the frame number of its last key frame, 0 without one. Each chunk: DemoStreamChunkHeader
     * (float modGameTime, uint32 length), then a net message of that length.
     */
    static int lastKeyFrame(InputStream in, long size) throws IOException {
        byte[] h = new byte[8], m = new byte[5];
        int last = 0;
        long pos = 0;   // (bytes of the stream read)
        try {
            while (size <= 0 || pos + 8 <= size) {
                readFully(in, h, 8);
                pos += 8;
                long length = le(h, 4) & 0xffffffffL;
                if (length > 1 << 24 || (size > 0 && pos + length > size)) break;   // (not a chunk: stop there)
                if (length >= 5) {
                    readFully(in, m, 5);
                    if (m[0] == NETMSG_KEYFRAME) last = le(m, 1);
                    skip(in, length - 5);
                } else {
                    skip(in, length);
                }
                pos += length;
            }
            if (size > 0 && pos < size) skip(in, size - pos);   // (to the stream's end: what follows it is read next)
        } catch (IOException e) {
            // (a file cut short ends here, and a damaged one, gzip's ZipException: before the length was read from the
            // stream such a replay was listed as "time unknown", and that stays so; review 2026-11-15)
        }
        return last;
    }

    private static void readFully(InputStream in, byte[] b, int n) throws IOException {
        for (int off = 0; off < n; ) {
            int k = in.read(b, off, n - off);
            if (k < 0) throw new EOFException();
            off += k;
        }
    }

    private static int le(byte[] b, int off) {
        return (b[off] & 0xff) | (b[off + 1] & 0xff) << 8 | (b[off + 2] & 0xff) << 16 | (b[off + 3] & 0xff) << 24;
    }

    private static String cString(byte[] b, int off, int max) {
        int end = off;
        while (end < off + max && b[end] != 0) end++;
        return new String(b, off, end - off, StandardCharsets.UTF_8);
    }

    private static void skip(InputStream in, long n) throws IOException {
        while (n > 0) {
            long k = in.skip(n);
            if (k <= 0) { if (in.read() < 0) throw new EOFException(); k = 1; }
            n -= k;
        }
    }

    private static void send(OutputStream out, String name, JSONObject command) {
        JSONObject msg = new JSONObject();
        try { msg.put("name", name).put("command", command); } catch (JSONException ignored) {}
        byte[] data = (msg + "\n").getBytes(StandardCharsets.UTF_8);
        synchronized (out) {
            try { out.write(data); out.flush(); } catch (IOException e) { Log.e("bridge", "reply " + name + ": " + e); }
        }
    }
}
