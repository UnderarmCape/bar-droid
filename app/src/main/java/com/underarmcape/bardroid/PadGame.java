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
 *   A held       nothing picked: v0.8.5's area select - a circle in the middle selects the units it passes over while
 *                the left stick pans (RT: added to the selection, buildings too; D-pad: the circle bigger or smaller,
 *                held: quickly; B: undone; X held: v0.8.5's filter radial, the left stick picks all mobile / combat /
 *                builders / air).
 *                With an order picked, held past HOLD_MS, the left stick moves the pointer instead (BAR counts a drag
 *                only when the pointer moves): an area circle, a row of buildings; let go: the order, the pointer glides
 *                back. A shorter press is a click when it is let go (Kailil, 2026-10-29: a press while the camera moved
 *                drew a tiny path)
 *   X            BAR's right click there (the smart action: move, attack, repair, reclaim, guard); held past HOLD_MS:
 *                the left stick draws a path
 *   B            cancel the order or building picked, else clear the selection
 *   RT held      Shift (queue)                    RB held  Space (put the order first; on the build menu Alt: a
 *                                                          factory queues it first)
 *   RB tap       the build menu (the D-pad steps through it, the pointer kept on it, A picks, X takes one off a
 *                factory's queue, RB / LB the next / previous page, B leaves)
 *   Back + RB    the order menu, the same way (A gives the order: targeted ones go back to the middle to aim; the
 *                pointer at 5/8 speed there)
 *   D-pad        right / left: next / previous idle builder; down: the commander; up: camera bookmark (LT + up: store)
 *   LB + D-pad   right / left: next / previous idle unit of the rest; down: every idle unit of the last one's type
 *   LB + A/X/Y   fight (attack the enemy there) / attack / patrol, at the middle; LB + B: stop (twice: repeat; held: wait)
 *                LB + A or Y held past HOLD_MS: draws a fight or patrol path with the left stick, until let go (LB may
 *                be let go; RB held at the end: Alt, the other fight)
 *   Start or Back + D-pad  control groups: up / down the slot, left tap selects the group, left held assigns every unit
 *                of the selection's types to it (and those to come), right tap the camera to it, right held clears it;
 *                Start + L3: clear the group
 *   L3 / R3      remove the next / the last queued order; Back + R3: D-gun; Back + R3 + L3 held: self-destruct
 *   Back + Start a free pointer on the left stick (any of BAR's windows), and back; free by itself before the start
 *   Back + Y     the path speed tuner (bardroid_padspeed.lua): how fast the pointer draws at each zoom
 *   LB + L3 held first person on the selected unit (bardroid_padfp.lua): the sticks go to the widget (left walks, right
 *                looks), RT fires, B or the same chord ends it; the squad's orders: A follow me, X stop, Y fight, RB
 *                patrol, D-pad up add, down clear; Back the camera tuner (D-pad up / down the setting, left / right
 *                less and more, A saves, B closes); nothing else while it lasts
 *   a building picked (v0.8.5's placement): A places it, X places it and keeps it, D-pad left/right turns it and
 *                up/down spaces a row, Back slows the pan, B puts it away; LB held: a grid ("GRID" shown; Shift+Alt:
 *                the engine lays a build drag out only with Shift held, so LB alone did not, Kailil 2026-10-29) - A
 *                starts it where the pointer is, the left stick draws it (LB may be let go), A places it and puts the
 *                building away (X: keeps it), B cancels; holding A the whole time works too. An area order picked
 *                (area mex, ...) works the same way: A, draw, A.
 *
 * Pump thread only, except {@link #otherInput}.
 */
final class PadGame {
    private static final long RB_TAP_MS = 220, ASSIGN_HOLD_MS = 350, LB_B_DOUBLE_MS = 350, LB_B_HOLD_MS = 500;
    private static final long STICKY_TAP_MS = 350, CANCEL_RELEASE_MS = 250, GLIDE_MS = 160, BACK_TAP_MS = 300;
    private static final long AREA_SELECT_MS = 250;   // A held this long with nothing picked: v0.8.5's area select
    private static final long HOLD_MS = 250;          // A (an order picked) or X held this long: the stick draws
    private static final long GRID_EXIT_MS = 150;     // a grid placed with A: the building put away this much later
    private static final long PATH_ARM_MS = 160;      // a path's order picked: this long later the game has it, its drag starts
    private static final long SELF_DESTRUCT_MS = 750; // Back + R3 + L3 held this long (v0.8.5's)
    private static final long FIRST_PERSON_MS = 300;  // LB + L3 held this long (Kailil, 2026-10-30)
    private static final long AREA_REPEAT_AFTER_MS = 250, AREA_REPEAT_MS = 60;   // the D-pad held on the area select
    private static final float FILTER_STICK = 0.25f;  // the filter radial: the left stick this far picks a side
    // (the order menu: half speed, then Kailil: "increase speed by a quarter now")
    private static final float FINE_AIM = 0.35f, ON_INTERFACE = 0.6f, ON_ORDERS = 0.5f * 1.25f;
    private static final float PLACING = 0.8f;        // a building's grid being drawn (Kailil, 2026-10-30: 20% less)

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
    private boolean areaCandidate, areaSelect;     // A down with nothing picked (a click, or held: the area select)
    private boolean aPending, xPending;            // A or X down, its button not yet pressed (a click, or held: a drag)
    private long xDownAt = -1, gridExitAt = -1;
    private boolean gridLatched;                   // a grid's drag started with LB: Shift+Alt held until it ends
    private boolean rtNow;                         // RT held this tick (a grid placed with RT keeps the building)
    private boolean filterOpen;                    // X in the area select: v0.8.5's filter radial
    private String filterSide;
    private long rbDownAt = -1, startLeftAt = -1, startRightAt = -1, lbBDownAt = -1, lbBTapAt = -1, backDownAt = -1;
    private boolean rbUsed, startLeftDone, startRightDone, lbBHeld, backUsed;
    private int groupSlot = 1;
    private int pathButton = -1;                   // LB + A (fight) or Y (patrol) down: a tap, or held a path
    private long pathDownAt = -1, pathArmAt = -1;
    private boolean pathDrawing;                   // the path's drag: until pathButton is let go
    private boolean drawFast;                      // the stick was moving as the drawing began: LT does not slow it
    private long areaRepeatAt = -1, selfDestructAt = -1, dgunAt = -1, fpDownAt = -1;
    private boolean selfDestructDone, fpDone, fpFiring;
    private float fracX, fracY;

    PadGame(PadMouse mouse) { this.mouse = mouse; }

    /**
     * Touch or a real mouse moved the pointer: the pad brings it back to the middle when it is used again, not before (a
     * pad lying connected but unused kept taking the pointer away from the finger or the mouse). Any thread.
     */
    void otherInput() { centreWanted = true; waitForPad = true; }

    /** The left stick pans the camera (the pointer in the middle) rather than moving the pointer. */
    boolean reticle() { return reticle && !drawing; }

    /** The left stick picks a side of the area select's filter radial: it does not pan meanwhile. */
    boolean stickTaken() { return filterOpen; }

    /** Lets go of every button and key the pad holds (a mode change, a pause). */
    void release() {
        if (leftDown) { leftDown = false; mouse.button(true, false); }
        if (rightDown) { rightDown = false; mouse.button(false, false); }
        if (shift) { shift = false; mouse.key(KeyEvent.KEYCODE_SHIFT_LEFT, false); }
        if (space) { space = false; mouse.key(KeyEvent.KEYCODE_SPACE, false); }
        if (alt) { alt = false; mouse.key(KeyEvent.KEYCODE_ALT_LEFT, false); }
        java.util.Arrays.fill(prev, false);
        rbDownAt = startLeftAt = startRightAt = lbBDownAt = lbBTapAt = backDownAt = aDownAt = cancelAt = glideAt = xDownAt
                = gridExitAt = pathDownAt = pathArmAt = areaRepeatAt = selfDestructAt = dgunAt = -1;
        pathButton = -1;
        if (areaSelect) mouse.act("area_off");
        sticky = drawing = areaCandidate = areaSelect = aPending = xPending = gridLatched = filterOpen = pathDrawing = false;
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
        boolean menu = !focus.equals("none"), ordersMenu = focus.equals("orders"), buildMenu = focus.equals("build");
        String armed = menu ? "none" : mouse.armed();   // the order or building picked: build, area, unitarea, other
        boolean picked = armed.equals("build");
        boolean free = mouseMode != mouse.pregame();   // (before the start the pointer is free, as in v0.8.5)
        boolean wasReticle = reticle;
        reticle = !menu && !free;
        if (reticle && !wasReticle) centreWanted = true;
        boolean back = held[BACK], start = held[START], lb = held[LB];
        rtNow = rt;
        if (gridExitAt >= 0 && now >= gridExitAt) { gridExitAt = -1; mouse.act("build_exit"); }

        // First person: LB + L3 held in or out of it; in it the sticks are the widget's (the camera line) and only B and RT
        // count here
        if (lb && pressed(tapped, LS)) { fpDownAt = now; fpDone = false; }
        if (fpDownAt >= 0) {
            if (!held[LS] || !lb) fpDownAt = -1;
            else if (!fpDone && now - fpDownAt >= FIRST_PERSON_MS) { fpDone = true; mouse.act("fp_toggle"); }
        }
        if (mouse.firstPerson()) {
            if (pressed(tapped, B)) mouse.act("fp_toggle");
            if (pressed(tapped, A)) mouse.act("fp_order_follow");
            if (pressed(tapped, X)) mouse.act("fp_order_stop");
            if (pressed(tapped, Y)) mouse.act("fp_order_fight");
            if (pressed(tapped, RB)) mouse.act("fp_order_patrol");
            if (pressed(tapped, DPAD_UP)) mouse.act("fp_order_add");
            if (pressed(tapped, DPAD_DOWN)) mouse.act("fp_order_clear");
            if (pressed(tapped, DPAD_LEFT)) mouse.act("fp_order_left");     // (the camera tuner's less and more)
            if (pressed(tapped, DPAD_RIGHT)) mouse.act("fp_order_right");
            if (pressed(tapped, BACK)) mouse.act("fp_order_tune");
            if (rt != fpFiring) { fpFiring = rt; mouse.act(rt ? "fp_fire_on" : "fp_fire_off"); }
            if (shift) { shift = false; mouse.key(KeyEvent.KEYCODE_SHIFT_LEFT, false); }
            System.arraycopy(held, 0, prev, 0, COUNT);
            return;
        }
        fpFiring = false;

        // Modifier keys: RT Shift; RB held past a tap Space (on the build menu Alt); LB with a building picked
        // Shift+Alt (a grid: the engine lays out a build drag only with Shift), held on while its drag lasts
        boolean gridKeys = (lb && picked) || gridLatched;
        boolean wantShift = rt || gridKeys;
        if (wantShift != shift) { shift = wantShift; mouse.key(KeyEvent.KEYCODE_SHIFT_LEFT, wantShift); }
        if (picked && pressed(tapped, LB)) mouse.act("grid_on");   // ("GRID" in v0.8.5's blue)
        if (!menu && !picked && (pressed(tapped, START) || pressed(tapped, BACK))) mouse.act("group_list_on");   // (while held)
        if ((released(held, tapped, START) && !back) || (released(held, tapped, BACK) && !start)) mouse.act("group_list_off");

        // Back chords: + RB the order menu, + Start the free pointer, + R3 the D-gun, + R3 + L3 held self-destruct; Back
        // alone while placing slows the pan (v0.8.5)
        if (pressed(tapped, BACK)) { backDownAt = now; backUsed = false; }
        if (back && pressed(tapped, RB)) { mouse.act("pad_orders"); rbDownAt = -1; rbUsed = true; backUsed = true; }
        if (back && pressed(tapped, Y)) { mouse.act("pad_speed"); backUsed = true; }   // (the path speed tuner)
        if ((back && pressed(tapped, START)) || (start && pressed(tapped, BACK))) {
            mouseMode = !mouseMode;
            backUsed = true;
            mouse.act("mouse_toggle");   // (bardroid_pad.lua keeps the same switch: its reticle and note)
        }
        // (the D-gun when R3 is let go: it may yet be the self-destruct chord)
        if (back && pressed(tapped, RS)) { dgunAt = now; backUsed = true; }
        if (dgunAt >= 0 && released(held, tapped, RS)) { if (selfDestructAt < 0) mouse.act("dgun"); dgunAt = -1; }
        if (back && held[RS] && held[LS]) {
            if (selfDestructAt < 0) { selfDestructAt = now; selfDestructDone = false; backUsed = true; }
            if (!selfDestructDone && now - selfDestructAt >= SELF_DESTRUCT_MS) { selfDestructDone = true; mouse.act("selfd"); }
        } else if (!held[RS] && !held[LS]) {
            selfDestructAt = -1;
        }
        if (released(held, tapped, BACK)) {
            if (picked && !backUsed && now - backDownAt <= BACK_TAP_MS) mouse.act("slow_pan");
            backDownAt = -1;
        }

        // RB: a quick tap the build menu (on it: its next page); held past the tap (or with another button) a modifier
        if (!back && pressed(tapped, RB)) { rbDownAt = now; rbUsed = false; }
        if (held[RB] && rbDownAt >= 0 && !rbUsed && (now - rbDownAt > RB_TAP_MS || anyFace(tapped) || pathDrawing)) rbUsed = true;
        boolean rbHeld = held[RB] && rbUsed && rbDownAt >= 0;
        boolean wantSpace = rbHeld && !buildMenu && !pathDrawing;
        if (wantSpace != space) { space = wantSpace; mouse.key(KeyEvent.KEYCODE_SPACE, wantSpace); }
        boolean wantAlt = gridKeys || (rbHeld && (buildMenu || pathDrawing));   // (a path: the other fight)
        if (wantAlt != alt) { alt = wantAlt; mouse.key(KeyEvent.KEYCODE_ALT_LEFT, wantAlt); }
        if (released(held, tapped, RB)) {
            if (rbDownAt >= 0 && !rbUsed) mouse.act(buildMenu ? "pad_page_next" : "pad_build");
            rbDownAt = -1;
        }
        if (buildMenu && pressed(tapped, LB)) mouse.act("pad_page_prev");   // (Kailil: "pressing RB or LB cycles the tabs")

        boolean bTaken = buttons(held, tapped, now, menu, ordersMenu, picked, armed, lb, lx, ly);
        paths(held, now);

        // The pointer: drawing (a mouse button held in the middle's place) the left stick moves it; else in the middle,
        // gliding back to it; free (a menu, Back+Start, before the start) the left stick moves it
        boolean wasDrawing = drawing;
        drawing = reticle && ((leftDown && !areaCandidate) || rightDown);
        if (drawing && !wasDrawing) {
            glideAt = -1;
            px = mouse.width() / 2f; py = mouse.height() / 2f;
            drawFast = lx != 0 || ly != 0;
        }
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
            // Drawing: the speed for the zoom (Kailil, 2026-10-30: "Zoom distance determines the speed"; the launcher's
            // tuner, /padspeed); LT slows it only from a standstill ("seamless" when the stick was already panning)
            if (drawing) factor = mouse.drawSpeed() * (picked ? PLACING : 1f);
            boolean fine = lt && !(drawing && drawFast);
            float step = mouse.pixelsPerSecond() * dt * (fine ? FINE_AIM : 1f) * factor;
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
        } else if (picked) {
            dpad(tapped, "spacing_up", "spacing_down", "rotate_left", "rotate_right");
        } else if (areaSelect) {   // (v0.8.5: the D-pad sizes the circle; Kailil, 2026-10-30: held, quickly)
            areaDpad(held, tapped, now);
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
                            String armed, boolean lb, float lx, float ly) {
        boolean stickyKind = !menu && ((picked && lb) || armed.equals("area"));
        // v0.8.5's area select (Kailil: "when holding A to select units ... is it not possible to do the 0.8.5 method"):
        // nothing picked, A held past a tap - the click is let go and bardroid_pad.lua's circle selects; B undoes it;
        // X held as well opens v0.8.5's filter radial (Kailil, 2026-10-29): the left stick picks a side (up all mobile,
        // down combat, left builders, right air), let go of X: that filter
        if (areaSelect) {
            if (pressed(tapped, X) && !filterOpen) { filterOpen = true; filterSide = null; mouse.act("area_filter_open"); }
            if (filterOpen) {
                if (held[X]) {
                    String side = Math.hypot(lx, ly) < FILTER_STICK ? null
                            : Math.abs(ly) > Math.abs(lx) ? (ly < 0 ? "up" : "down") : (lx < 0 ? "left" : "right");
                    if (side != null && !side.equals(filterSide)) { filterSide = side; mouse.act("area_filter_" + side); }
                } else {
                    filterOpen = false;
                    mouse.act("area_filter_pick");
                }
            }
            if (pressed(tapped, B)) { closeFilter(); areaSelect = false; mouse.act("area_cancel"); return true; }
            if (!held[A]) { closeFilter(); areaSelect = false; mouse.act("area_off"); }
            return false;
        }
        if (areaCandidate && leftDown && held[A] && now - aDownAt >= AREA_SELECT_MS) {
            areaCandidate = false;
            leftUp(true);
            areaSelect = true;
            mouse.act("area_on");
            return false;
        }
        if (sticky) {
            if (cancelAt >= 0) {   // B: the order or building put away first, then the button let go
                if (now - cancelAt >= CANCEL_RELEASE_MS) { sticky = false; cancelAt = -1; leftUp(true); }
                return pressed(tapped, B);
            }
            if (pressed(tapped, A)) { sticky = false; leftUp(false); return false; }
            if (pressed(tapped, X)) {   // confirm and keep the building picked
                sticky = false;
                if (!shift) mouse.key(KeyEvent.KEYCODE_SHIFT_LEFT, true);
                leftUp(true);
                if (!shift) mouse.key(KeyEvent.KEYCODE_SHIFT_LEFT, false);
                return false;
            }
            if (pressed(tapped, B)) { mouse.act("cancel"); cancelAt = now; return true; }
            return false;
        }
        // A with an order or building picked: the button goes down only when A is let go (a click, or a sticky drag's
        // start) or once held past HOLD_MS (a drag: the stick draws), so a press while the camera moves stays a click
        boolean aClicks = !ordersMenu && !(lb && !menu && !picked);
        if (aClicks && pressed(tapped, A) && !leftDown && !aPending) {
            if (reticle && !drawing) centreNow();
            aDownAt = now;
            areaCandidate = reticle && !menu && !lb && armed.equals("none");
            if (reticle && !menu && !armed.equals("none")) aPending = true;
            else leftPress(lb && picked);
        }
        if (aPending && (!held[A] || now - aDownAt >= HOLD_MS)) {
            aPending = false;
            if (reticle) centreNow();
            leftPress(lb && picked);
        }
        if (leftDown && !held[A] && pathButton < 0) {
            areaCandidate = false;
            if (stickyKind && aDownAt >= 0 && now - aDownAt < STICKY_TAP_MS) sticky = true;   // a tap: the drag goes on
            else leftUp(false);
        }
        // X: the same, a click unless held past HOLD_MS (then a path)
        boolean xRight = (!menu && !picked && !lb) || (menu && !ordersMenu);
        if (xRight && pressed(tapped, X) && !rightDown && !xPending) {
            if (reticle && !drawing) centreNow();
            if (reticle && !menu) {
                xPending = true;
                xDownAt = now;
            } else {
                rightDown = true;
                mouse.button(false, true);
            }
        }
        if (xPending && !held[X]) {   // a short press: a right click
            xPending = false;
            if (reticle) centreNow();
            mouse.button(false, true);
            mouse.button(false, false);
        } else if (xPending && now - xDownAt >= HOLD_MS) {
            xPending = false;
            if (reticle) centreNow();
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

    /**
     * LB + A or Y (Kailil, 2026-10-30: "draw Patrol paths, and fight paths, just like i can draw Move paths"): a tap
     * gives the order at the middle; held past HOLD_MS the order is picked and, once the game has it, the left button
     * goes down: the left stick draws, and BAR's formation widget gives the path when the button is let go.
     */
    private void paths(boolean[] held, long now) {
        if (pathButton < 0) return;
        if (pathDrawing) {
            if (!held[pathButton]) { pathDrawing = false; pathButton = -1; leftUp(true); }
        } else if (pathArmAt >= 0) {
            if (!held[pathButton]) {
                mouse.act("cancel");
                pathArmAt = -1; pathButton = -1;
            } else if (now >= pathArmAt) {
                pathArmAt = -1;
                if (mouse.armed().equals("none")) { pathButton = -1; return; }   // (nothing that can take the order selected)
                if (reticle) centreNow();
                pathDrawing = true;
                leftPress(false);
            }
        } else if (!held[pathButton]) {
            mouse.act(pathButton == A ? "lb_a" : "lb_y");
            pathButton = -1;
        } else if (now - pathDownAt >= HOLD_MS) {
            mouse.act(pathButton == A ? "path_fight" : "path_patrol");
            pathArmAt = now + PATH_ARM_MS;
        }
    }

    /** The D-pad on the area select: each press a step, held quickly. */
    private void areaDpad(boolean[] held, boolean[] tapped, long now) {
        boolean bigger = held[DPAD_UP] || held[DPAD_RIGHT], smaller = held[DPAD_DOWN] || held[DPAD_LEFT];
        if (pressed(tapped, DPAD_UP) || pressed(tapped, DPAD_RIGHT)) {
            mouse.act("area_bigger");
            areaRepeatAt = now + AREA_REPEAT_AFTER_MS;
        } else if (pressed(tapped, DPAD_DOWN) || pressed(tapped, DPAD_LEFT)) {
            mouse.act("area_smaller");
            areaRepeatAt = now + AREA_REPEAT_AFTER_MS;
        } else if (!bigger && !smaller) {
            areaRepeatAt = -1;
        } else if (areaRepeatAt >= 0 && now >= areaRepeatAt) {
            mouse.act(bigger ? "area_bigger" : "area_smaller");
            areaRepeatAt = now + AREA_REPEAT_MS;
        }
    }

    /** The left button down; grid: a grid's drag (Shift+Alt stay held until it ends). */
    private void leftPress(boolean grid) {
        leftDown = true;
        if (grid) gridLatched = true;
        mouse.button(true, true);
    }

    /** keepBuilding: a grid placed keeps the building picked (X, RT, a cancel); else it is put away just after. */
    private void leftUp(boolean keepBuilding) {
        if (leftDown) { leftDown = false; mouse.button(true, false); }
        aDownAt = -1;
        if (gridLatched) {
            gridLatched = false;
            if (!keepBuilding && !rtNow) gridExitAt = SystemClock.uptimeMillis() + GRID_EXIT_MS;
        }
    }

    private void closeFilter() {
        if (filterOpen) { filterOpen = false; mouse.act("area_filter_close"); }
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
        boolean groups = start || back;   // (Kailil, 2026-10-30: Back; v0.8.5's Start stays)
        if (groups) {   // control groups
            if (pressed(tapped, DPAD_UP)) { groupSlot = groupSlot % 9 + 1; mouse.act("group_show_" + groupSlot); }
            if (pressed(tapped, DPAD_DOWN)) { groupSlot = (groupSlot + 7) % 9 + 1; mouse.act("group_show_" + groupSlot); }
            if (start && pressed(tapped, LS)) mouse.act("group_clear_" + groupSlot);
        }
        // + D-pad left: a tap selects the group, held every unit of the selection's types joins it, those to come too.
        // + D-pad right: a tap the camera to the group, held the group cleared. Also if Start or Back lets go first.
        // (All BAR's own group commands and autogroup: bardroid_pad.lua.)
        if (groups && pressed(tapped, DPAD_LEFT)) { startLeftAt = now; startLeftDone = false; }
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
        if (groups && pressed(tapped, DPAD_RIGHT)) { startRightAt = now; startRightDone = false; }
        if (startRightAt >= 0) {
            if (!startRightDone && held[DPAD_RIGHT] && now - startRightAt >= ASSIGN_HOLD_MS) {
                startRightDone = true;
                mouse.act("group_clear_" + groupSlot);
            }
            if (released(held, tapped, DPAD_RIGHT)) {
                if (!startRightDone) mouse.act("group_look_" + groupSlot);
                startRightAt = -1;
            }
        }
        if (!groups) {
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
            if (pathButton < 0 && (pressed(tapped, A) || pressed(tapped, Y))) {   // (a tap or a path: paths())
                pathButton = pressed(tapped, A) ? A : Y;
                pathDownAt = now;
            }
            if (pressed(tapped, X)) mouse.act("lb_x");
        }
        if (!start && !back) {
            if (pressed(tapped, LS) && !lb) mouse.act("queue_remove_first");   // (LB + L3: first person)
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
