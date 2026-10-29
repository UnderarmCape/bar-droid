package com.underarmcape.bardroid;

import android.os.SystemClock;
import android.view.KeyEvent;

import java.util.ArrayList;
import java.util.List;

import static com.underarmcape.bardroid.PadButtons.*;

/**
 * PadGame (the gamepad in BAR's game, v0.8.5's controls on a mouse and keys) on the laptop: button sequences in, the
 * mouse, keys and actions it sends out, against a made-up game state. Prints PASS/FAIL lines and "ALL PASS".
 *   tools/padgame-test.ps1 (laptop-tests), tools/java-checks.sh (CI)
 */
public final class PadGameTest {
    static int fails;

    /** A pointer, keyboard and game that write down what PadGame does. */
    static final class Fake implements PadMouse {
        final List<String> out = new ArrayList<>();
        String focus = "none", armed = "none";
        boolean pregame;
        float[] at;
        public int mode() { return MODE_GAME; }
        public float pixelsPerSecond() { return 1000; }
        public boolean onInterface() { return false; }
        public void move(int dx, int dy) { out.add("move " + dx + " " + dy); }
        public void button(boolean left, boolean down) { out.add((left ? "left " : "right ") + (down ? "down" : "up")); }
        public void wheel(float dy) { out.add("wheel"); }
        public void key(int keyCode, boolean down) { out.add("key " + keyCode + (down ? " down" : " up")); }
        public void act(String name) { out.add("act " + name); }
        public void centre() { out.add("centre"); }
        public void moveTo(float x, float y) { out.add("moveTo " + Math.round(x) + " " + Math.round(y)); }
        public int width() { return 2000; }
        public int height() { return 1000; }
        public float[] pointer() { return at; }
        public String padFocus() { return focus; }
        public boolean pregame() { return pregame; }
        public String armed() { return armed; }
    }

    final Fake m = new Fake();
    final PadGame g = new PadGame(m);
    final boolean[] held = new boolean[COUNT];
    boolean lt, rt;
    float lx, ly;

    /** One pump tick of 16 ms; pressed: buttons that went down since the last tick. */
    void tick(int... pressed) {
        boolean[] tapped = new boolean[COUNT];
        boolean active = lx != 0 || ly != 0 || lt || rt;
        for (int b : pressed) { tapped[b] = true; held[b] = true; }
        for (int b = 0; b < COUNT; b++) active |= held[b] || tapped[b];
        SystemClock.now += 16;
        g.tick(held, tapped, lx, ly, lt, rt, active, 0.016f);
    }

    void up(int b) { held[b] = false; tick(); }

    void wait(int ms) { for (int t = 0; t < ms; t += 16) tick(); }

    /** A tap: down for one tick, up the next. */
    void tap(int b) { tick(b); up(b); }

    static void check(String name, boolean ok, Object detail) {
        if (!ok) fails++;
        System.out.println((ok ? "PASS " : "FAIL ") + name + (ok ? "" : ": " + detail));
    }

    boolean has(String event) { return m.out.contains(event); }

    int count(String prefix) {
        int n = 0;
        for (String e : m.out) if (e.startsWith(prefix)) n++;
        return n;
    }

