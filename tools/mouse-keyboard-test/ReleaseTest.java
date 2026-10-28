package com.underarmcape.bardroid;

/** CtrlAltRelease (MouseKeyboard's Ctrl+Alt: the mouse back to Android). tools/mouse-keyboard-test.ps1 runs it. */
public class ReleaseTest {
    static final int C = CtrlAltRelease.CTRL, A = CtrlAltRelease.ALT, O = CtrlAltRelease.OTHER;
    static int failed;

    /** Steps: "+C" Ctrl down, "-A" Alt up, "+O" another key down, "K" a click; '!' after an up = it must release. */
    static void check(String name, String... steps) {
        CtrlAltRelease r = new CtrlAltRelease();
        boolean ok = true;
        for (String s : steps) {
            char k = s.length() > 1 ? s.charAt(1) : ' ';
            int key = k == 'C' ? C : k == 'A' ? A : O;
            switch (s.charAt(0)) {
                case '+': r.down(key); break;
                case 'K': r.click(); break;
                case '-': ok &= r.up(key) == s.endsWith("!"); break;
                default: throw new IllegalArgumentException(s);
            }
        }
        System.out.println((ok ? "PASS " : "FAIL ") + name);
        if (!ok) failed++;
    }

    public static void main(String[] a) {
        check("Ctrl+Alt, Alt up first", "+C", "+A", "-A!", "-C");
        check("Alt+Ctrl, Ctrl up first", "+A", "+C", "-C!", "-A");
        check("Ctrl+Alt+key is BAR's", "+C", "+A", "+O", "-O", "-A", "-C");
        check("Ctrl+Alt+click is BAR's", "+C", "+A", "K", "-A", "-C");
        check("Ctrl alone", "+C", "-C");
        check("Alt+Tab", "+A", "+O", "-O", "-A");
        check("twice in a row", "+C", "+A", "-C!", "-A", "+C", "+A", "-A!", "-C");
        check("a key before, then a lone Ctrl+Alt", "+O", "-O", "+C", "+A", "-A!", "-C");
        check("Ctrl, Alt, Alt again (one press)", "+C", "+A", "-A!", "+A", "-A", "-C");
        check("left and right Ctrl", "+C", "+C", "+A", "-C!", "-C", "-A");
        System.out.println(failed == 0 ? "ALL PASS" : failed + " FAILED");
        System.exit(failed == 0 ? 0 : 1);
    }
}
