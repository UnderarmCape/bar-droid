package com.underarmcape.bardroid;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** SettingsMerge (springsettings.cfg at every start), with the app's template: MergeTest <template> [<a phone's file>] */
public final class MergeTest {
    static int fails;

    static void check(String what, boolean ok) {
        System.out.println((ok ? "ok   " : "FAIL ") + what);
        if (!ok) fails++;
    }

    static Map<String, String> setFor(List<String> template) {
        Map<String, String> tpl = SettingsMerge.keys(template), set = new LinkedHashMap<>();
        for (String k : SettingsMerge.ALWAYS) if (tpl.containsKey(k)) set.put(k, tpl.get(k));
        set.put("WorkerThreadCount", "4");
        set.put("RapidTagResolutionOrder", "repos-cdn.beyondallreason.dev;repos.beyondallreason.dev");
        return set;
    }

    static List<String> lines(String s) { return new ArrayList<>(Arrays.asList(s.split("\n", -1)).subList(0, s.split("\n", -1).length - 1)); }

    static long count(List<String> lines, String key) {
        return lines.stream().filter(l -> key.equals(SettingsMerge.configKey(l))).count();
    }

    public static void main(String[] a) throws Exception {
        List<String> template = Files.readAllLines(Paths.get(a[0]), StandardCharsets.UTF_8);
        Map<String, String> tpl = SettingsMerge.keys(template), set = setFor(template);

        // a first start: the template, with the set keys
        List<String> first = lines(SettingsMerge.merge(template, null, set));
        Map<String, String> k1 = SettingsMerge.keys(first);
        check("first start: every template key", k1.keySet().containsAll(tpl.keySet()));
        check("first start: the user's knobs set", "4".equals(k1.get("WorkerThreadCount")));
        check("first start: comments kept", first.stream().filter(l -> l.trim().startsWith("#")).count()
                == template.stream().filter(l -> l.trim().startsWith("#")).count());

        // BAR and the player changed things; BAR's engine dropped a default and repeated a key
        List<String> played = new ArrayList<>(first);
        played.add("snd_volmaster = 37");
        played.add("version = 5");
        played.replaceAll(l -> "Fullscreen".equals(SettingsMerge.configKey(l)) ? "Fullscreen = 1" : l);
        played.removeIf(l -> "CompressTextures".equals(SettingsMerge.configKey(l)));
        played.add("snd_volmaster = 99");
        List<String> second = lines(SettingsMerge.merge(template, played, set));
        Map<String, String> k2 = SettingsMerge.keys(second);
        check("BAR's settings kept (volume, migration version)", "37".equals(k2.get("snd_volmaster")) && "5".equals(k2.get("version")));
        check("an Android key set back (Fullscreen)", tpl.get("Fullscreen").equals(k2.get("Fullscreen")));
        check("a dropped template key back (CompressTextures)", tpl.get("CompressTextures").equals(k2.get("CompressTextures")));
        check("a key twice: the first counts, once in the file", count(second, "snd_volmaster") == 1);
        check("idempotent", SettingsMerge.merge(template, second, set).equals(String.join("\n", second) + "\n"));

        if (a.length > 1) {   // a real file from the phone
            List<String> phone = Files.readAllLines(Paths.get(a[1]), StandardCharsets.UTF_8);
            List<String> merged = lines(SettingsMerge.merge(template, phone, set));
            Map<String, String> kp = SettingsMerge.keys(phone), km = SettingsMerge.keys(merged);
            boolean kept = true;
            for (Map.Entry<String, String> e : kp.entrySet())
                if (!set.containsKey(e.getKey()) && !e.getValue().equals(km.get(e.getKey()))) { kept = false; System.out.println("     changed: " + e.getKey()); }
            check("the phone's file: every non-Android key kept (" + kp.size() + " keys)", kept);
            boolean forced = true;
            for (Map.Entry<String, String> e : set.entrySet()) forced &= e.getValue().equals(km.get(e.getKey()));
            check("the phone's file: every Android key set", forced);
            check("the phone's file: no key twice", km.size() == merged.stream().filter(l -> SettingsMerge.configKey(l) != null).count());
        }
        System.out.println(fails == 0 ? "ALL PASS" : fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
