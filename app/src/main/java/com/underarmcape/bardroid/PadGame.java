package com.underarmcape.bardroid;

import android.os.SystemClock;
import android.view.KeyEvent;

import static com.underarmcape.bardroid.ControllerBridge.BTN_A;
import static com.underarmcape.bardroid.ControllerBridge.BTN_B;
import static com.underarmcape.bardroid.ControllerBridge.BTN_BACK;
import static com.underarmcape.bardroid.ControllerBridge.BTN_DPAD_DOWN;
import static com.underarmcape.bardroid.ControllerBridge.BTN_DPAD_LEFT;
import static com.underarmcape.bardroid.ControllerBridge.BTN_DPAD_RIGHT;
import static com.underarmcape.bardroid.ControllerBridge.BTN_DPAD_UP;
import static com.underarmcape.bardroid.ControllerBridge.BTN_LB;
import static com.underarmcape.bardroid.ControllerBridge.BTN_LS;
import static com.underarmcape.bardroid.ControllerBridge.BTN_RB;
import static com.underarmcape.bardroid.ControllerBridge.BTN_RS;
import static com.underarmcape.bardroid.ControllerBridge.BTN_START;
import static com.underarmcape.bardroid.ControllerBridge.BTN_X;
import static com.underarmcape.bardroid.ControllerBridge.BTN_Y;
import static com.underarmcape.bardroid.ControllerBridge.BUTTON_COUNT;

/**
 * The gamepad in BAR's own game (online, spectating): Kailil's BAR Controller Support v0.8.5 ("Build-First Commander")
 * rebuilt on a mouse and keyboard, which BAR's sandbox cannot see or block (Kailil, 2026-10-29: "match 1to1 using any
 * means necessary ... dont worry about radials ... I want mouse to be locked to the center of the screen like it is in
 * 8.5"). Game-side work goes to bardroid_pad.lua and bardroid_buildmenu.lua as actions ("act" lines):
 *
 *   pointer      locked to the middle of the screen (v0.8.5's reticle) while the pad is the input
 *   left stick   pans the map under it (LT held: faster); right stick turns (x) and zooms (y), LB + right stick tilts
 *   A            left click there: select (twice: that type on screen; held: box select), place a building
 *   X            BAR's right click there (the smart action: move, attack, repair, reclaim, guard; held: a path)
 *   B            cancel the order or building picked, else clear the selection
 *   RT held      Shift (queue)                    RB held  Space (put the order first in the queue)
 *   RB tap       the build menu (the D-pad steps through it, A picks, B leaves)
 *   Back + RB    the order menu, the same way (A gives the order: targeted ones go back to the middle to aim)
 *   D-pad        right / left: next / previous idle builder; down: the commander; up: camera bookmark (LT + up: store)
 *   LB + D-pad   right / left: next / previous idle unit of the rest; down: every idle unit of the last one's type
 *   LB + A/X/Y   fight (attack the enemy there) / attack / patrol, at the middle; LB + B: stop (twice: repeat; held: wait)
 *   Start + D-pad  control groups: up / down the slot, left tap recall (held: assign), right: same type from now on;
 *                Start + L3: clear the group
 *   L3 / R3      remove the next / the last queued order; Back + R3: D-gun
 *   Back + Start a free pointer on the left stick (any of BAR's windows), and back; free by itself before the start
 *   a building picked: A places it, X places it and keeps it, D-pad left/right turns it and up/down spaces a row,
 *                LB held: Alt (a drag makes a filled area), B puts it away
 *
 * Pump thread only, except {@link #otherInput}.
 */
final class PadGame {
    private static final long RB_TAP_MS = 220, ASSIGN_HOLD_MS = 350, LB_B_DOUBLE_MS = 350, LB_B_HOLD_MS = 500;
    private static final float FINE_AIM = 0.35f, ON_INTERFACE = 0.6f;

    private final ControllerBridge.Mouse mouse;
    private final boolean[] prev = new boolean[BUTTON_COUNT];
    private boolean leftDown, rightDown, shift, space, alt;
    private boolean mouseMode;                   // Back+Start: a free pointer
    private volatile boolean centreWanted = true; // the pointer must go (back) to the middle
    private boolean reticle;
    private long rbDownAt = -1, startLeftAt = -1, lbBDownAt = -1, lbBTapAt;
    private boolean rbUsed, startLeftDone, lbBHeld;
    private int groupSlot = 1;
    private float fracX, fracY;

    PadGame(ControllerBridge.Mouse mouse) { this.mouse = mouse; }

    /** Touch or a real mouse moved the pointer: the pad puts it back in the middle when it is used again. Any thread. */
    void otherInput() { centreWanted = true; }

    /** The left stick pans the camera (the pointer in the middle) rather than moving the pointer. */
    boolean reticle() { return reticle; }

