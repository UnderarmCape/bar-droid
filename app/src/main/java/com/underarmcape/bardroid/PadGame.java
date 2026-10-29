package com.underarmcape.bardroid;

import android.os.SystemClock;
import android.view.KeyEvent;

import static com.underarmcape.bardroid.PadButtons.A;
import static com.underarmcape.bardroid.PadButtons.B;
import static com.underarmcape.bardroid.PadButtons.BACK;
import static com.underarmcape.bardroid.PadButtons.DPAD_DOWN;
import static com.underarmcape.bardroid.PadButtons.DPAD_LEFT;
import static com.underarmcape.bardroid.PadButtons.DPAD_RIGHT;
import static com.underarmcape.bardroid.PadButtons.DPAD_UP;
import static com.underarmcape.bardroid.PadButtons.LB;
import static com.underarmcape.bardroid.PadButtons.LS;
import static com.underarmcape.bardroid.PadButtons.RB;
import static com.underarmcape.bardroid.PadButtons.RS;
import static com.underarmcape.bardroid.PadButtons.START;
import static com.underarmcape.bardroid.PadButtons.X;
import static com.underarmcape.bardroid.PadButtons.Y;
import static com.underarmcape.bardroid.PadButtons.COUNT;

/**
 * The gamepad in BAR's own game (online, spectating): Kailil's BAR Controller Support v0.8.5 ("Build-First Commander")
 * rebuilt on a mouse and keyboard, which BAR's sandbox cannot see or block (Kailil, 2026-10-29: "match 1to1 using any
 * means necessary ... dont worry about radials ... I want mouse to be locked to the center of the screen like it is in
 * 8.5"). Game-side work goes to bardroid_pad.lua and bardroid_buildmenu.lua as actions ("act" lines):
 *
 *   pointer      in the middle of the screen (v0.8.5's reticle) while the pad is the input; whenever it has been
 *                elsewhere it glides back (Kailil: "make sure that snap back is smooth and not jerky")
 *   left stick   pans the map under it (LT held: faster); right stick turns (x) and zooms (y), LB + right stick tilts
 *   A            left click there: select (twice: that type on screen), place a building
 *   X            BAR's right click there (the smart action: move, attack, repair, reclaim, guard)
 *   A or X held  the left stick moves the pointer instead (BAR counts a drag only when the pointer moves): box select,
 *                a path (X), an area circle, a row of buildings; let go: the order, and the pointer glides back
 *   B            cancel the order or building picked, else clear the selection
 *   RT held      Shift (queue)                    RB held  Space (put the order first; on the build menu Alt: a
 *                                                          factory queues it first)
 *   RB tap       the build menu (the D-pad steps through it, the pointer kept on it, A picks, X takes one off a
 *                factory's queue, B leaves; in the controller game v0.8.5's own build menu, through its controller
 *                calls: "buildapi")
 *   Back + RB    the order menu, the same way (A gives the order: targeted ones go back to the middle to aim; the
 *                pointer at half speed there)
 *   D-pad        right / left: next / previous idle builder; down: the commander; up: camera bookmark (LT + up: store)
 *   LB + D-pad   right / left: next / previous idle unit of the rest; down: every idle unit of the last one's type
 *   LB + A/X/Y   fight (attack the enemy there) / attack / patrol, at the middle; LB + B: stop (twice: repeat; held: wait)
 *   Start + D-pad  control groups: up / down the slot, left tap recall (held: assign), right: same type from now on;
 *                Start + L3: clear the group
 *   L3 / R3      remove the next / the last queued order; Back + R3: D-gun
 *   Back + Start a free pointer on the left stick (any of BAR's windows), and back; free by itself before the start
 *   a building picked (v0.8.5's placement): A places it, X places it and keeps it, D-pad left/right turns it and
 *                up/down spaces a row, Back slows the pan, B puts it away; LB held: a grid (Alt) - A starts it where
 *                the pointer is, the left stick draws it, A places it (X: and keeps the building), B cancels; holding
 *                A the whole time works too. An area order picked (area mex, ...) works the same way: A, draw, A.
 *
 * Pump thread only, except {@link #otherInput}.
 */
