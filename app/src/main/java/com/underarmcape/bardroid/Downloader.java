package com.underarmcape.bardroid;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;

/** Resumable HTTP(S) downloader with optional SHA-256 verification. Follows redirects across hosts. */
public final class Downloader {
    public interface Progress { void onProgress(long done, long total); }

    private volatile boolean cancelled;
    public void cancel() { cancelled = true; }

    public static String fetchText(String url) throws IOException {
        HttpURLConnection c = open(url, 0);
        try (InputStream in = c.getInputStream()) {
            byte[] buf = Installer.readAll(in);
            return new String(buf, StandardCharsets.UTF_8);
        } finally { c.disconnect(); }
    }

    private static HttpURLConnection open(String url, long rangeStart) throws IOException {
        String current = url;
        for (int hop = 0; hop < 8; hop++) {
            HttpURLConnection c = (HttpURLConnection) new URL(current).openConnection();
            c.setInstanceFollowRedirects(false);
            c.setConnectTimeout(30000);
            c.setReadTimeout(60000);
            c.setRequestProperty("User-Agent", "BARDroid/" + BuildConfig.VERSION_NAME);
            if (rangeStart > 0) c.setRequestProperty("Range", "bytes=" + rangeStart + "-");
            int code = c.getResponseCode();
            if (code / 100 == 3) {
                String loc = c.getHeaderField("Location");
                c.disconnect();
                if (loc == null) throw new IOException("redirect without Location from " + current);
                current = new URL(new URL(current), loc).toString();
                continue;
            }
            if (code / 100 != 2) {
                c.disconnect();
                throw new IOException("HTTP " + code + " for " + current);
            }
            return c;
        }
        throw new IOException("too many redirects for " + url);
    }

    /** Downloads url to dest (resuming a partial .part file). Returns the file. */
    public File download(String url, File dest, String expectedSha256, Progress progress) throws IOException {
        File part = new File(dest.getPath() + ".part");
        long have = part.exists() ? part.length() : 0;
        if (dest.exists() && (expectedSha256 == null || sha256(dest).equalsIgnoreCase(expectedSha256))) {
            Log.i("dl", "already have " + dest.getName());
            return dest;
        }
        Log.i("dl", "GET " + url + (have > 0 ? " (resume at " + have + ")" : ""));
        HttpURLConnection c;
        try {
            c = open(url, have);
        } catch (IOException e) {
            // 416: the .part is already whole (the app was killed before the rename) or longer than the file now.
            if (have == 0 || !String.valueOf(e.getMessage()).startsWith("HTTP 416")) throw e;
            Log.i("dl", "partial " + part.getName() + " not resumable: starting over");
            //noinspection ResultOfMethodCallIgnored
            part.delete();
            have = 0;
            c = open(url, 0);
        }
        boolean resumed = have > 0 && c.getResponseCode() == 206;
        if (!resumed) { have = 0; }
        long total = c.getContentLengthLong();
        if (total > 0) total += have;
        try (InputStream in = c.getInputStream(); RandomAccessFile out = new RandomAccessFile(part, "rw")) {
            out.setLength(have);   // a server that ignored the range sends it all again: no old bytes after it
            out.seek(have);
            byte[] buf = new byte[256 * 1024];
            long done = have; int n; long lastReport = 0;
            while ((n = in.read(buf)) > 0) {
                if (cancelled) throw new IOException("cancelled");
                out.write(buf, 0, n);
                done += n;
                if (progress != null && (done - lastReport > 2 * 1024 * 1024 || done == total)) { progress.onProgress(done, total); lastReport = done; }
            }
            // the .part stays for the next try to resume
            if (total > 0 && done != total) throw new IOException("download of " + dest.getName() + " ended at " + done + " of " + total + " bytes");
        } finally { c.disconnect(); }
        if (expectedSha256 != null) {
            String got = sha256(part);
            if (!got.equalsIgnoreCase(expectedSha256)) {
                //noinspection ResultOfMethodCallIgnored
                part.delete();
                throw new IOException("checksum mismatch for " + dest.getName() + ": expected " + expectedSha256 + " got " + got);
            }
        }
        if (dest.exists()) //noinspection ResultOfMethodCallIgnored
            dest.delete();
        if (!part.renameTo(dest)) throw new IOException("rename failed: " + part);
        return dest;
    }

    public static String sha256(File f) throws IOException {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            try (InputStream in = new java.io.FileInputStream(f)) {
                byte[] buf = new byte[1 << 20]; int n;
                while ((n = in.read(buf)) > 0) md.update(buf, 0, n);
            }
            StringBuilder sb = new StringBuilder();
            for (byte b : md.digest()) sb.append(String.format(Locale.US, "%02x", b));
            return sb.toString();
        } catch (java.security.NoSuchAlgorithmException e) { throw new IOException(e); }
    }

    public static String human(long bytes) {
        if (bytes < 0) return "?";
        if (bytes < 1024 * 1024) return (bytes / 1024) + " KB";
        if (bytes < 1024L * 1024 * 1024) return String.format(Locale.US, "%.1f MB", bytes / 1048576.0);
        return String.format(Locale.US, "%.2f GB", bytes / 1073741824.0);
    }

    @SuppressWarnings("unused")
    private static void closeQuietly(FileOutputStream o) { try { if (o != null) o.close(); } catch (IOException ignored) {} }
}