    public static void main(String[] args) {
        PadGameTest t;

        t = new PadGameTest();
        t.tick(); t.m.out.clear();
        t.tap(RB); t.wait(50);
        check("RB tapped: the build menu", t.has("act pad_build") && !t.has("key " + KeyEvent.KEYCODE_SPACE + " down"), t.m.out);

        t = new PadGameTest();
        t.tick(); t.m.out.clear();
        t.tick(RB); t.wait(300);
        check("RB held: Space (the order first in the queue)", t.has("key " + KeyEvent.KEYCODE_SPACE + " down"), t.m.out);
        t.up(RB);
        check("RB let go after holding: Space up, no build menu",
                t.has("key " + KeyEvent.KEYCODE_SPACE + " up") && !t.has("act pad_build"), t.m.out);

        t = new PadGameTest();
        t.m.focus = "build";
        t.tick(); t.m.out.clear();
        t.tick(RB); t.wait(300);
        check("RB held on the build menu: Alt (a factory queues it first), not Space",
                t.has("key " + KeyEvent.KEYCODE_ALT_LEFT + " down") && !t.has("key " + KeyEvent.KEYCODE_SPACE + " down"), t.m.out);
        t.up(RB);
        check("RB held on the build menu and let go: no page turned", !t.has("act pad_page_next"), t.m.out);
        t.tap(X);
        check("X on the build menu: the right button (one off a factory's queue)",
                t.has("right down") && t.has("right up"), t.m.out);
        t.m.out.clear();
        t.tap(RB); t.tap(LB);
        check("RB / LB tapped on the build menu: the next / previous page (not the menu off)",
                t.has("act pad_page_next") && t.has("act pad_page_prev") && !t.has("act pad_build"), t.m.out);

        t = new PadGameTest();
        t.tick(); t.m.out.clear();
        t.tick(BACK); t.tick(RB); t.up(RB); t.up(BACK);
        check("Back + RB: the order menu, no build menu", t.has("act pad_orders") && !t.has("act pad_build"), t.m.out);

        // LB + B: stop, repeat, wait, each alone (Kailil: "triggers stop first")
        t = new PadGameTest();
        t.tick(); t.tick(LB); t.m.out.clear();
        t.tap(B); t.wait(400);
        check("LB + B: stop", t.count("act lb_b") == 1 && t.has("act lb_b"), t.m.out);
        t.m.out.clear();
        t.tap(B); t.wait(100); t.tap(B); t.wait(400);
        check("LB + B twice: repeat, no stop", t.has("act lb_b2") && !t.has("act lb_b"), t.m.out);
        t.m.out.clear();
        t.tick(B); t.wait(550); t.up(B); t.wait(400);
        check("LB + B held: wait, no stop", t.has("act lb_b_hold") && !t.has("act lb_b") && !t.has("act lb_b2"), t.m.out);

        // A in the middle: a click there; held, the left stick draws; let go, the pointer glides back
        t = new PadGameTest();
        t.tick(); t.m.out.clear();
        t.tap(A);
        check("A: centred, a left click", t.m.out.indexOf("centre") >= 0
                && t.m.out.indexOf("centre") < t.m.out.indexOf("left down") && t.has("left up"), t.m.out);
        // v0.8.5's area select: A held with nothing picked
        t.m.out.clear();
        t.tick(A);
        t.lx = 1; t.wait(320); t.lx = 0;
        check("A held, nothing picked: the click let go and the area select on, the left stick still pans",
                t.has("left up") && t.has("act area_on") && t.count("move ") == 0 && t.g.reticle(), t.m.out);
        t.tap(DPAD_UP); t.tap(DPAD_LEFT);
        check("the D-pad sizes the circle (no idle builders, no bookmark)", t.has("act area_bigger") && t.has("act area_smaller")
                && !t.has("act idle_prev") && !t.has("act bookmark_recall"), t.m.out);
        t.up(A);
        check("A let go: the area select over", t.has("act area_off"), t.m.out);
        t.m.out.clear();
        t.tick(A); t.wait(320); t.tap(B);
        check("B in the area select: undone, no cancel as well", t.has("act area_cancel") && !t.has("act cancel"), t.m.out);
        t.up(A);
        check("A let go after B: nothing more", !t.has("act area_off"), t.m.out);

        // With an order picked, A held draws with the pointer
        t.m.armed = "unitarea";
        t.m.out.clear();
        t.tick(A);
        t.lx = 1; t.wait(200); t.lx = 0;
        check("A held with an order picked + left stick: the pointer moves (a drag BAR sees), the camera does not pan",
                t.count("move ") > 0 && !t.g.reticle() && !t.has("act area_on"), t.m.out);
        t.m.out.clear();
        t.up(A); t.wait(250);
        String last = t.m.out.isEmpty() ? "" : t.m.out.get(t.m.out.size() - 1);
        check("A let go: the pointer glides back to the middle in steps", t.count("moveTo ") >= 5
                && last.equals("moveTo 1000 500") && t.g.reticle(), t.m.out);
        String first = null;
        for (String e : t.m.out) if (e.startsWith("moveTo ")) { first = e; break; }
        check("the glide starts near where the pointer was, not in the middle", first != null && !first.equals("moveTo 1000 500"), first);

        t = new PadGameTest();
        t.tick(); t.m.out.clear();
        t.tick(X); t.lx = 1; t.wait(200); t.lx = 0;
        check("X held + left stick: the right button held while the pointer moves (a path)",
                t.has("right down") && !t.has("right up") && t.count("move ") > 0, t.m.out);
        t.up(X);
        check("X let go: the right button up (the path given)", t.has("right up"), t.m.out);

        // v0.8.5's placement: LB held a grid (Alt); a tap of A starts it, the next A places it; B cancels
        t = new PadGameTest();
        t.m.armed = "build";
        t.tick(); t.m.out.clear();
        t.tick(LB);
        t.tap(A);
        check("a building picked, LB held: Alt, and a tap of A starts the grid (the button stays down)",
                t.has("key " + KeyEvent.KEYCODE_ALT_LEFT + " down") && t.has("left down") && !t.has("left up"), t.m.out);
        t.lx = 1; t.wait(150); t.lx = 0;
        check("the left stick draws the grid", t.count("move ") > 0, t.m.out);
        t.m.out.clear();
        t.tap(A);
        check("the next A places it", t.has("left up"), t.m.out);
        t.m.out.clear();
        t.tap(A); t.tap(X);
        check("X ends a grid placing it and keeping the building (Shift)", t.m.out.indexOf("key " + KeyEvent.KEYCODE_SHIFT_LEFT + " down")
                < t.m.out.indexOf("left up") && t.has("left up"), t.m.out);
        t.m.out.clear();
        t.tap(A); t.tap(B);
        check("B in a grid: cancel first", t.has("act cancel") && !t.has("left up"), t.m.out);
        t.wait(300);
        check("then the button let go (nothing placed: the building was put away)", t.has("left up"), t.m.out);

        t = new PadGameTest();
        t.m.armed = "area";
        t.tick(); t.m.out.clear();
        t.tap(A);
        check("an area order (area mex): a tap of A starts its circle", t.has("left down") && !t.has("left up"), t.m.out);
        t.tap(A);
        check("the next A gives it", t.has("left up"), t.m.out);

        t = new PadGameTest();
        t.m.armed = "build";
        t.tick(); t.m.out.clear();
        t.tap(A);
        check("a building picked, no LB: A places it (down and up)", t.has("left down") && t.has("left up"), t.m.out);
        t.m.out.clear();
        t.tap(X);
        check("X places it and keeps it (a Shift click)", t.m.out.indexOf("key " + KeyEvent.KEYCODE_SHIFT_LEFT + " down")
                < t.m.out.indexOf("left down") && t.has("left up") && !t.has("right down"), t.m.out);
        t.m.out.clear();
        t.tap(BACK);
        check("Back alone while placing: the slow pan", t.has("act slow_pan"), t.m.out);
        t.m.out.clear();
        t.tap(DPAD_LEFT); t.tap(DPAD_UP);
        check("D-pad while placing: turn and spacing", t.has("act rotate_left") && t.has("act spacing_up"), t.m.out);

        // The order menu: the pointer at half speed
        t = new PadGameTest();
        t.m.focus = "build";
        t.tick(); t.m.out.clear();
        t.lx = 1; t.wait(320);
        int build = 0;
        for (String e : t.m.out) if (e.startsWith("move ")) build += Integer.parseInt(e.split(" ")[1]);
        t = new PadGameTest();
        t.m.focus = "orders";
        t.tick(); t.m.out.clear();
        t.lx = 1; t.wait(320);
        int orders = 0;
        for (String e : t.m.out) if (e.startsWith("move ")) orders += Integer.parseInt(e.split(" ")[1]);
        check("the order menu: the pointer at 5/8 speed (half, then a quarter faster)", build > 0
                && Math.abs(orders * 8 - build * 5) <= 32, orders + " against " + build);
        t.m.out.clear();
        t.tap(A); t.tap(B); t.tap(DPAD_RIGHT);
        check("the order menu: A gives the order, B leaves, the D-pad steps (no clicks)",
                t.has("act pad_select") && t.has("act pad_back") && t.has("act pad_right") && !t.has("left down"), t.m.out);

        // After touch moved the pointer, a resting pad leaves it alone; used again, it brings the pointer back gliding
        t = new PadGameTest();
        t.tick(); t.m.out.clear();
        t.m.at = new float[]{200, 100};
        t.g.otherInput();
        t.wait(500);
        check("a pad lying unused leaves the pointer to touch or the mouse",
                !t.has("centre") && t.count("moveTo ") == 0, t.m.out);
        t.lx = 0.5f; t.tick(); t.lx = 0; t.wait(250);
        check("used again (the left stick), the pointer glides back from where it was",
                t.m.out.contains("moveTo 1000 500") && !t.has("centre") && t.count("moveTo ") >= 5, t.m.out);
        t.m.out.clear();
        t.lx = 1; t.tick(); t.lx = 0;   // (a glide under way when touch takes the pointer again stops)
        t.m.at = new float[]{1500, 900};
        t.g.otherInput();
        t.wait(100);
        check("a glide stops when touch takes the pointer", t.count("moveTo ") <= 2, t.m.out);
        t = new PadGameTest();
        t.wait(300);
        check("a pad connected at the start but unused does not take the pointer", t.m.out.isEmpty(), t.m.out);

        // Control groups (Start + D-pad): the slot, a tap recalls, held assigns, right autogroups, L3 clears
        t = new PadGameTest();
        t.tick(); t.m.out.clear();
        t.tick(START); t.tap(DPAD_UP);
        check("Start + D-pad up: the next group slot", t.has("act group_show_2") && !t.has("act bookmark_recall"), t.m.out);
        t.tap(DPAD_LEFT);
        check("Start + D-pad left tapped: the group recalled", t.has("act group_recall_2") && !t.has("act group_assign_2")
                && !t.has("act idle_prev"), t.m.out);
        t.m.out.clear();
        t.tick(DPAD_LEFT); t.wait(400); t.up(DPAD_LEFT);
        check("Start + D-pad left held: the selection assigned, no recall", t.has("act group_assign_2")
                && !t.has("act group_recall_2"), t.m.out);
        t.m.out.clear();
        t.tap(DPAD_RIGHT);
        int altDown = t.m.out.indexOf("key " + KeyEvent.KEYCODE_ALT_LEFT + " down");
        check("Start + D-pad right: BAR's autogroup (Alt + 2)", altDown >= 0
                && altDown < t.m.out.indexOf("key " + (KeyEvent.KEYCODE_1 + 1) + " down")
                && t.has("key " + KeyEvent.KEYCODE_ALT_LEFT + " up") && t.has("act group_auto_2") && !t.has("act idle_next"), t.m.out);
        t.m.out.clear();
        t.tap(LS);
        check("Start + L3: the group cleared, no queued order removed", t.has("act group_clear_2")
                && !t.has("act queue_remove_first"), t.m.out);
        t.up(START);

        // The D-pad's own work; L3 / R3; Back + R3; LB with the face buttons and the D-pad
        t.m.out.clear();
        t.tap(DPAD_RIGHT); t.tap(DPAD_LEFT); t.tap(DPAD_DOWN); t.tap(DPAD_UP);
        check("the D-pad: idle builders, the commander, the bookmark (no groups)", t.has("act idle_next")
                && t.has("act idle_prev") && t.has("act commander") && t.has("act bookmark_recall") && t.count("act group_") == 0, t.m.out);
        t.m.out.clear();
        t.lt = true; t.tap(DPAD_UP); t.lt = false; t.tick();
        check("LT + D-pad up: the bookmark stored", t.has("act bookmark_store") && !t.has("act bookmark_recall"), t.m.out);
        t.m.out.clear();
        t.tap(LS); t.tap(RS);
        check("L3 / R3: the next / last queued order removed", t.has("act queue_remove_first")
                && t.has("act queue_remove_last") && !t.has("act dgun"), t.m.out);
        t.m.out.clear();
        t.tick(BACK); t.tap(RS); t.up(BACK);
        check("Back + R3: the D-gun, no order removed", t.has("act dgun") && !t.has("act queue_remove_last"), t.m.out);
        t.m.out.clear();
        t.tick(LB); t.tap(Y); t.tap(A); t.tap(X); t.up(LB);
        check("LB + Y / A / X: patrol, fight, attack (no clicks)", t.has("act lb_y") && t.has("act lb_a") && t.has("act lb_x")
                && !t.has("left down") && !t.has("right down"), t.m.out);
        t.m.out.clear();
        t.tick(LB); t.tap(DPAD_RIGHT); t.tap(DPAD_LEFT); t.tap(DPAD_DOWN); t.up(LB);
        check("LB + D-pad: the other idle units, idle of the type (no builders, no commander)", t.has("act idle_mobile_next")
                && t.has("act idle_mobile_prev") && t.has("act idle_type") && !t.has("act idle_next") && !t.has("act commander"), t.m.out);

        // Back + Start: a free pointer on the left stick, and back to the middle
        t.m.out.clear();
        t.tick(BACK); t.tap(START); t.up(BACK);
        t.lx = 1; t.wait(100); t.lx = 0;
        check("Back + Start: a free pointer the left stick moves", t.has("act mouse_toggle") && !t.g.reticle()
                && t.count("move ") > 0, t.m.out);
        t.m.out.clear();
        t.m.at = new float[]{1300, 500};   // (where the free pointer went, by the game's answer)
        t.tick(START); t.tap(BACK); t.up(START); t.wait(250);
        check("Start + Back: the pointer glides back and is held in the middle again", t.has("act mouse_toggle")
                && t.g.reticle() && t.count("moveTo ") >= 5 && t.m.out.contains("moveTo 1000 500") && !t.has("centre"), t.m.out);

        System.out.println(fails == 0 ? "ALL PASS" : fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