final class PadGame {
    private static final long RB_TAP_MS = 220, ASSIGN_HOLD_MS = 350, LB_B_DOUBLE_MS = 350, LB_B_HOLD_MS = 500;
    private static final long STICKY_TAP_MS = 350, CANCEL_RELEASE_MS = 250, GLIDE_MS = 160, BACK_TAP_MS = 300;
    private static final float FINE_AIM = 0.35f, ON_INTERFACE = 0.6f, ON_ORDERS = 0.5f;

    private final PadMouse mouse;
    private final boolean[] prev = new boolean[COUNT];
    private boolean leftDown, rightDown, shift, space, alt;
    private boolean mouseMode;                     // Back+Start: a free pointer
    private volatile boolean centreWanted = true;  // the pointer must go (back) to the middle
    private volatile boolean waitForPad = true;    // ... once the pad is used again (touch or a mouse has the pointer)
    private boolean reticle, drawing;
    private float px, py;                          // the pointer while drawing (X screen pixels)
    private long glideAt = -1;                     // a glide back to the middle: since when, from where
    private float gx, gy;
    private long aDownAt = -1, cancelAt = -1;      // A's press; a cancelled drag lets go of the button then
    private boolean sticky;                        // a drag started by a tap of A, ended by the next press
    private long rbDownAt = -1, startLeftAt = -1, lbBDownAt = -1, lbBTapAt = -1, backDownAt = -1;
    private boolean rbUsed, startLeftDone, lbBHeld, backUsed;
    private int groupSlot = 1;
    private float fracX, fracY;

    PadGame(PadMouse mouse) { this.mouse = mouse; }

    /**
     * Touch or a real mouse moved the pointer: the pad brings it back to the middle when it is used again, not before (a
     * pad lying connected but unused kept taking the pointer away from the finger or the mouse). Any thread.
     */
    void otherInput() { centreWanted = true; waitForPad = true; }

    /** The left stick pans the camera (the pointer in the middle) rather than moving the pointer. */
    boolean reticle() { return reticle && !drawing; }

    /** Lets go of every button and key the pad holds (a mode change, a pause). */
    void release() {
        if (leftDown) { leftDown = false; mouse.button(true, false); }
        if (rightDown) { rightDown = false; mouse.button(false, false); }
        if (shift) { shift = false; mouse.key(KeyEvent.KEYCODE_SHIFT_LEFT, false); }
        if (space) { space = false; mouse.key(KeyEvent.KEYCODE_SPACE, false); }
        if (alt) { alt = false; mouse.key(KeyEvent.KEYCODE_ALT_LEFT, false); }
        java.util.Arrays.fill(prev, false);
        rbDownAt = startLeftAt = lbBDownAt = lbBTapAt = backDownAt = aDownAt = cancelAt = glideAt = -1;
        sticky = drawing = false;
        centreWanted = waitForPad = true;
    }