    /** Lets go of every button and key the pad holds (a mode change, a pause). */
    void release() {
        if (leftDown) { leftDown = false; mouse.button(true, false); }
        if (rightDown) { rightDown = false; mouse.button(false, false); }
        if (shift) { shift = false; mouse.key(KeyEvent.KEYCODE_SHIFT_LEFT, false); }
        if (space) { space = false; mouse.key(KeyEvent.KEYCODE_SPACE, false); }
        if (alt) { alt = false; mouse.key(KeyEvent.KEYCODE_ALT_LEFT, false); }
        java.util.Arrays.fill(prev, false);
        rbDownAt = startLeftAt = lbBDownAt = -1;
        centreWanted = true;
    }

    /**
     * One pump tick. held: the buttons down now; tapped: pressed since the last tick (even if already up again);
     * lx, ly: the left stick (-1..1 past the deadzone); lt, rt: the triggers held.
     */
    void tick(boolean[] held, boolean[] tapped, float lx, float ly, boolean lt, boolean rt, float dt) {
        long now = SystemClock.uptimeMillis();
        String focus = mouse.padFocus();
        boolean menu = !focus.equals("none");
        boolean picked = !menu && mouse.buildingPicked();
        boolean free = mouseMode != mouse.pregame();   // (before the start the pointer is free, as in v0.8.5)
        boolean wasReticle = reticle;
        reticle = !menu && !free;
        if (reticle && !wasReticle) centreWanted = true;
        boolean back = held[BTN_BACK], start = held[BTN_START], lb = held[BTN_LB];

        // Modifier keys: RT Shift; RB held past a tap Space; LB with a building picked Alt
        if (rt != shift) { shift = rt; mouse.key(KeyEvent.KEYCODE_SHIFT_LEFT, rt); }
        boolean wantAlt = lb && picked;
        if (wantAlt != alt) { alt = wantAlt; mouse.key(KeyEvent.KEYCODE_ALT_LEFT, wantAlt); }

        // Back chords: + RB the order menu, + Start the free pointer, + R3 the D-gun
        if (back && pressed(tapped, BTN_RB)) { mouse.act("pad_orders"); rbDownAt = -1; rbUsed = true; }
        if ((back && pressed(tapped, BTN_START)) || (start && pressed(tapped, BTN_BACK))) {
            mouseMode = !mouseMode;
            mouse.act("mouse_toggle");   // (bardroid_pad.lua keeps the same switch: its reticle and note)
        }
        if (back && pressed(tapped, BTN_RS)) mouse.act("dgun");

        // RB: a quick tap the build menu; held past the tap (or with another button) Space
        if (!back && pressed(tapped, BTN_RB)) { rbDownAt = now; rbUsed = false; }
        if (held[BTN_RB] && rbDownAt >= 0 && !rbUsed && (now - rbDownAt > RB_TAP_MS || anyFace(tapped))) rbUsed = true;
        boolean wantSpace = held[BTN_RB] && rbUsed && rbDownAt >= 0;
        if (wantSpace != space) { space = wantSpace; mouse.key(KeyEvent.KEYCODE_SPACE, wantSpace); }
        if (released(held, tapped, BTN_RB)) {
            if (rbDownAt >= 0 && !rbUsed) mouse.act("pad_build");
            rbDownAt = -1;
        }

        // The pointer: in the middle, or moved by the left stick
        if (reticle && centreWanted) { centreWanted = false; mouse.centre(); }
        if (!reticle && (lx != 0 || ly != 0)) {
            float step = mouse.pixelsPerSecond() * dt * (lt ? FINE_AIM : 1f) * (mouse.onInterface() ? ON_INTERFACE : 1f);
            fracX += lx * step; fracY += ly * step;
            int ix = (int) fracX, iy = (int) fracY;
            fracX -= ix; fracY -= iy;
            if (ix != 0 || iy != 0) mouse.move(ix, iy);
        } else {
            fracX = fracY = 0;
        }

        // The mouse buttons: A left (not on the order menu, which takes A as an action; not with LB, the order
        // shortcuts); X right (normal play only)
        boolean ordersMenu = focus.equals("orders");
        boolean aClicks = !ordersMenu && !(lb && !menu && !picked);
        boolean a = held[BTN_A] && aClicks, aTap = tapped[BTN_A] && aClicks;
        if ((a || aTap) && !leftDown) {
            if (reticle) mouse.centre();
            leftDown = true;
            mouse.button(true, true);
        }
        if (!a && leftDown) { leftDown = false; mouse.button(true, false); }
        boolean xClicks = !menu && !picked && !lb;
        boolean x = held[BTN_X] && xClicks, xTap = tapped[BTN_X] && xClicks;
        if ((x || xTap) && !rightDown) {
            if (reticle) mouse.centre();
            rightDown = true;
            mouse.button(false, true);
        }
        if (!x && rightDown) { rightDown = false; mouse.button(false, false); }

        if (menu) {
            menuButtons(tapped, ordersMenu);
        } else if (picked) {
            pickedButtons(tapped);
        } else {
            playButtons(held, tapped, lb, start, back, lt, now);
        }
        System.arraycopy(held, 0, prev, 0, BUTTON_COUNT);
    }

