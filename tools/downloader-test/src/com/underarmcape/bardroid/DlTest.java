package com.underarmcape.bardroid;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.Random;

/**
 * Downloader.java against a local HTTP server (tools/downloader-test.ps1): a fresh download, a whole .part (HTTP 416),
 * a resume (206), a server that ignores the range with a longer .part on disk, a body cut short (the .part stays),
 * and a resume after that.
 */
public final class DlTest {
    static final byte[] DATA = new byte[1 << 20];
    static volatile String mode = "range";   // range | norange | truncate
    static int fails;

    public static void main(String[] a) throws Exception {
        new Random(1).nextBytes(DATA);
        ServerSocket server = new ServerSocket(0, 8, InetAddress.getLoopbackAddress());
        Thread t = new Thread(() -> {
            while (!server.isClosed()) {
                try (Socket s = server.accept()) { serve(s); } catch (IOException ignored) {}
            }
        });
        t.setDaemon(true);
        t.start();
        String url = "http://127.0.0.1:" + server.getLocalPort() + "/f";
        File dir = Files.createTempDirectory("dltest").toFile();
        File dest = new File(dir, "x.bin"), part = new File(dir, "x.bin.part");

        check("fresh", url, dest, part);
        write(part, Arrays.copyOf(DATA, DATA.length));
        check("whole .part (416, starts over)", url, dest, part);
        write(part, Arrays.copyOf(DATA, 300_000));
        check("resume (206)", url, dest, part);
        mode = "norange";
        byte[] junk = new byte[1_500_000];
        Arrays.fill(junk, (byte) 7);
        write(part, junk);
        check("range ignored, longer .part", url, dest, part);
        mode = "truncate";
        dest.delete();
        part.delete();
        try {
            new Downloader().download(url, dest, null, null);
            System.out.println("FAIL body cut short: no error, " + dest.length() + " bytes");
            fails++;
        } catch (IOException e) {
            boolean ok = !dest.exists() && part.exists();
            System.out.println((ok ? "ok   " : "FAIL ") + "body cut short: " + e.getMessage() + " (.part kept: " + part.exists() + ")");
            if (!ok) fails++;
        }
        mode = "range";
        check("resume after that", url, dest, part);
        server.close();
        System.out.println(fails == 0 ? "ALL PASS" : fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }

    /** One request: GET with an optional Range; 200, 206 or 416; in truncate mode half the body, then the socket closes. */
    static void serve(Socket s) throws IOException {
        BufferedReader in = new BufferedReader(new InputStreamReader(s.getInputStream(), StandardCharsets.US_ASCII));
        long start = 0;
        for (String l; (l = in.readLine()) != null && !l.isEmpty(); )
            if (l.toLowerCase().startsWith("range:") && mode.equals("range")) start = Long.parseLong(l.replaceAll("[^0-9]", ""));
        OutputStream out = s.getOutputStream();
        if (start >= DATA.length) {
            out.write("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".getBytes(StandardCharsets.US_ASCII));
            return;
        }
        int len = DATA.length - (int) start;
        String head = (start > 0 ? "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes " + start + "-" + (DATA.length - 1) + "/" + DATA.length
                : "HTTP/1.1 200 OK") + "\r\nContent-Length: " + len + "\r\nConnection: close\r\n\r\n";
        out.write(head.getBytes(StandardCharsets.US_ASCII));
        out.write(DATA, (int) start, mode.equals("truncate") ? len / 2 : len);
        out.flush();
    }

    static void check(String name, String url, File dest, File part) {
        dest.delete();
        try {
            File f = new Downloader().download(url, dest, null, null);
            boolean ok = Arrays.equals(Files.readAllBytes(f.toPath()), DATA) && !part.exists();
            System.out.println((ok ? "ok   " : "FAIL ") + name + " (" + f.length() + " bytes)");
            if (!ok) fails++;
        } catch (Exception e) {
            System.out.println("FAIL " + name + ": " + e);
            fails++;
        }
    }

    static void write(File f, byte[] b) throws IOException {
        try (FileOutputStream o = new FileOutputStream(f)) { o.write(b); }
    }
}
