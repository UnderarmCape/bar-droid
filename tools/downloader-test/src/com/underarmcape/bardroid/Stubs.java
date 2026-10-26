package com.underarmcape.bardroid;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;

final class Log {
    static void i(String t, String m) { System.out.println("  [" + t + "] " + m); }
    static void e(String t, String m) { System.out.println("  [" + t + "] E " + m); }
}

final class BuildConfig { static final String VERSION_NAME = "test"; }

final class Installer {
    static byte[] readAll(InputStream in) throws IOException {
        ByteArrayOutputStream o = new ByteArrayOutputStream();
        byte[] b = new byte[65536]; int n;
        while ((n = in.read(b)) > 0) o.write(b, 0, n);
        return o.toByteArray();
    }
}