    /**
     * One pump tick. held: the buttons down now; tapped: pressed since the last tick (even if already up again);
     * lx, ly: the left stick (-1..1 past the deadzone); lt, rt: the triggers held; active: the pad is in use (a button,
     * a stick or a trigger, the right stick too).
     */
    void tick(boolean[] held, boolean[] tapped, float lx, float ly, boolean lt, boolean rt, boolean active, float dt) {
        long now = SystemClock.uptimeMillis();
        if (active) waitForPad = false;
        else if (waitForPad) glideAt = -1;   // (touch or a mouse has the pointer: no glide pulls it away)
        String focus = mouse.padFocus();
        // (the order menu, and in the controller game v0.8.5's build menu, take A and X as actions: "buildapi")
        boolean menu = !focus.equals("none"), ordersMenu = focus.equals("orders") || focus.equals("buildapi");
        String armed = menu ? "none" : mouse.armed();   // the order or building picked: build, area, unitarea, other
        boolean picked = armed.equals("build");
        boolean free = mouseMode != mouse.pregame();   // (before the start the pointer is free, as in v0.8.5)
        boolean wasReticle = reticle;
        reticle = !menu && !free;
        if (reticle && !wasReticle) centreWanted = true;
        boolean back = held[BACK], start = held[START], lb = held[LB];

        // Modifier keys: RT Shift; RB held past a tap Space (on the build menu Alt); LB with a building picked Alt
        if (rt != shift) { shift = rt; mouse.key(KeyEvent.KEYCODE_SHIFT_LEFT, rt); }

        // Back chords: + RB the order menu, + Start the free pointer, + R3 the D-gun; Back alone while placing slows
        // the pan (v0.8.5)
        if (pressed(tapped, BACK)) { backDownAt = now; backUsed = false; }
        if (back && pressed(tapped, RB)) { mouse.act("pad_orders"); rbDownAt = -1; rbUsed = true; backUsed = true; }
        if ((back && pressed(tapped, START)) || (start && pressed(tapped, BACK))) {
            mouseMode = !mouseMode;
            backUsed = true;
            mouse.act("mouse_toggle");   // (bardroid_pad.lua keeps the same switch: its reticle and note)
        }
        if (back && pressed(tapped, RS)) { mouse.act("dgun"); backUsed = true; }
        if (released(held, tapped, BACK)) {
            if (picked && !backUsed && now - backDownAt <= BACK_TAP_MS) mouse.act("slow_pan");
            backDownAt = -1;
        }

        // RB: a quick tap the build menu; held past the tap (or with another button) a modifier
        if (!back && pressed(tapped, RB)) { rbDownAt = now; rbUsed = false; }
        if (held[RB] && rbDownAt >= 0 && !rbUsed && (now - rbDownAt > RB_TAP_MS || anyFace(tapped))) rbUsed = true;
        boolean rbHeld = held[RB] && rbUsed && rbDownAt >= 0;
        boolean buildMenu = focus.equals("build") || focus.equals("buildapi");
        boolean wantSpace = rbHeld && !buildMenu;
        if (wantSpace != space) { space = wantSpace; mouse.key(KeyEvent.KEYCODE_SPACE, wantSpace); }
        boolean wantAlt = (lb && picked) || (rbHeld && buildMenu);
        if (wantAlt != alt) { alt = wantAlt; mouse.key(KeyEvent.KEYCODE_ALT_LEFT, wantAlt); }
        if (released(held, tapped, RB)) {
            if (rbDownAt >= 0 && !rbUsed) mouse.act("pad_build");
            rbDownAt = -1;
        }

        boolean bTaken = buttons(held, tapped, now, menu, ordersMenu, picked, armed, lb);

        // The pointer: drawing (a mouse button held in the middle's place) the left stick moves it; else in the middle,
        // gliding back to it; free (a menu, Back+Start, before the start) the left stick moves it
        boolean wasDrawing = drawing;
        drawing = reticle && (leftDown || rightDown);
        if (drawing && !wasDrawing) { glideAt = -1; px = mouse.width() / 2f; py = mouse.height() / 2f; }
        if (!drawing && wasDrawing && reticle) glideFrom(px, py, now);
        if (reticle && !drawing) {
            if (centreWanted && !waitForPad) {
                centreWanted = false;
                float[] at = mouse.pointer();
                if (at != null) glideFrom(at[0], at[1], now); else mouse.centre();
            }
            glide(now);
        } else if (lx != 0 || ly != 0) {
            float factor = focus.equals("orders") ? ON_ORDERS : (!drawing && mouse.onInterface() ? ON_INTERFACE : 1f);
            float step = mouse.pixelsPerSecond() * dt * (lt ? FINE_AIM : 1f) * factor;
            fracX += lx * step; fracY += ly * step;
            int ix = (int) fracX, iy = (int) fracY;
            fracX -= ix; fracY -= iy;
            if (drawing) {   // (kept on the screen: the glide back starts where the pointer really is)
                float nx = Math.max(0, Math.min(mouse.width() - 1, px + ix)), ny = Math.max(0, Math.min(mouse.height() - 1, py + iy));
                ix = Math.round(nx - px); iy = Math.round(ny - py);
                px += ix; py += iy;
            }
            if (ix != 0 || iy != 0) mouse.move(ix, iy);
        } else {
            fracX = fracY = 0;
        }

        if (menu) {
            dpad(tapped, "pad_up", "pad_down", "pad_left", "pad_right");
            if (pressed(tapped, B)) mouse.act("pad_back");
            if (ordersMenu && pressed(tapped, A)) mouse.act("pad_select");
            if (focus.equals("buildapi") && pressed(tapped, X)) mouse.act("pad_x");   // (one off a factory's queue)
        } else if (picked) {
            dpad(tapped, "spacing_up", "spacing_down", "rotate_left", "rotate_right");
        } else {
            playButtons(held, tapped, lb, start, back, lt, now, bTaken);
        }
        System.arraycopy(held, 0, prev, 0, COUNT);
    }

