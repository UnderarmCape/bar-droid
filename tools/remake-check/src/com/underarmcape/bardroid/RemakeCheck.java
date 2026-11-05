package com.underarmcape.bardroid;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

/** The phone's remake of a menu copy (BuildMenuPatches) against the shipped copy: args <dir> <assets> <name>... */
public class RemakeCheck {
    public static void main(String[] args) throws Exception {
        Path dir = Path.of(args[0]), assets = Path.of(args[1]);
        int fails = 0;
        for (int i = 2; i < args.length; i++) {
            String name = args[i];
            String bar = Files.readString(dir.resolve(name + ".bar"), StandardCharsets.UTF_8);
            String[] info = Files.readString(dir.resolve(name + ".info"), StandardCharsets.UTF_8).strip().split("\\R");
            String patches = Files.readString(assets.resolve("bardroid_" + name + ".patches"), StandardCharsets.UTF_8);
            String shipped = Files.readString(assets.resolve("bardroid_" + name + ".lua"), StandardCharsets.UTF_8);
            String made = BuildMenuPatches.apply(bar, patches, info[0], info[1]);
            boolean same = made.equals(shipped);
            if (!same) {
                fails++;
                int at = 0;
                while (at < made.length() && at < shipped.length() && made.charAt(at) == shipped.charAt(at)) at++;
                System.out.println(name + ": differs at char " + at + " (made " + made.length() + ", shipped " + shipped.length() + ")");
            }
            System.out.println((same ? "PASS " : "FAIL ") + name + ": the phone's remake equals the shipped copy (" + info[0] + ")");
        }
        System.exit(fails == 0 ? 0 : 1);
    }
}
