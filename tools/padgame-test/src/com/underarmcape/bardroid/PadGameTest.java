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
        float speed = 1;
        public float drawSpeed() { return speed; }
        boolean riding;
        public boolean firstPerson() { return riding; }
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

    /** How far the pointer moved, sideways and down, by the moves written down. */
    static int sumMoves(PadGameTest t) {
        int sum = 0;
        for (String e : t.m.out) {
            if (!e.startsWith("move ")) continue;
            String[] f = e.split(" ");
            sum += Math.abs(Integer.parseInt(f[1])) + Math.abs(Integer.parseInt(f[2]));
        }
        return sum;
    }

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
        // v0.8.5's filter radial (Kailil, 2026-10-29): A held, then X; the left stick picks a side, X let go takes it
        t.m.out.clear();
        t.tick(A); t.wait(320); t.tick(X);
        check("A held, then X: the filter radial, no right click, the stick no longer pans", t.has("act area_filter_open")
                && !t.has("right down") && t.g.stickTaken(), t.m.out);
        t.lx = -1; t.tick(); t.tick(); t.lx = 0; t.tick();
        check("the left stick left: Builders lit (once)", t.count("act area_filter_left") == 1, t.m.out);
        t.up(X);
        check("X let go: the filter taken, the stick pans again", t.has("act area_filter_pick") && !t.g.stickTaken(), t.m.out);
        t.up(A);
        check("A let go: the area select over", t.has("act area_off") && !t.has("right down"), t.m.out);

        // With an order picked, A held draws with the pointer, once held past the hold time (Kailil, 2026-10-29: a press
        // while the camera moved drew a tiny path); a shorter press is a click when let go
        t.m.armed = "unitarea";
        t.m.out.clear();
        t.lx = 1; t.tap(A); t.wait(50); t.lx = 0;
        check("A tapped with an order picked while the camera pans: a click when let go, no drag",
                t.has("left down") && t.has("left up") && t.count("move ") == 0, t.m.out);
        t.m.out.clear();
        t.tick(A);
        t.lx = 1; t.wait(150);
        check("A held with an order picked, under the hold time: no button yet, the stick still pans",
                !t.has("left down") && t.count("move ") == 0 && t.g.reticle(), t.m.out);
        t.wait(250); t.lx = 0;
        check("A held with an order picked + left stick: the pointer moves (a drag BAR sees), the camera does not pan",
                t.has("left down") && t.count("move ") > 0 && !t.g.reticle() && !t.has("act area_on"), t.m.out);
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
        t.lx = 1; t.tap(X); t.wait(50); t.lx = 0;
        check("X tapped while the camera pans: a right click, no path", t.has("right down") && t.has("right up")
                && t.count("move ") == 0, t.m.out);
        t.m.out.clear();
        t.tick(X); t.lx = 1; t.wait(150);
        check("X held under the hold time: no button yet, the stick still pans", !t.has("right down")
                && t.count("move ") == 0 && t.g.reticle(), t.m.out);
        t.wait(250); t.lx = 0;
        check("X held + left stick: the right button held while the pointer moves (a path)",
                t.has("right down") && !t.has("right up") && t.count("move ") > 0, t.m.out);
        t.up(X);
        check("X let go: the right button up (the path given)", t.has("right up"), t.m.out);

        // v0.8.5's placement: LB held a grid (Alt); a tap of A starts it, the next A places it; B cancels
        t = new PadGameTest();
        t.m.armed = "build";
        t.tick(); t.m.out.clear();
        t.tick(LB);
        check("a building picked, LB: Shift+Alt (the engine lays out a build drag only with Shift) and GRID shown",
                t.has("key " + KeyEvent.KEYCODE_ALT_LEFT + " down") && t.has("key " + KeyEvent.KEYCODE_SHIFT_LEFT + " down")
                && t.has("act grid_on"), t.m.out);
        t.tap(A);
        check("a building picked, LB held: a tap of A starts the grid (the button stays down)",
                t.has("left down") && !t.has("left up"), t.m.out);
        t.up(LB);
        t.lx = 1; t.wait(150); t.lx = 0;
        check("the left stick draws the grid, LB let go: Shift+Alt held on", t.count("move ") > 0
                && !t.has("key " + KeyEvent.KEYCODE_ALT_LEFT + " up") && !t.has("key " + KeyEvent.KEYCODE_SHIFT_LEFT + " up"), t.m.out);
        t.m.out.clear();
        t.tap(A);
        int leftUp = t.m.out.indexOf("left up");
        check("the next A places it (Shift+Alt let go after)", leftUp >= 0
                && t.m.out.indexOf("key " + KeyEvent.KEYCODE_ALT_LEFT + " up") > leftUp, t.m.out);
        t.wait(200);
        check("... and puts the building away, as v0.8.5's A", t.has("act build_exit"), t.m.out);
        t.tick(LB);
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

        // Control groups (Start or Back + D-pad): the slot, left tap selects, left held assigns (and BAR's autogroup), right
        // tap the camera, right held clears, Start + L3 clears
        t = new PadGameTest();
        t.tick(); t.m.out.clear();
        t.tick(START); t.tap(DPAD_UP);
        check("Start held: the group list shows", t.has("act group_list_on"), t.m.out);
        check("Start + D-pad up: the next group slot", t.has("act group_show_2") && !t.has("act bookmark_recall"), t.m.out);
        t.tap(DPAD_LEFT);
        check("Start + D-pad left tapped: the group recalled", t.has("act group_recall_2") && !t.has("act group_assign_2")
                && !t.has("act idle_prev"), t.m.out);
        t.m.out.clear();
        t.tick(DPAD_LEFT); t.wait(400); t.up(DPAD_LEFT);
        check("Start + D-pad left held: the group assigned once, no keys pressed, no recall", t.count("act group_assign_2") == 1
                && t.count("key ") == 0 && !t.has("act group_recall_2"), t.m.out);
        t.m.out.clear();
        t.tap(DPAD_RIGHT);
        check("Start + D-pad right tapped: the camera to the group", t.has("act group_look_2") && !t.has("act group_clear_2")
                && !t.has("act idle_next"), t.m.out);
        t.m.out.clear();
        t.tick(DPAD_RIGHT); t.wait(400); t.up(DPAD_RIGHT);
        check("Start + D-pad right held: the group cleared, no camera move", t.has("act group_clear_2")
                && !t.has("act group_look_2"), t.m.out);
        t.m.out.clear();
        t.tap(LS);
        check("Start + L3: the group cleared, no queued order removed", t.has("act group_clear_2")
                && !t.has("act queue_remove_first"), t.m.out);
        t.up(START);
        check("Start let go: the group list goes (after a moment)", t.has("act group_list_off"), t.m.out);
        t.m.out.clear();
        t.tick(BACK); t.tap(DPAD_LEFT); t.tap(DPAD_RIGHT); t.up(BACK);
        check("Back + D-pad works as Start + D-pad, no idle builders", t.has("act group_list_on") && t.has("act group_recall_2")
                && t.has("act group_look_2") && !t.has("act idle_prev") && !t.has("act idle_next"), t.m.out);

        // Fight and patrol paths: LB + A / Y held draws, RB held Alt, let go: the drag ends; a tap stays the order at the middle
        t = new PadGameTest();
        t.tick(); t.m.out.clear();
        t.tick(LB); t.tick(A); t.wait(300);
        check("LB + A held: fight picked", t.has("act path_fight") && !t.has("act lb_a") && !t.has("right down"), t.m.out);
        t.m.armed = "other";
        t.wait(200);
        check("... and once the game has it the right button goes down in the middle (BAR's formations draw with no other)",
                t.has("right down") && !t.has("left down") && t.has("centre"), t.m.out);
        t.up(LB);
        t.m.out.clear();
        t.lx = 1; t.tick(); t.tick(); t.lx = 0; t.tick();
        check("LB may be let go: the left stick draws, the button stays down", t.count("move ") > 0 && !t.has("right up"), t.m.out);
        t.tick(RB); t.wait(16);
        check("RB held on a path: Alt (the other fight), no Space", t.has("key " + KeyEvent.KEYCODE_ALT_LEFT + " down")
                && !t.has("key " + KeyEvent.KEYCODE_SPACE + " down"), t.m.out);
        t.up(A);
        check("A let go: the path given (the button up), the order put away", t.has("right up") && t.has("act path_end"), t.m.out);
        t.up(RB); t.m.armed = "none"; t.m.out.clear();
        t.tick(LB); t.tick(Y); t.wait(300);
        t.m.armed = "other"; t.wait(200);
        check("LB + Y held: a patrol path, the right button down", t.has("act path_patrol") && t.has("right down"), t.m.out);
        t.wait(300);
        check("... and it stays down with X not held", !t.has("right up"), t.m.out);
        t.m.out.clear();
        t.up(Y);
        check("Y let go ends it (A was never down)", t.has("right up") && t.has("act path_end"), t.m.out);
        t.up(LB); t.m.armed = "none"; t.m.out.clear();
        t.tick(LB); t.tick(A); t.wait(300); t.wait(200); t.up(A); t.up(LB);
        check("nothing that can take the order: no drag", t.has("act path_fight") && !t.has("right down"), t.m.out);

        // The pointer's speed while drawing: the zoom's; LT slows it only from a standstill
        t = new PadGameTest();
        t.tick(); t.m.out.clear();
        t.tick(X); t.wait(300); t.m.out.clear();
        t.m.speed = 0.5f; t.lx = 1; t.tick(); t.tick(); t.tick(); t.tick();
        int half = sumMoves(t);
        t.m.out.clear(); t.m.speed = 1; t.tick(); t.tick(); t.tick(); t.tick();
        check("drawing: the zoom's speed", Math.abs(sumMoves(t) - half * 2) <= 2, half + " " + sumMoves(t));
        t.lx = 0; t.up(X);
        t.m.out.clear(); t.wait(250);
        t.lt = true; t.tick(X); t.wait(300); t.m.out.clear();
        t.lx = 1; t.tick(); t.tick(); t.tick(); t.tick();
        int slow = sumMoves(t);
        t.lx = 0; t.lt = false; t.up(X); t.wait(250);
        t.lt = true; t.lx = 1; t.tick(X); t.wait(300); t.m.out.clear(); t.tick(); t.tick(); t.tick(); t.tick();
        check("LT from a standstill slows the drawing; with the stick already moving it does not", sumMoves(t) > slow * 2,
                slow + " " + sumMoves(t));
        t.lx = 0; t.lt = false; t.up(X);

        // A held: the D-pad sizes the circle, held quickly
        t = new PadGameTest();
        t.tick(); t.m.out.clear();
        t.tick(A); t.wait(300);
        check("(the area select is on)", t.has("act area_on"), t.m.out);
        t.m.out.clear();
        t.tick(DPAD_LEFT); t.wait(1000); t.up(DPAD_LEFT);
        int steps = t.count("act area_smaller");
        check("D-pad held: the circle steps quickly", steps >= 8 && steps <= 16, steps);
        t.m.out.clear();
        t.wait(300);
        check("D-pad let go: no more steps", t.count("act area_") == 0, t.m.out);
        t.up(A);

        // Back + R3 + L3 held: self-destruct, no D-gun, no order removed; Back + Y: the tuner
        t = new PadGameTest();
        t.tick(); t.m.out.clear();
        t.tick(BACK); t.tick(RS); t.tick(LS); t.wait(800); t.up(RS); t.up(LS); t.up(BACK);
        check("Back + R3 + L3 held: self-destruct once, no D-gun, nothing removed", t.count("act selfd") == 1 && !t.has("act dgun")
                && !t.has("act queue_remove_first") && !t.has("act queue_remove_last"), t.m.out);
        t.m.out.clear();
        t.tick(BACK); t.tap(Y); t.up(BACK);
        check("Back + Y: the path speed tuner", t.has("act pad_speed"), t.m.out);

        // First person: LB + L3 held, no order removed; in it only B and RT count
        t = new PadGameTest();
        t.tick(); t.m.out.clear();
        t.tick(LB); t.tick(LS); t.wait(350); t.up(LS); t.up(LB);
        check("LB + L3 held 0.3 s: first person, once, no order removed", t.count("act fp_toggle") == 1
                && !t.has("act queue_remove_first"), t.m.out);
        t.m.out.clear();
        t.tick(LB); t.tap(LS); t.up(LB);
        check("LB + L3 tapped: nothing", t.m.out.stream().noneMatch(e -> e.equals("act fp_toggle") || e.equals("act queue_remove_first")), t.m.out);
        t.m.riding = true; t.m.out.clear();
        t.tap(A); t.tap(X); t.tap(Y); t.tap(RB); t.tap(DPAD_UP); t.tap(DPAD_DOWN); t.tap(DPAD_LEFT); t.tap(DPAD_RIGHT); t.tap(BACK);
        t.rt = true; t.tick(); t.tick(); t.rt = false; t.tick();
        check("riding: A, X, Y, RB, D-pad up and down are the squad's orders", t.has("act fp_order_follow") && t.has("act fp_order_stop")
                && t.has("act fp_order_fight") && t.has("act fp_order_patrol") && t.has("act fp_order_add") && t.has("act fp_order_clear"), t.m.out);
        check("riding: Back the camera tuner, D-pad left and right its less and more", t.has("act fp_order_tune")
                && t.has("act fp_order_left") && t.has("act fp_order_right") && !t.has("act group_list_on"), t.m.out);
        check("riding: RT fires and lets go, once each, no Shift, no clicks, no menus", t.count("act fp_fire_on") == 1
                && t.count("act fp_fire_off") == 1 && !t.has("key " + KeyEvent.KEYCODE_SHIFT_LEFT + " down")
                && !t.has("left down") && !t.has("right down") && !t.has("act pad_build") && !t.has("act idle_prev"), t.m.out);
        t.m.out.clear();
        t.tap(B);
        check("riding: B ends it", t.has("act fp_toggle") && !t.has("act cancel"), t.m.out);
        t.m.riding = false;
        PadGameTest r = new PadGameTest();
        r.tick(); r.m.armed = "build"; r.tick(LB); r.m.out.clear(); r.m.riding = true; r.tick();
        check("riding: LB on a building lets go of Shift and Alt as it starts", r.has("key " + KeyEvent.KEYCODE_SHIFT_LEFT + " up")
                && r.has("key " + KeyEvent.KEYCODE_ALT_LEFT + " up"), r.m.out);
        r = new PadGameTest();
        r.tick(); r.tick(RB); r.wait(500); r.m.out.clear(); r.m.riding = true; r.tick();
        check("riding: RB held lets go of Space as it starts", r.has("key " + KeyEvent.KEYCODE_SPACE + " up"), r.m.out);

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