    /** The build or order menu has the pad: the D-pad steps, B leaves, A on the order menu gives the order. */
    private void menuButtons(boolean[] tapped, boolean ordersMenu) {
        dpad(tapped, "pad_up", "pad_down", "pad_left", "pad_right");
        if (pressed(tapped, BTN_B)) mouse.act("pad_back");
        if (ordersMenu && pressed(tapped, BTN_A)) mouse.act("pad_select");
    }

    /** A building picked: X places it and keeps it (a Shift click), the D-pad turns it and spaces a row, B cancels. */
    private void pickedButtons(boolean[] tapped) {
        if (pressed(tapped, BTN_X)) {
            if (reticle) mouse.centre();
            if (!shift) mouse.key(KeyEvent.KEYCODE_SHIFT_LEFT, true);
            mouse.button(true, true);
            mouse.button(true, false);
            if (!shift) mouse.key(KeyEvent.KEYCODE_SHIFT_LEFT, false);
        }
        dpad(tapped, "spacing_up", "spacing_down", "rotate_left", "rotate_right");
        if (pressed(tapped, BTN_B)) mouse.act("cancel");
    }

    private void playButtons(boolean[] held, boolean[] tapped, boolean lb, boolean start, boolean back, boolean lt, long now) {
        if (start) {   // control groups
            if (pressed(tapped, BTN_DPAD_UP)) { groupSlot = groupSlot % 9 + 1; mouse.act("group_show_" + groupSlot); }
            if (pressed(tapped, BTN_DPAD_DOWN)) { groupSlot = (groupSlot + 7) % 9 + 1; mouse.act("group_show_" + groupSlot); }
            if (pressed(tapped, BTN_DPAD_RIGHT)) {   // BAR's autogroup: this type joins the group from now on (Alt+N)
                int key = KeyEvent.KEYCODE_1 + groupSlot - 1;
                if (!alt) mouse.key(KeyEvent.KEYCODE_ALT_LEFT, true);
                mouse.key(key, true);
                mouse.key(key, false);
                if (!alt) mouse.key(KeyEvent.KEYCODE_ALT_LEFT, false);
                mouse.act("group_auto_" + groupSlot);
            }
            if (pressed(tapped, BTN_LS)) mouse.act("group_clear_" + groupSlot);
        }
        // Start + D-pad left: a tap recalls the group, held it assigns the selection to it (also if Start lets go first)
        if (start && pressed(tapped, BTN_DPAD_LEFT)) { startLeftAt = now; startLeftDone = false; }
        if (startLeftAt >= 0) {
            if (!startLeftDone && held[BTN_DPAD_LEFT] && now - startLeftAt >= ASSIGN_HOLD_MS) {
                startLeftDone = true;
                mouse.act("group_assign_" + groupSlot);
            }
            if (released(held, tapped, BTN_DPAD_LEFT)) {
                if (!startLeftDone) mouse.act("group_recall_" + groupSlot);
                startLeftAt = -1;
            }
        }
        if (!start) {
            if (lb) dpad(tapped, null, "idle_type", "idle_mobile_prev", "idle_mobile_next");
            else dpad(tapped, lt ? "bookmark_store" : "bookmark_recall", "commander", "idle_prev", "idle_next");
        }
        if (pressed(tapped, BTN_B)) {
            if (lb) {   // stop; twice repeat; held wait
                lbBDownAt = now;
                lbBHeld = false;
                if (now - lbBTapAt <= LB_B_DOUBLE_MS) { mouse.act("lb_b2"); lbBTapAt = 0; }
                else { mouse.act("lb_b"); lbBTapAt = now; }
            } else {
                mouse.act("cancel");
            }
        }
        if (lbBDownAt >= 0) {
            if (!lbBHeld && held[BTN_B] && now - lbBDownAt >= LB_B_HOLD_MS) { lbBHeld = true; mouse.act("lb_b_hold"); }
            if (!held[BTN_B]) lbBDownAt = -1;
        }
        if (lb) {
            if (pressed(tapped, BTN_A)) mouse.act("lb_a");
            if (pressed(tapped, BTN_X)) mouse.act("lb_x");
            if (pressed(tapped, BTN_Y)) mouse.act("lb_y");
        }
        if (!start && !back) {
            if (pressed(tapped, BTN_LS)) mouse.act("queue_remove_first");
            if (pressed(tapped, BTN_RS)) mouse.act("queue_remove_last");
        }
    }

    /** The D-pad's four presses as actions (null: none); BTN_DPAD_UP, DOWN, LEFT, RIGHT follow each other (SDL order). */
    private void dpad(boolean[] tapped, String up, String down, String left, String right) {
        String[] acts = {up, down, left, right};
        for (int d = 0; d < 4; d++) if (acts[d] != null && pressed(tapped, BTN_DPAD_UP + d)) mouse.act(acts[d]);
    }

    private static boolean pressed(boolean[] tapped, int i) { return tapped[i]; }

    private boolean released(boolean[] held, boolean[] tapped, int i) { return !held[i] && (prev[i] || tapped[i]); }

    private static boolean anyFace(boolean[] tapped) {
        return tapped[BTN_A] || tapped[BTN_B] || tapped[BTN_X] || tapped[BTN_Y];
    }
}