    /**
     * A and X as mouse buttons. A: the left button (not on the order menu, which takes A as an action; not with LB in
     * play, the order shortcuts). A tap with a grid (LB) or an area order picked starts a drag the next press ends (X:
     * placing and keeping the building; B cancels it). X: the right button in play and on the build menu (one off a
     * factory's queue); with a building picked a Shift click (place it and keep it). B: cancel. True: B was taken here.
     */
    private boolean buttons(boolean[] held, boolean[] tapped, long now, boolean menu, boolean ordersMenu, boolean picked,
                            String armed, boolean lb) {
        boolean stickyKind = !menu && ((picked && lb) || armed.equals("area"));
        if (sticky) {
            if (cancelAt >= 0) {   // B: the order or building put away first, then the button let go
                if (now - cancelAt >= CANCEL_RELEASE_MS) { sticky = false; cancelAt = -1; leftUp(); }
                return pressed(tapped, B);
            }
            if (pressed(tapped, A)) { sticky = false; leftUp(); return false; }
            if (pressed(tapped, X)) {   // confirm and keep the building picked
                sticky = false;
                if (!shift) mouse.key(KeyEvent.KEYCODE_SHIFT_LEFT, true);
                leftUp();
                if (!shift) mouse.key(KeyEvent.KEYCODE_SHIFT_LEFT, false);
                return false;
            }
            if (pressed(tapped, B)) { mouse.act("cancel"); cancelAt = now; return true; }
            return false;
        }
        boolean aClicks = !ordersMenu && !(lb && !menu && !picked);
        if (aClicks && pressed(tapped, A) && !leftDown) {
            if (reticle && !drawing) centreNow();
            aDownAt = now;
            leftDown = true;
            mouse.button(true, true);
        }
        if (leftDown && !held[A]) {
            if (stickyKind && aDownAt >= 0 && now - aDownAt < STICKY_TAP_MS) sticky = true;   // a tap: the drag goes on
            else leftUp();
        }
        boolean xRight = (!menu && !picked && !lb) || (menu && !ordersMenu);
        if (xRight && pressed(tapped, X) && !rightDown) {
            if (reticle && !drawing) centreNow();
            rightDown = true;
            mouse.button(false, true);
        }
        if (rightDown && !held[X]) { rightDown = false; mouse.button(false, false); }
        if (picked && pressed(tapped, X) && !leftDown) {   // place it here and keep it picked
            if (reticle) centreNow();
            if (!shift) mouse.key(KeyEvent.KEYCODE_SHIFT_LEFT, true);
            mouse.button(true, true);
            mouse.button(true, false);
            if (!shift) mouse.key(KeyEvent.KEYCODE_SHIFT_LEFT, false);
        }
        if (!menu && picked && pressed(tapped, B)) { mouse.act("cancel"); return true; }
        return false;
    }

    private void leftUp() {
        if (leftDown) { leftDown = false; mouse.button(true, false); }
        aDownAt = -1;
    }

    /** The pointer straight to the middle (before a click there): a glide still under way ends. */
    private void centreNow() {
        glideAt = -1;
        centreWanted = false;
        mouse.centre();
    }

    private void glideFrom(float x, float y, long now) { gx = x; gy = y; glideAt = now; }

    /** One step of the glide back to the middle (ease-out over GLIDE_MS). */
    private void glide(long now) {
        if (glideAt < 0) return;
        float t = Math.min(1f, (now - glideAt) / (float) GLIDE_MS), e = 1 - (1 - t) * (1 - t) * (1 - t);
        float cx = mouse.width() / 2f, cy = mouse.height() / 2f;
        mouse.moveTo(gx + (cx - gx) * e, gy + (cy - gy) * e);
        if (t >= 1) glideAt = -1;
    }

