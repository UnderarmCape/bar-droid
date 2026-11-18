package com.underarmcape.bardroid;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;

/**
 * LogRedact.java ("Share logs" keeps an online game's join password out of the logs it hands on): the start script's
 * lines as the engine logs them, the rest of a log untouched, bytes outside ASCII as they were.
 *   tools/log-redact-test.ps1, tools/java-checks.sh
 */
public final class LogRedactTest {
    private static int failed;

    private static void check(boolean ok, String what, String got) {
        System.out.println((ok ? "PASS  " : "FAIL  ") + what + (ok ? "" : ": " + got));
        if (!ok) failed++;
    }

    public static void main(String[] a) throws Exception {
        String s = LogRedact.line("[t=00:00:01.5] \tMyPasswd=a8F3k2Zq;");
        check(s.equals("[t=00:00:01.5] \tMyPasswd=(removed);") && !s.contains("a8F3"),
                "the start script's join password: its value gone, the key and the ';' kept", s);
        s = LogRedact.line("09:00:51 [engine] \tMyPasswd = x y z");
        check(s.equals("09:00:51 [engine] \tMyPasswd = (removed)"), "spaces round '=' and no ';' (launcher.log's copy)", s);
        s = LogRedact.line("\tmypasswd=QQQ;");
        check(!s.contains("QQQ"), "any case", s);
        s = LogRedact.line("\tMyPasswd=;");
        check(s.equals("\tMyPasswd=(removed);"), "an empty one (a skirmish) stays harmless", s);
        String plain = "[t=00:00:02] [bardroid-perf] 29.7 fps over 60 s, slowest frame 320 ms";
        check(LogRedact.line(plain) == plain, "a line without one: the same string, no work", LogRedact.line(plain));
        s = LogRedact.line("\tMyPlayerName=Phone;");
        check(s.equals("\tMyPlayerName=Phone;"), "the script's other keys left as they are", s);

        byte[] in = ("line one\n\tMyPasswd=secret123;\nnaïve été\r\nlast").getBytes(StandardCharsets.ISO_8859_1);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        LogRedact.copy(new ByteArrayInputStream(in), out);
        String text = new String(out.toByteArray(), StandardCharsets.ISO_8859_1);
        check(text.equals("line one\n\tMyPasswd=(removed);\nnaïve été\nlast\n") && !text.contains("secret123"),
                "a whole log copied: the value gone, other bytes as they were, lines ending in \\n", text);

        System.out.println(failed == 0 ? "ALL PASS" : failed + " FAILED");
        System.exit(failed == 0 ? 0 : 1);
    }
}
