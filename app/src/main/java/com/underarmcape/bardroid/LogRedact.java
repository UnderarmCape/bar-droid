package com.underarmcape.bardroid;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.util.regex.Pattern;

/**
 * What "Share logs" keeps out of the logs it hands on (LogShare): the engine logs an online game's start script whole,
 * its join password with it ("\tMyPasswd=...;" in launcher.log and the infologs: 9 of them in the Fold7's logs,
 * 2026-11-18), and the zip goes to whoever is asked to read it. The value goes, the key stays (a reader still sees the
 * script had one). No Android classes: tools/log-redact-test checks it on the laptop.
 */
final class LogRedact {
    private LogRedact() {}

    private static final Pattern SECRET = Pattern.compile("(?i)(MyPasswd\\s*=\\s*)[^;\\r\\n]*");

    /** One line, its join password's value gone. */
    static String line(String s) {
        if (s.indexOf("sswd") < 0 && s.indexOf("SSWD") < 0) return s;   // (a cheap test first: logs run to tens of MB)
        return SECRET.matcher(s).replaceAll("$1(removed)");
    }

    /** A log copied line by line, its bytes as they were (Latin-1 both ways) but a join password's value; lines end in
     *  \n. {@code out} is left open (a zip's entry). */
    static void copy(InputStream in, OutputStream out) throws IOException {
        BufferedReader r = new BufferedReader(new InputStreamReader(in, StandardCharsets.ISO_8859_1), 1 << 16);
        Writer w = new OutputStreamWriter(out, StandardCharsets.ISO_8859_1);
        for (String s; (s = r.readLine()) != null; ) {
            w.write(line(s));
            w.write('\n');
        }
        w.flush();
    }
}