    private void playButtons(boolean[] held, boolean[] tapped, boolean lb, boolean start, boolean back, boolean lt, long now,
                             boolean bTaken) {
        if (start) {   // control groups
            if (pressed(tapped, DPAD_UP)) { groupSlot = groupSlot % 9 + 1; mouse.act("group_show_" + groupSlot); }
            if (pressed(tapped, DPAD_DOWN)) { groupSlot = (groupSlot + 7) % 9 + 1; mouse.act("group_show_" + groupSlot); }
            if (pressed(tapped, DPAD_RIGHT)) {   // BAR's autogroup: this type joins the group from now on (Alt+N)
                int key = KeyEvent.KEYCODE_1 + groupSlot - 1;
                if (!alt) mouse.key(KeyEvent.KEYCODE_ALT_LEFT, true);
                mouse.key(key, true);
                mouse.key(key, false);
                if (!alt) mouse.key(KeyEvent.KEYCODE_ALT_LEFT, false);
                mouse.act("group_auto_" + groupSlot);
            }
            if (pressed(tapped, LS)) mouse.act("group_clear_" + groupSlot);
        }
        // Start + D-pad left: a tap recalls the group, held it assigns the selection to it (also if Start lets go first)
        if (start && pressed(tapped, DPAD_LEFT)) { startLeftAt = now; startLeftDone = false; }
        if (startLeftAt >= 0) {
            if (!startLeftDone && held[DPAD_LEFT] && now - startLeftAt >= ASSIGN_HOLD_MS) {
                startLeftDone = true;
                mouse.act("group_assign_" + groupSlot);
            }
            if (released(held, tapped, DPAD_LEFT)) {
                if (!startLeftDone) mouse.act("group_recall_" + groupSlot);
                startLeftAt = -1;
            }
        }
        if (!start) {
            if (lb) dpad(tapped, null, "idle_type", "idle_mobile_prev", "idle_mobile_next");
            else dpad(tapped, lt ? "bookmark_store" : "bookmark_recall", "commander", "idle_prev", "idle_next");
        }
        // B: cancel; with LB stop, twice repeat, held wait - decided once it is clear which (Kailil: double tap and
        // hold "triggers stop first")
        if (pressed(tapped, B) && !bTaken) {
            if (lb) {
                if (lbBTapAt >= 0) { mouse.act("lb_b2"); lbBTapAt = -1; lbBDownAt = -1; }
                else { lbBDownAt = now; lbBHeld = false; }
            } else {
                mouse.act("cancel");
            }
        }
        if (lbBDownAt >= 0) {
            if (!lbBHeld && held[B] && now - lbBDownAt >= LB_B_HOLD_MS) {
                lbBHeld = true;
                lbBDownAt = -1;
                mouse.act("lb_b_hold");
            } else if (!held[B]) {   // let go: a stop unless a second tap follows
                lbBTapAt = now;
                lbBDownAt = -1;
            }
        }
        if (lbBTapAt >= 0 && now - lbBTapAt > LB_B_DOUBLE_MS) { mouse.act("lb_b"); lbBTapAt = -1; }
        if (lb) {
            if (pressed(tapped, A)) mouse.act("lb_a");
            if (pressed(tapped, X)) mouse.act("lb_x");
            if (pressed(tapped, Y)) mouse.act("lb_y");
        }
        if (!start && !back) {
            if (pressed(tapped, LS)) mouse.act("queue_remove_first");
            if (pressed(tapped, RS)) mouse.act("queue_remove_last");
        }
    }

    /** The D-pad's four presses as actions (null: none); DPAD_UP, DOWN, LEFT, RIGHT follow each other (SDL order). */
    private void dpad(boolean[] tapped, String up, String down, String left, String right) {
        String[] acts = {up, down, left, right};
        for (int d = 0; d < 4; d++) if (acts[d] != null && pressed(tapped, DPAD_UP + d)) mouse.act(acts[d]);
    }

    private static boolean pressed(boolean[] tapped, int i) { return tapped[i]; }

    private boolean released(boolean[] held, boolean[] tapped, int i) { return !held[i] && (prev[i] || tapped[i]); }

    private static boolean anyFace(boolean[] tapped) {
        return tapped[A] || tapped[B] || tapped[X] || tapped[Y];
    }
}
