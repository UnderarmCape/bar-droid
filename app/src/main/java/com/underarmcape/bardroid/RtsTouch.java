package com.underarmcape.bardroid;

import android.graphics.Rect;
import android.graphics.RectF;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.os.SystemClock;
import android.util.SparseArray;
import android.view.HapticFeedbackConstants;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.VelocityTracker;
import android.view.ViewConfiguration;

import com.termux.x11.LorieView;
import com.termux.x11.MainActivity;
import com.termux.x11.input.InputStub;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

/**
 * Finger gestures on the game screen, made for an RTS. Termux:X11's touch modes are for desktops (a pinch magnifies
 * the Android view and nothing pans the map), so fingers are handled here and everything else (mouse, stylus,
 * touchpad, keyboard) stays with Termux:X11:
 *
 *   tap                  left click (select, buttons, place a building); a quick second tap is a double click (BAR:
 *                        the unit's type on screen); a quick third tap selects that type on the whole map
 *   drag                 pan: the map follows the finger, and keeps gliding after a flick. A drag that starts on the
 *                        game's interface (minimap, sliders, windows) is a left drag instead
 *   tap, then drag       left drag: box select
 *   long press           right button: lift = right click (move/attack order), keep dragging = right drag (formation)
 *   two-finger tap       right click at the first finger
 *   two fingers          move = pan, pinch = zoom about the pinch (in the lobby: the mouse wheel, which scrolls),
 *                        twist = rotate the camera
 *   two fingers up/down  tilt the camera (both fingers moving up or down together, however they sit)
 *   two fingers held     (half a second, a buzz) then swiped: up = select all own units, down = deselect, left = stop,
 *                        right = fight (attack-move: the next tap places it)
 *   three-finger tap     show / hide the keyboard
 *   three-finger swipe   up = overview of the whole map, down = the camera to the commander, selected (dead: the
 *                        constructor selected last; out of the overview too); left / right = previous / next idle builder
 *   three fingers held   (most of a second, a buzz) the layout editor opens or closes (bardroid_layout.lua)
 * Actions go to the widget as "act <name>" lines (not in the lobby).
 * A building picked in the app's build menu (bardroid_buildmenu.lua: its page strip then shows ONE, LINE, GRID and
 * BORDER, and a big green PLACE button with rotate and cancel lies over the order menu; Kailil, 2026-10-28): a tap on
 * the map picks the spot (the building shows there), a tap on PLACE builds it there and the building stays picked
 * (Shift held for the click); with LINE, GRID or BORDER a drag on the map lays out BAR's own line, filled area or
 * hollow ring of them at once (the engine's build drag with Shift, Shift+Alt or Shift+Alt+Ctrl held).
 * With ONE (Kailil, 2026-10-29) a drag on the map does not pan: the building follows the finger. Once one waits there,
 * a later drag anywhere nudges it (half the finger's way, a small joystick), a tap elsewhere moves it there (unless a
 * second tap follows), a double tap sends it (with none waiting: places it at the double tap and sends it). A finger
 * held still for a breath on a building it placed or nudged (or a drag that starts on the waiting building) turns it
 * into a GRID (a buzz as for the three-finger gestures, "GRID" shown over it): the drag draws the grid from it, PLACE
 * or a double tap sends it (BAR's own build drag with Shift+Alt, replayed between its two corners).
 * The X pointer is hidden while two or more fingers are down. Off the map (the void past its edge) fingers work as on
 * it: the map-edge rules of 2026-10-26 (taps off the map clicking nothing, drags anchored mid-screen) are gone (Kailil,
 * 2026-10-27: they made the edge "wonky" and the interface over the void untouchable; edge navigation comes later).
 *
 * Camera moves go to bardroid_touch.lua in the game through files (BAR's sandbox gives user widgets no sockets); the
 * widget answers through bardroid_hover.txt whether the pointer is over the game's interface.
 */
final class RtsTouch {
    private static final long LONG_PRESS_MS = 450, MULTI_TAP_MS = 500;
    private static final long HOVER_WAIT_MS = 250;            // a drag waits this long at most for the widget's answer
    private static final long HOVER_STALE_MS = 3000;          // older answers: the widget is not running
    private static final long LOG_RESTART_BYTES = 256 * 1024;
    private static final double ZOOM_STEP = Math.log(1.12);   // one wheel click per 12% change in finger distance
    private static final float WHEEL_CLICK = 120;              // Termux:X11 scroll units per wheel click
    private static final double ROTATE_START = Math.toRadians(8);   // twist before the camera starts to turn
    private static final long FLING_FRAME_MS = 16;
    private static final float FLING_DECAY = 0.92f;            // velocity kept per fling frame
    private static final long TWO_HOLD_MS = 450;               // two fingers held still this long: the swipe menu
    private static final long THREE_HOLD_MS = 800;             // three fingers held still this long: the layout editor
    // A second finger this soon after the first is one two-finger gesture even if the first already slid a little
    // (fingers never land together; the first one's slide used to lock the gesture into pan/zoom: no tilt)
    private static final long JOIN_MS = 250;
    private static final float TILT_DECIDE_SLOPS = 3;          // how far the fingers may move before a tilt is ruled out
    private static final float SWIPE_SCREEN = 0.08f;           // a swipe: this much of the screen's shorter side
    private static final float NUDGE_GAIN = 0.5f;              // a waiting building moves half the finger's way
    private static final long GRID_REST_MS = 600;              // a finger at rest after moving a building: a GRID

    private enum State { IDLE, PENDING, DRAG_WAIT, PAN, LEFT_DRAG, RIGHT_HOLD, MULTI_PENDING, TWO_FINGER, TILT,
        TWO_HOLD, THREE, PLACE_DRAG, NUDGE, GRID_DRAG, DONE }

    private final MainActivity activity;
    private final float slop, minFling;
    private final long doubleTapMs = ViewConfiguration.getDoubleTapTimeout();
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final Handler io;
    private final HandlerThread ioThread = new HandlerThread("touch-io");
    private final File widgetDir = new File(BarApp.get().paths().bar, "LuaUI/Config");   // the game's write dir
    private final File touchLog = new File(widgetDir, "bardroid_touch.txt");
    private final File screenFile = new File(widgetDir, "bardroid_screen.txt");
    private final File hoverFile = new File(widgetDir, "bardroid_hover.txt");
    private final File placeFile = new File(widgetDir, "bardroid_place.txt");
    private int[] heldKeys = {};                     // modifier keys held for a building's tap or drag
    private FileOutputStream log;
    private long logBytes;

    private State state = State.IDLE;
    private int firstId;
    private float downX, downY, curX, curY;         // first finger, view pixels
    private float panX, panY;                       // where the last pan line ended
    private boolean secondTap;                      // this touch follows a tap: a drag selects
    private long downTime;
    private VelocityTracker velocity;
    private final SparseArray<float[]> starts = new SparseArray<>();
    private int maxFingers;
    private int idA, idB;                           // the two fingers of a two-finger gesture
    private float lastCx, lastCy, lastDist;         // two-finger gesture, view pixels
    private double zoomAcc, lastAngle, rotateAcc;
    private boolean rotating;
    private float lastTapX = -1, lastTapY;          // X screen pixels
    private long lastTapTime;
    private float doubleTapX = -1, doubleTapY;      // the last double click (a third tap: the type on the whole map)
    private long doubleTapTime;
    private boolean joinedPan;                      // this two-finger gesture began as a one-finger pan: no tap
    private float flingX, flingY, flingVx, flingVy; // view pixels, pixels per second
    private boolean cursorHidden;
    // One building picked with ONE (startPlaceDrag): at this touch's start, and where the finger last came to rest
    private boolean placingOne, waitingAtDown, onWaiting;
    private float holdX, holdY, moveX, moveY;       // view pixels: the rest point (the GRID hold), the last move sent
    // A tap with a building waiting moves it only once no second tap follows (a double tap sends the waiting one)
    private Runnable placeTapLater;
    private float placeTapX = -1, placeTapY;        // view pixels: the last tap with ONE picked, for the double tap
    private long placeTapAt = -1;
    private float[] placeTapSpot;                   // X screen pixels: where that tap put the building

    // What the game's widget says is under a point (bardroid_hover.txt)
    private static final int HOVER_UNKNOWN = -1, HOVER_MAP = 0, HOVER_INTERFACE = 1;

    private final Runnable longPress = () -> {
        if (state != State.PENDING) return;
        if (placingOne && hoverAt(downX, downY) == HOVER_MAP) {   // (BAR: a right click would put the building away)
            moveX = curX; moveY = curY;
            startGrid();
            return;
        }
        state = State.RIGHT_HOLD;
        view().performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
        press(downX, downY, InputStub.BUTTON_RIGHT, true);
    };

    /** A finger at rest for a breath while it places or nudges a building: a GRID from it. */
    private final Runnable gridHold = () -> {
        if (state == State.PLACE_DRAG || state == State.NUDGE) startGrid();
    };

    /** Two fingers held still: the next swipe picks an action (twoHoldSwipe). */
    private final Runnable twoHold = () -> {
        if (state != State.MULTI_PENDING || maxFingers != 2) return;
        state = State.TWO_HOLD;
        view().performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
    };

    /** Three fingers held still: the layout editor opens or closes (bardroid_layout.lua). */
    private final Runnable threeHold = () -> {
        if (state != State.MULTI_PENDING || maxFingers != 3) return;
        state = State.DONE;
        view().performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
        act("hud");
    };

    /** The game has not said in time whether the drag started on its interface: pan. */
    private final Runnable hoverTimeout = () -> {
        if (state == State.DRAG_WAIT && !startPlaceDrag()) startPan();   // (ONE picked: a drag never pans)
    };

    private final Runnable fling = new Runnable() {
        @Override public void run() {
            float dt = FLING_FRAME_MS / 1000f;
            float dx = flingVx * dt, dy = flingVy * dt;
            sendPan(flingX, flingY, flingX + dx, flingY + dy);
            flingVx *= FLING_DECAY; flingVy *= FLING_DECAY;
            if (Math.hypot(flingVx, flingVy) >= minFling / 4) ui.postDelayed(this, FLING_FRAME_MS);
        }
    };

    RtsTouch(MainActivity activity) {
        this.activity = activity;
        ViewConfiguration vc = ViewConfiguration.get(activity);
        slop = vc.getScaledTouchSlop();
        minFling = vc.getScaledMinimumFlingVelocity() * 4;
        ioThread.start();
        io = new Handler(ioThread.getLooper());
        io.post(this::restartLog);
    }

    /** A new, empty touch log (the widget sees it shrink and reads from the start). */
    private void restartLog() {
        try {
            if (log != null) log.close();
            //noinspection ResultOfMethodCallIgnored
            widgetDir.mkdirs();
            log = new FileOutputStream(touchLog, false);
            logBytes = 0;
        } catch (IOException e) { Log.e("touch", "touch log", e); log = null; }
    }

    private int screenW, screenH, hz;

    /**
     * The X screen changed size or the display its refresh rate (a foldable folded or unfolded): the widget picks
     * BAR's interface scale for the screen. The file stays, so a game that is still loading picks it up too.
     */
    void screenSize(int w, int h, int refreshHz) {
        if (w <= 0 || h <= 0 || (w == screenW && h == screenH && refreshHz == hz)) return;
        Log.i("display", "X screen " + w + "x" + h + ", display " + refreshHz + " Hz");   // fold/unfold steps
        screenW = w; screenH = h; hz = refreshHz;
        // 0: the widget leaves VSync alone. libbardroid_pace.so caps the frame rate; with vblank_mode=0 Mesa ignores
        // the swap interval, and the widget re-setting VSync at each 60/120 Hz switch only rewrote springsettings.cfg.
        int cap = 0;
        byte[] line = (w + " " + h + " " + refreshHz + " " + cap + "\n").getBytes(StandardCharsets.US_ASCII);
        io.post(() -> {
            File tmp = new File(widgetDir, "bardroid_screen.tmp");
            try {
                //noinspection ResultOfMethodCallIgnored
                widgetDir.mkdirs();
                try (FileOutputStream o = new FileOutputStream(tmp)) { o.write(line); }
                if (!tmp.renameTo(screenFile)) throw new IOException("rename " + tmp);   // the widget never sees half a line
            } catch (IOException e) { Log.e("touch", "screen file", e); }
        });
    }

    void close() {
        ui.removeCallbacksAndMessages(null);   // (also a tap still waiting for the game's answer: tapBuilding)
        ui.removeCallbacks(fling);
        ui.removeCallbacks(longPress);
        ui.removeCallbacks(hoverTimeout);
        ui.removeCallbacks(twoHold);
        ui.removeCallbacks(threeHold);
        releaseKeys();
        io.post(() -> { try { if (log != null) log.close(); } catch (IOException ignored) {} });
        ioThread.quitSafely();
    }

    /** Finger touches on the touchscreen are ours (and the rest of a gesture we started). */
    boolean handles(MotionEvent e) {
        if (state != State.IDLE && state != State.DONE) return true;
        return Prefs.rtsTouch && e.isFromSource(InputDevice.SOURCE_TOUCHSCREEN)
                && e.getToolType(e.getActionIndex()) == MotionEvent.TOOL_TYPE_FINGER;
    }

    /** @param e in the coordinates of the LorieView's parent (as Termux:X11's own listener gets it) */
    boolean onTouch(MotionEvent e) {
        if (velocity != null) velocity.addMovement(e);
        switch (e.getActionMasked()) {
            case MotionEvent.ACTION_DOWN: {
                source("touch");
                finishWaitingTap();   // (before this touch moves the pointer away from the waiting tap's point)
                cancelGesture();
                ui.removeCallbacks(fling);   // a touch stops a gliding map
                state = State.PENDING;
                firstId = e.getPointerId(0);
                downX = curX = e.getX(); downY = curY = e.getY();
                downTime = e.getEventTime();
                // a tap before this one that waits to move a building: a second tap near it may make a double tap
                if (placeTapLater != null) {
                    ui.removeCallbacks(placeTapLater);
                    if (!nearPlaceTap(downX, downY, downTime)) runPlaceTap();
                }
                placeState();
                secondTap = nearLastTap(toX(downX), toY(downY));
                starts.clear();
                starts.put(firstId, new float[]{downX, downY});
                maxFingers = 1;
                if (velocity != null) velocity.recycle();
                velocity = VelocityTracker.obtain();
                velocity.addMovement(e);
                moveCursor(downX, downY);   // the widget reports whether this point is on the game's interface
                ui.postDelayed(longPress, LONG_PRESS_MS);
                break;
            }
            case MotionEvent.ACTION_POINTER_DOWN: {
                int i = e.getActionIndex();
                starts.put(e.getPointerId(i), new float[]{e.getX(i), e.getY(i)});
                maxFingers = Math.max(maxFingers, e.getPointerCount());
                showCursor(false);   // Kailil: the pointer flickering between two fingers looked broken
                if (state == State.PENDING) {
                    ui.removeCallbacks(longPress);
                    state = State.MULTI_PENDING;
                    joinedPan = false;
                    ui.postDelayed(twoHold, TWO_HOLD_MS);
                } else if (state == State.MULTI_PENDING) {
                    ui.removeCallbacks(twoHold);   // a third finger
                    ui.removeCallbacks(threeHold);
                    if (e.getPointerCount() == 3) ui.postDelayed(threeHold, THREE_HOLD_MS);
                } else if ((state == State.PAN || state == State.DRAG_WAIT) && e.getEventTime() - downTime <= JOIN_MS) {
                    // the first finger slid before the second landed: still one two-finger gesture, measured from here
                    ui.removeCallbacks(hoverTimeout);
                    state = State.MULTI_PENDING;
                    joinedPan = true;
                    for (int p = 0; p < e.getPointerCount(); p++) starts.put(e.getPointerId(p), new float[]{e.getX(p), e.getY(p)});
                } else if (state == State.PAN || state == State.DRAG_WAIT || state == State.PLACE_DRAG
                        || state == State.NUDGE || state == State.GRID_DRAG) {
                    ui.removeCallbacks(hoverTimeout);
                    ui.removeCallbacks(gridHold);
                    beginTwoFinger(e, State.TWO_FINGER);   // a second finger joins a pan (or a building's drag): pinch/twist from here
                }
                break;
            }
            case MotionEvent.ACTION_MOVE:
                onMove(e);
                break;
            case MotionEvent.ACTION_POINTER_UP:
                if ((state == State.TWO_FINGER || state == State.TILT || state == State.TWO_HOLD) && e.getPointerCount() <= 2)
                    state = State.DONE;   // one finger left: stop
                break;
            case MotionEvent.ACTION_UP:
                onLastUp(e);
                break;
            case MotionEvent.ACTION_CANCEL:
                cancelGesture();
                break;
            default:
                break;
        }
        return true;
    }

    private void onMove(MotionEvent e) {
        int i = e.findPointerIndex(firstId);
        if (i >= 0) { curX = e.getX(i); curY = e.getY(i); }
        switch (state) {
            case PENDING: {
                if (i < 0 || Math.hypot(curX - downX, curY - downY) <= slop) return;
                ui.removeCallbacks(longPress);
                if (secondTap && place() == null) startLeftDrag();
                else decideDrag(hoverAt(downX, downY));
                return;
            }
            case DRAG_WAIT:
                decideDrag(hoverAt(downX, downY));
                return;
            case PAN:
                panTo(curX, curY);
                return;
            case LEFT_DRAG:
            case RIGHT_HOLD:
                if (i >= 0) moveCursor(curX, curY);
                return;
            case PLACE_DRAG:
            case NUDGE:
                if (i < 0) return;
                if (state == State.PLACE_DRAG) sendSpot(curX, curY);   // the building under the finger
                else nudgeTo(curX, curY);
                if (Math.hypot(curX - holdX, curY - holdY) > slop) {   // still moving: the GRID hold counts from here
                    holdX = curX; holdY = curY;
                    ui.removeCallbacks(gridHold);
                    ui.postDelayed(gridHold, GRID_REST_MS);
                }
                return;
            case GRID_DRAG:
                if (i >= 0) gridTo(curX, curY);
                return;
            case MULTI_PENDING: {
                if (e.getPointerCount() < 2 || !movedPastSlop(e)) return;
                ui.removeCallbacks(twoHold);
                ui.removeCallbacks(threeHold);
                if (maxFingers >= 3) {   // three fingers: a swipe, measured from where they came down
                    state = State.THREE;
                    swipe(e);
                    return;
                }
                State kind = twoFingerKind(e);
                if (kind == null) return;
                beginTwoFinger(e, kind);
                if (kind == State.TILT) {   // the tilt counts from where the fingers came down
                    float[] sa = starts.get(idA), sb = starts.get(idB);
                    if (sa != null && sb != null) lastCy = (sa[1] + sb[1]) / 2;
                }
                return;
            }
            case TWO_HOLD:
            case THREE:
                swipe(e);
                return;
            case TWO_FINGER: {
                int a = e.findPointerIndex(idA), b = e.findPointerIndex(idB);
                if (a < 0 || b < 0) return;
                float cx = (e.getX(a) + e.getX(b)) / 2, cy = (e.getY(a) + e.getY(b)) / 2, d = dist(e, a, b);
                if (cx != lastCx || cy != lastCy) sendPan(lastCx, lastCy, cx, cy);
                if (lastDist > 0 && d > 0 && d != lastDist) {
                    if (gameWidgetRunning()) {
                        // in a game the widget zooms continuously about the pinch (wheel clicks zoomed in 12% steps)
                        send(String.format(Locale.US, "zoom %.5f %.1f %.1f", d / lastDist, toX(cx), toY(cy)));
                    } else {   // the lobby: the wheel scrolls its lists
                        zoomAcc += Math.log(d / lastDist);
                        while (zoomAcc >= ZOOM_STEP) { wheel(cx, cy, -WHEEL_CLICK); zoomAcc -= ZOOM_STEP; }   // spread
                        while (zoomAcc <= -ZOOM_STEP) { wheel(cx, cy, WHEEL_CLICK); zoomAcc += ZOOM_STEP; }   // pinch
                    }
                }
                double angle = angle(e, a, b), turn = Math.IEEEremainder(angle - lastAngle, 2 * Math.PI);
                if (rotating) {
                    send(String.format(Locale.US, "rot %.4f", turn));
                } else if (Math.abs(rotateAcc += turn) >= ROTATE_START) {
                    rotating = true;   // the whole twist so far, so the map stays under the fingers
                    send(String.format(Locale.US, "rot %.4f", rotateAcc));
                }
                lastCx = cx; lastCy = cy; lastDist = d; lastAngle = angle;
                return;
            }
            case TILT: {
                int a = e.findPointerIndex(idA), b = e.findPointerIndex(idB);
                if (a < 0 || b < 0) return;
                float cy = (e.getY(a) + e.getY(b)) / 2;
                float h = view().getInputSourceRect().height();
                if (cy != lastCy && h > 0)
                    send(String.format(Locale.US, "tilt %.4f", (toY(cy) - toY(lastCy)) / h));   // fraction of the screen height
                lastCy = cy;
                return;
            }
            default:
        }
    }

    private void onLastUp(MotionEvent e) {
        ui.removeCallbacks(longPress);
        ui.removeCallbacks(hoverTimeout);
        ui.removeCallbacks(twoHold);
        ui.removeCallbacks(threeHold);
        ui.removeCallbacks(gridHold);
        curX = e.getX(); curY = e.getY();
        if (state != State.PENDING) runPlaceTap();   // (not a double tap: the tap before moves its building now)
        switch (state) {
            case PENDING:
                tap(downX, downY);
                break;
            case DRAG_WAIT:
                if (hoverAt(downX, downY) == HOVER_INTERFACE) {   // a quick drag on the interface
                    press(downX, downY, InputStub.BUTTON_LEFT, true);
                    press(curX, curY, InputStub.BUTTON_LEFT, false);
                } else if (startPlaceDrag()) {   // (ONE picked: the building moved, the map stays)
                    ui.removeCallbacks(gridHold);
                } else {
                    startPan();
                    flingIfFast();
                }
                break;
            case PAN:
                panTo(curX, curY);
                flingIfFast();
                break;
            case LEFT_DRAG:
                press(curX, curY, InputStub.BUTTON_LEFT, false);
                releaseKeys();
                break;
            case RIGHT_HOLD:
                press(curX, curY, InputStub.BUTTON_RIGHT, false);
                break;
            case MULTI_PENDING:
                if (!joinedPan && e.getEventTime() - downTime <= MULTI_TAP_MS) {
                    if (maxFingers == 2) {
                        press(downX, downY, InputStub.BUTTON_RIGHT, true);
                        press(downX, downY, InputStub.BUTTON_RIGHT, false);
                    } else if (maxFingers == 3) {
                        activity.toggleKeyboardVisibility();
                    }
                }
                break;
            default:
        }
        state = State.IDLE;
        showCursor(true);
        if (velocity != null) { velocity.recycle(); velocity = null; }
        io.post(() -> { if (logBytes > LOG_RESTART_BYTES) restartLog(); });   // between gestures only
    }

    private void cancelGesture() {
        ui.removeCallbacks(longPress);
        ui.removeCallbacks(hoverTimeout);
        ui.removeCallbacks(twoHold);
        ui.removeCallbacks(threeHold);
        ui.removeCallbacks(gridHold);
        // (a tap before this touch, held back for a double tap: this one was none, so its building moves now, not at
        // some later touch)
        runPlaceTap();
        if (state == State.LEFT_DRAG) press(downX, downY, InputStub.BUTTON_LEFT, false);
        if (state == State.RIGHT_HOLD) press(downX, downY, InputStub.BUTTON_RIGHT, false);
        releaseKeys();
        state = State.IDLE;
        showCursor(true);
    }

    /** The X pointer is hidden while two or more fingers are down. */
    private void showCursor(boolean visible) {
        if (cursorHidden == !visible) return;
        cursorHidden = !visible;
        view().setCursorVisible(visible);
    }

    /** A one-finger drag: a left drag where it started on the game's interface, else a pan; not known yet: wait. */
    private void decideDrag(int hover) {
        if (hover == HOVER_UNKNOWN) {
            if (state != State.DRAG_WAIT) {
                state = State.DRAG_WAIT;
                ui.postDelayed(hoverTimeout, HOVER_WAIT_MS);
            }
            return;
        }
        ui.removeCallbacks(hoverTimeout);
        if (hover == HOVER_MAP && (startShapeDrag() || startPlaceDrag())) return;
        if (hover == HOVER_INTERFACE) startLeftDrag();
        else startPan();
    }

    /**
     * ONE picked: a drag on the map moves the building instead of the map. With none waiting it follows the finger;
     * with one waiting (placed earlier, not by a tap just now) the drag nudges it; a drag that starts on it draws a
     * GRID from it. False: not ONE.
     */
    private boolean startPlaceDrag() {
        if (!placingOne) return false;
        runPlaceTap();
        holdX = curX; holdY = curY;
        if (onWaiting) {
            moveX = downX; moveY = downY;
            startGrid();
            gridTo(curX, curY);
            return true;
        }
        moveX = curX; moveY = curY;
        if (waitingAtDown) {
            state = State.NUDGE;
        } else {
            state = State.PLACE_DRAG;
            sendSpot(curX, curY);
        }
        ui.postDelayed(gridHold, GRID_REST_MS);
        return true;
    }

    /**
     * The building waiting (or the one under a finger held still where it came down) becomes the first corner of a
     * GRID: a buzz as for the three-finger gestures, "GRID" over it (bardroid_buildmenu.lua), and the finger's way from
     * here moves the far corner.
     */
    private void startGrid() {
        ui.removeCallbacks(gridHold);
        runPlaceTap();
        if (state == State.PENDING && !waitingAtDown) sendSpot(curX, curY);
        state = State.GRID_DRAG;
        view().performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
        send("grid start");
    }

    private void sendSpot(float vx, float vy) {
        send(String.format(Locale.US, "spot %.0f %.0f", toX(vx), toY(vy)));
        spotSentAt = SystemClock.uptimeMillis();
    }

    /** The waiting building moved by part of the finger's way since the last move (X screen pixels, y down). */
    private void nudgeTo(float vx, float vy) {
        float k = xPerViewPixel() * NUDGE_GAIN;
        if (vx == moveX && vy == moveY) return;
        send(String.format(Locale.US, "nudge %.2f %.2f", (vx - moveX) * k, (vy - moveY) * k));
        moveX = vx; moveY = vy;
        spotSentAt = SystemClock.uptimeMillis();
    }

    /** The GRID's far corner moved by the finger's way since the last move. */
    private void gridTo(float vx, float vy) {
        float k = xPerViewPixel();
        if (vx == moveX && vy == moveY) return;
        send(String.format(Locale.US, "grid by %.1f %.1f", (vx - moveX) * k, (vy - moveY) * k));
        moveX = vx; moveY = vy;
    }

    /**
     * A building picked with LINE, GRID or BORDER: the drag lays it out with BAR's own build drag (the engine's
     * GuiHandler: no modifier a line, Alt a filled rectangle, Alt+Ctrl a hollow one; Shift queues them and keeps the
     * building picked). False: nothing picked, or ONE (the drag pans).
     */
    private boolean startShapeDrag() {
        Place p = place();
        String shape = p == null ? null : p.shape;
        if (shape == null || shape.equals("one")) return false;
        if (shape.equals("grid")) holdKeys(KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_ALT_LEFT);
        else if (shape.equals("border")) holdKeys(KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_ALT_LEFT, KeyEvent.KEYCODE_CTRL_LEFT);
        else holdKeys(KeyEvent.KEYCODE_SHIFT_LEFT);
        startLeftDrag();
        return true;
    }

    private void holdKeys(int... keys) {
        releaseKeys();
        heldKeys = keys;
        for (int k : keys) view().sendKeyEvent(0, k, true);
    }

    private void releaseKeys() {
        for (int i = heldKeys.length - 1; i >= 0; i--) view().sendKeyEvent(0, heldKeys[i], false);
        heldKeys = new int[0];
    }

    /** The building picked in the app's build menu (bardroid_buildmenu.lua writes bardroid_place.txt). */
    private static final class Place {
        String shape;      // one, line, grid or border
        float[] done;      // its PLACE button: x0 y0 x1 y1, X screen pixels
        float[] spot;      // where the spot a tap picked is on the screen now; null: none (or off the screen)
        float spotR;       // the building's size there (X screen pixels from its middle)
        boolean grid;      // a GRID waits (ONE: from the spot)
        float[] gridEnds;  // its first and far corner buildings on the screen: x0 y0 x1 y1; null: one is off it
    }

    /**
     * The building picked, its shape, PLACE button, spot and GRID ("place <shape>", "done x0 y0 x1 y1", "spot x y r",
     * "grid x0 y0 x1 y1" or "grid off" in bardroid_place.txt, written again every second while one is picked); null:
     * none picked, no game, or an old file.
     */
    private Place place() {
        if (!gameWidgetRunning() || System.currentTimeMillis() - placeFile.lastModified() > HOVER_STALE_MS) return null;
        String text = readSmall(placeFile);
        if (text == null) return null;
        Place p = null;
        try {
            for (String line : text.split("\n")) {
                String[] f = line.trim().split(" ");
                if (f[0].equals("place") && f.length == 2 && !f[1].equals("none")) {
                    p = new Place();
                    p.shape = f[1];
                } else if (p != null && f[0].equals("done") && f.length == 5) {
                    p.done = new float[]{Float.parseFloat(f[1]), Float.parseFloat(f[2]), Float.parseFloat(f[3]), Float.parseFloat(f[4])};
                } else if (p != null && f[0].equals("spot") && (f.length == 3 || f.length == 4)) {
                    p.spot = new float[]{Float.parseFloat(f[1]), Float.parseFloat(f[2])};
                    if (f.length == 4) p.spotR = Float.parseFloat(f[3]);
                } else if (p != null && f[0].equals("grid")) {
                    p.grid = true;
                    if (f.length == 5) {
                        p.gridEnds = new float[]{Float.parseFloat(f[1]), Float.parseFloat(f[2]), Float.parseFloat(f[3]), Float.parseFloat(f[4])};
                    }
                }
            }
        } catch (NumberFormatException e) { return null; }
        return p;
    }

    private long spotSentAt = -1;   // when this app last put a building somewhere (the game writes it back a frame later)

    /** At a touch's start: ONE picked, a building waiting (not one a tap put down just now), the finger on it. */
    private void placeState() {
        Place p = place();
        placingOne = p != null && "one".equals(p.shape);
        boolean waiting = placingOne && (p.spot != null || p.grid
                || (spotSentAt >= 0 && SystemClock.uptimeMillis() - spotSentAt < HOVER_STALE_MS));
        // (a quick second touch after a tap that put the building down moves it under the finger again: "a second
        // (delayed) touch" nudges)
        waitingAtDown = waiting && !(placeTapAt >= 0 && placeTapSpot != null && downTime - placeTapAt <= doubleTapMs);
        onWaiting = false;
        if (waitingAtDown && p.spot != null) {
            float r = Math.max(p.spotR, 3 * slop * xPerViewPixel());
            onWaiting = Math.hypot(toX(downX) - p.spot[0], toY(downY) - p.spot[1]) <= r;
        }
    }

    private boolean nearPlaceTap(float vx, float vy, long when) {
        return placeTapX >= 0 && when - placeTapAt <= doubleTapMs && Math.hypot(vx - placeTapX, vy - placeTapY) <= slop * 2;
    }

    /** The tap before, which waited for a second one, moves its building now. */
    private void runPlaceTap() {
        Runnable r = placeTapLater;
        if (r == null) return;
        ui.removeCallbacks(r);
        placeTapLater = null;
        r.run();
    }

    /**
     * A tap on the map with ONE picked: with no building waiting it goes there; with one waiting it moves there unless
     * a second tap follows; a double tap sends the waiting building (or grid), or the one the first tap put down.
     */
    private void tapOne(float vx, float vy, Place place) {
        float x = toX(vx), y = toY(vy);
        if (nearPlaceTap(vx, vy, downTime)) {
            Runnable firstMove = placeTapLater;   // (the first tap would have moved a waiting building: not now)
            if (firstMove != null) { ui.removeCallbacks(firstMove); placeTapLater = null; }
            float[] fallback = placeTapSpot;
            placeTapX = -1; placeTapAt = -1; placeTapSpot = null;
            sendPlaced(place, fallback);
            return;
        }
        placeTapX = vx; placeTapY = vy; placeTapAt = SystemClock.uptimeMillis();
        boolean waiting = place.spot != null || place.grid
                || (spotSentAt >= 0 && SystemClock.uptimeMillis() - spotSentAt < HOVER_STALE_MS);
        if (waiting) {
            placeTapSpot = null;
            placeTapLater = () -> {
                placeTapLater = null;
                send("grid none");
                send(String.format(Locale.US, "spot %.0f %.0f", x, y));
                spotSentAt = SystemClock.uptimeMillis();
            };
            ui.postDelayed(placeTapLater, doubleTapMs);
        } else {
            placeTapSpot = new float[]{x, y};
            send(String.format(Locale.US, "spot %.0f %.0f", x, y));
            spotSentAt = SystemClock.uptimeMillis();
        }
    }

    /**
     * The building at its spot (Shift click: queued, the building stays picked), or a waiting GRID (BAR's own build
     * drag with Shift+Alt from its first to its far corner). fallback: where a tap just put it, before the game said so.
     */
    private void sendPlaced(Place p, float[] fallback) {
        lastTapX = -1; doubleTapX = -1;
        if (p.grid) {
            float[] g = p.gridEnds;
            if (g == null) return;   // (a corner off the screen: PLACE is grey)
            holdKeys(KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_ALT_LEFT);
            LorieView v = view();
            v.sendMouseEvent(g[0], g[1], InputStub.BUTTON_UNDEFINED, false, false);
            v.sendMouseEvent(g[0], g[1], InputStub.BUTTON_LEFT, true, false);
            v.sendMouseEvent(g[2], g[3], InputStub.BUTTON_UNDEFINED, false, false);
            v.sendMouseEvent(g[2], g[3], InputStub.BUTTON_LEFT, false, false);
            releaseKeys();
            send("grid none");
        } else {
            float[] s = p.spot != null ? p.spot : fallback;
            if (s == null) return;
            holdKeys(KeyEvent.KEYCODE_SHIFT_LEFT);
            clickAt(s[0], s[1]);
            releaseKeys();
        }
        send("spot none");
        spotSentAt = -1;
    }

    /** A left click at X screen pixel (x, y). */
    private void clickAt(float x, float y) {
        LorieView v = view();
        v.sendMouseEvent(x, y, InputStub.BUTTON_UNDEFINED, false, false);
        v.sendMouseEvent(x, y, InputStub.BUTTON_LEFT, true, false);
        v.sendMouseEvent(x, y, InputStub.BUTTON_LEFT, false, false);
    }

    private void startLeftDrag() {
        state = State.LEFT_DRAG;
        if (secondTap) lastTapX = -1;   // the tap before a box select does not start a double click
        press(downX, downY, InputStub.BUTTON_LEFT, true);
        moveCursor(curX, curY);
    }

    private void startPan() {
        state = State.PAN;
        panX = downX; panY = downY;
        panTo(curX, curY);   // catch up with the finger
    }

    private void panTo(float x, float y) {
        if (x == panX && y == panY) return;
        sendPan(panX, panY, x, y);
        panX = x; panY = y;
    }

    private void flingIfFast() {
        if (velocity == null) return;
        velocity.computeCurrentVelocity(1000);
        float vx = velocity.getXVelocity(firstId), vy = velocity.getYVelocity(firstId);
        if (Math.hypot(vx, vy) < minFling) return;
        // glide around the screen centre: a point near the edge would hit the clamp (or the sky) on the way
        LorieView v = view();
        Rect vp = v.getInputViewport();
        flingX = v.getLeft() + vp.exactCenterX(); flingY = v.getTop() + vp.exactCenterY();
        flingVx = vx; flingVy = vy;
        ui.postDelayed(fling, FLING_FRAME_MS);
    }

    private void beginTwoFinger(MotionEvent e, State next) {
        state = next;
        idA = e.getPointerId(0); idB = e.getPointerId(1);
        lastCx = (e.getX(0) + e.getX(1)) / 2; lastCy = (e.getY(0) + e.getY(1)) / 2;
        lastDist = dist(e, 0, 1);
        lastAngle = angle(e, 0, 1);
        zoomAcc = 0; rotateAcc = 0; rotating = false;
    }

    /**
     * Which two-finger gesture this is, once a finger has moved past the slop (null: not clear yet). Both fingers moving
     * up or down together, without pinching or twisting, is a tilt (as in map apps), however the fingers sit; the rest
     * pans, zooms and twists. Kailil (2026-10-26): tilting took "super careful and deliberate" fingers side by side,
     * decided at the first finger's first slop: now the slower finger gets up to TILT_DECIDE_SLOPS slops to follow.
     */
    private State twoFingerKind(MotionEvent e) {
        float[] sa = starts.get(e.getPointerId(0)), sb = starts.get(e.getPointerId(1));
        if (sa == null || sb == null) return State.TWO_FINGER;
        float ax = e.getX(0) - sa[0], ay = e.getY(0) - sa[1], bx = e.getX(1) - sb[0], by = e.getY(1) - sb[1];
        float cx = (ax + bx) / 2, cy = (ay + by) / 2;
        double spread = Math.abs(dist(e, 0, 1) - Math.hypot(sa[0] - sb[0], sa[1] - sb[1]));
        double twist = Math.abs(Math.IEEEremainder(angle(e, 0, 1) - Math.atan2(sb[1] - sa[1], sb[0] - sa[0]), 2 * Math.PI));
        boolean vertical = Math.abs(cy) > 1.2f * Math.abs(cx) && spread < 0.6 * Math.abs(cy) && twist < ROTATE_START;
        if (vertical && ay * by > 0 && Math.min(Math.abs(ay), Math.abs(by)) > slop / 3) return State.TILT;
        double most = Math.max(Math.hypot(ax, ay), Math.hypot(bx, by));
        if (vertical && ay * by >= 0 && most < TILT_DECIDE_SLOPS * slop) return null;   // the other finger may follow
        return State.TWO_FINGER;
    }

    /**
     * Two fingers after the hold, or three fingers: once the middle of the fingers has moved SWIPE_SCREEN of the screen's
     * shorter side, the direction picks the action (once a gesture).
     */
    private void swipe(MotionEvent e) {
        float sx = 0, sy = 0, x = 0, y = 0;
        int n = 0;
        for (int i = 0; i < e.getPointerCount(); i++) {
            float[] s = starts.get(e.getPointerId(i));
            if (s == null) continue;
            sx += s[0]; sy += s[1]; x += e.getX(i); y += e.getY(i); n++;
        }
        if (n == 0) return;
        float dx = (x - sx) / n, dy = (y - sy) / n;
        LorieView v = view();
        if (Math.hypot(dx, dy) < Math.max(3 * slop, SWIPE_SCREEN * Math.min(v.getWidth(), v.getHeight()))) return;
        boolean three = state == State.THREE;
        String name = Math.abs(dx) > Math.abs(dy)
                ? (dx > 0 ? (three ? "idle_next" : "fight") : (three ? "idle_prev" : "stop"))
                : (dy < 0 ? (three ? "overview_in" : "select_all") : (three ? "commander_view" : "deselect"));
        state = State.DONE;
        v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
        act(name);
    }

    /** A game action for the widget (bardroid_touch.lua ACTIONS); in the lobby there is none. */
    private void act(String name) {
        if (gameWidgetRunning()) send("act " + name);
    }

    private boolean nearLastTap(float x, float y) {
        float tol = slop * 2 * xPerViewPixel();
        return lastTapX >= 0 && SystemClock.uptimeMillis() - lastTapTime <= doubleTapMs
                && Math.abs(x - lastTapX) <= tol && Math.abs(y - lastTapY) <= tol;
    }

    private void tap(float vx, float vy) {
        Place place = place();
        if (place != null && tapBuilding(vx, vy, place, hoverAt(vx, vy), HOVER_ASKS)) return;
        runPlaceTap();
        clickTap(vx, vy);
    }

    private static final int HOVER_ASKS = 8;   // a tap with a building picked asks this often, HOVER_WAIT_MS in all
    private Runnable waitingTap;   // such a tap still waiting for the game's answer, and its point (view pixels)
    private float waitX, waitY;

    /**
     * A tap still waiting for the game's answer is decided at the next touch down, with the answer there is by then
     * (none: the click, as after the wait): the next touch moves the pointer, so the answer for the tap's point could
     * no longer come, and the click came 250 ms later, in the middle of the new gesture (a drag's button held).
     */
    private void finishWaitingTap() {
        if (waitingTap == null) return;
        ui.removeCallbacks(waitingTap);
        waitingTap = null;
        Place p = place();
        if (p == null || !tapBuilding(waitX, waitY, p, hoverAt(waitX, waitY), 0)) clickTap(waitX, waitY);
    }
    /**
     * A tap with a building picked: true when it was PLACE or picked the spot (or will be decided shortly). Where the
     * game has not yet said whether the point is on its interface (a quick tap, a slow frame late in a game), it asks
     * again for up to HOVER_WAIT_MS before the tap becomes a click: a plain click on the map would place the building
     * at once, without PLACE.
     */
    private boolean tapBuilding(float vx, float vy, Place place, int hover, int asks) {
        float x = toX(vx), y = toY(vy);
        float[] d = place.done;
        if (d != null && x >= d[0] && x <= d[2] && y >= d[1] && y <= d[3]) {
            // PLACE: the building at the spot (or the GRID), and it stays picked for the next (Shift held)
            lastTapX = -1; doubleTapX = -1;
            runPlaceTap();
            if (place.spot != null || place.grid) sendPlaced(place, null);
            return true;
        }
        if (hover == HOVER_UNKNOWN && asks > 0) {
            waitX = vx; waitY = vy;
            waitingTap = () -> {
                waitingTap = null;
                Place p = place();
                if (p == null || !tapBuilding(vx, vy, p, hoverAt(vx, vy), asks - 1)) clickTap(vx, vy);
            };
            ui.postDelayed(waitingTap, HOVER_WAIT_MS / HOVER_ASKS);
            return true;
        }
        if (hover == HOVER_MAP) {   // the spot: the building shows there until PLACE
            lastTapX = -1; doubleTapX = -1;
            if ("one".equals(place.shape)) {
                tapOne(vx, vy, place);
                return true;
            }
            send(String.format(Locale.US, "spot %.0f %.0f", x, y));
            return true;
        }
        return false;
    }

    /** A tap as a left click; a quick second one a double click, a third the type on the whole map. */
    private void clickTap(float vx, float vy) {
        float x = toX(vx), y = toY(vy);
        float tol = slop * 2 * xPerViewPixel();
        long now = SystemClock.uptimeMillis();
        // A third quick tap: the double click's unit types on the whole map; in the controller game it switches the
        // controller mod instead (GameActivity). No click (it would select one unit).
        if (doubleTapX >= 0 && now - doubleTapTime <= doubleTapMs && Math.abs(x - doubleTapX) <= tol
                && Math.abs(y - doubleTapY) <= tol && gameWidgetRunning()) {
            doubleTapX = -1;
            if (tripleTap != null && controllerGame()) tripleTap.run();
            else act("type_all");
            return;
        }
        // A double click needs both clicks on the same pixel; fingers land a few pixels apart.
        if (nearLastTap(x, y)) {
            x = lastTapX; y = lastTapY;
            lastTapX = -1;
            doubleTapX = x; doubleTapY = y; doubleTapTime = now;
        } else {
            doubleTapX = -1;
            lastTapX = x; lastTapY = y; lastTapTime = SystemClock.uptimeMillis();
        }
        LorieView v = view();
        v.sendMouseEvent(x, y, InputStub.BUTTON_UNDEFINED, false, false);
        v.sendMouseEvent(x, y, InputStub.BUTTON_LEFT, true, false);
        v.sendMouseEvent(x, y, InputStub.BUTTON_LEFT, false, false);
    }

    private void press(float vx, float vy, int button, boolean down) {
        LorieView v = view();
        float x = toX(vx), y = toY(vy);
        v.sendMouseEvent(x, y, InputStub.BUTTON_UNDEFINED, false, false);
        v.sendMouseEvent(x, y, button, down, false);
    }

    private void moveCursor(float vx, float vy) {
        view().sendMouseEvent(toX(vx), toY(vy), InputStub.BUTTON_UNDEFINED, false, false);
    }

    private void wheel(float vx, float vy, float dy) {
        moveCursor(vx, vy);
        view().sendMouseWheelEvent(0, dy);
    }

    /** The map point under view pixel (x0, y0) moves to (x1, y1). */
    private void sendPan(float x0, float y0, float x1, float y1) {
        send(String.format(Locale.US, "pan %.1f %.1f %.1f %.1f", toX(x0), toY(y0), toX(x1), toY(y1)));
    }

    /** The gamepad camera's stick state (ControllerBridge, any thread): the widget moves the camera every frame. */
    void padLine(String line) { send(line); }

    /** A gamepad button's game action (ControllerBridge, any thread). */
    void padAct(String name) { act(name); }

    private Runnable tripleTap;
    /** What a third quick tap does in the controller game (GameActivity: switch the controller mod). */
    void setTripleTap(Runnable r) { tripleTap = r; }

    private final File gameFile = new File(widgetDir, "bardroid_game.txt");
    private volatile long gameFileAt = -1;
    private volatile boolean controllerGame;
    /** The game is the controller game (v0.8.5 reads the pad): bardroid_game.txt "controller 1". Any thread. */
    boolean controllerGame() {
        long at = gameFile.lastModified();
        if (at != gameFileAt) {
            String text = readSmall(gameFile);
            controllerGame = text != null && text.trim().equals("controller 1");
            gameFileAt = at;
        }
        return controllerGame;
    }

    private final File padFile = new File(widgetDir, "bardroid_pad.txt");
    private volatile long padAt;
    private volatile String padFocus = "none", armed = "none";
    private volatile boolean pregame;
    /**
     * The menu that has the gamepad: "build", "orders" or "none" (bardroid_pad.lua writes bardroid_pad.txt, again every
     * second while a menu has it, an order is picked or the game has not started). Any thread.
     */
    String padFocus() { padState(); return padFocus; }
    /** The game has not started yet (bardroid_pad.txt). Any thread. */
    boolean pregame() { padState(); return pregame; }
    /** The order picked: "build", "area" (an area only: area mex), "unitarea", "other" or "none". Any thread. */
    String armed() { padState(); return armed; }
    private void padState() {   // (read at most every 100 ms: the pad asks each tick)
        long now = SystemClock.uptimeMillis();
        if (now - padAt < 100) return;
        padAt = now;
        String text = gameWidgetRunning() && System.currentTimeMillis() - padFile.lastModified() <= HOVER_STALE_MS
                ? readSmall(padFile) : null;
        String focus = "none", picked = "none";
        boolean before = false;
        if (text != null) {
            for (String line : text.split("\n")) {
                String[] f = line.trim().split(" ");
                if (f.length != 2) continue;
                if (f[0].equals("focus")) focus = f[1];
                if (f[0].equals("pregame")) before = f[1].equals("1");
                if (f[0].equals("armed")) picked = f[1];
                if (f[0].equals("drawspeed")) {
                    try { drawSpeed = Float.parseFloat(f[1]); } catch (NumberFormatException e) { /* the last one stands */ }
                }
            }
        }
        padFocus = focus;
        pregame = before;
        armed = picked;
    }
    private volatile float drawSpeed = 1;
    /** The pointer's speed while drawing, for the camera's zoom (bardroid_padspeed.lua). Any thread. */
    float drawSpeed() { padState(); return drawSpeed; }

    /** Where the pointer is by the game's last answer (bardroid_hover.txt, X screen pixels); null: no answer. Any thread. */
    float[] pointerAt() {
        if (!gameWidgetRunning()) return null;
        String text = readSmall(hoverFile);
        String[] f = text == null ? new String[0] : text.trim().split(" ");
        if (f.length != 3) return null;
        try { return new float[]{Float.parseFloat(f[0]), Float.parseFloat(f[1])}; } catch (NumberFormatException e) { return null; }
    }

    private volatile long interfaceAt;
    private volatile boolean onInterface;
    /** The game's last answer for the pointer, wherever it is: over the interface (read at most every 100 ms). Any thread. */
    boolean pointerOnInterface() {
        long now = SystemClock.uptimeMillis();
        if (now - interfaceAt >= 100) {
            String text = readSmall(hoverFile);
            String[] f = text == null ? new String[0] : text.trim().split(" ");
            onInterface = f.length == 3 && f[2].equals("1");
            interfaceAt = now;
        }
        return onInterface;
    }

    private static String readSmall(File file) {
        byte[] b = new byte[160];
        int n;
        try (FileInputStream in = new FileInputStream(file)) { n = in.read(b); } catch (IOException e) { return null; }
        return n <= 0 ? null : new String(b, 0, n, StandardCharsets.US_ASCII);
    }

    private static final int TAPS_OFF_PAD = 3;          // this many touches ...
    private static final long TAPS_OFF_PAD_MS = 6000;   // ... within this long end the pad's ways
    private String inputSource;
    private long inputSourceAt;
    private boolean padInUse;
    private int tapsOffPad;
    private long tapsOffPadFrom;
    /**
     * The input just used: "touch", "mouse", "keyboard" or "pad" (UI thread). bardroid_spectate.lua shows its touch
     * tools only after fingers. Sent when it changes, and again at most every 2 s while in use: a game started since
     * reads only lines written after its start. The pad's use starts its ways in the widgets ("src pad": menus hidden
     * until RB, its orders off); a few taps end them ("act fingers"; Kailil, 2026-10-30: "it should detect then
     * disable gamepad only mode"), a mouse or keyboard at once.
     */
    void source(String s) {
        long now = SystemClock.uptimeMillis();
        if (s.equals("pad")) {
            padInUse = true;
            tapsOffPad = 0;
        } else if (padInUse) {
            if (tapsOffPad == 0 || now - tapsOffPadFrom > TAPS_OFF_PAD_MS) { tapsOffPad = 0; tapsOffPadFrom = now; }
            if (++tapsOffPad >= TAPS_OFF_PAD || !s.equals("touch")) {
                padInUse = false;
                send("act fingers");
            }
        }
        if (s.equals(inputSource) && now - inputSourceAt < 2000) return;
        inputSource = s;
        inputSourceAt = now;
        send("src " + s);
    }

    /** A game's widget answers (it writes the hover file at least once a second); not in the lobby. Any thread. */
    boolean gameWidgetRunning() {
        return System.currentTimeMillis() - hoverFile.lastModified() <= HOVER_STALE_MS;
    }

    /** Appends one line to the touch log (the widget reads complete lines each frame). */
    private void send(String msg) {
        byte[] data = (msg + "\n").getBytes(StandardCharsets.US_ASCII);
        io.post(() -> {
            if (log == null) return;
            try { log.write(data); logBytes += data.length; } catch (IOException e) { Log.e("touch", "touch log", e); }
        });
    }

    /**
     * What is under view pixel (x, y) by the widget's last answer ("x y 0|1" in X screen pixels, written when the
     * pointer moves and every second): HOVER_INTERFACE (the game's interface or the minimap) or HOVER_MAP;
     * HOVER_UNKNOWN while it has not answered for that point. Without a widget (the lobby, a game still loading)
     * everything is interface: drags stay mouse drags.
     */
    private int hoverAt(float vx, float vy) {
        if (System.currentTimeMillis() - hoverFile.lastModified() > HOVER_STALE_MS) return HOVER_INTERFACE;
        byte[] b = new byte[64];
        int n;
        try (FileInputStream in = new FileInputStream(hoverFile)) { n = in.read(b); } catch (IOException e) { return HOVER_UNKNOWN; }
        if (n <= 0) return HOVER_UNKNOWN;
        String[] f = new String(b, 0, n, StandardCharsets.US_ASCII).trim().split(" ");
        if (f.length != 3) return HOVER_UNKNOWN;
        try {
            if (Math.abs(Integer.parseInt(f[0]) - toX(vx)) > 2 || Math.abs(Integer.parseInt(f[1]) - toY(vy)) > 2) return HOVER_UNKNOWN;
            return f[2].equals("1") ? HOVER_INTERFACE : HOVER_MAP;
        } catch (NumberFormatException e) { return HOVER_UNKNOWN; }
    }

    private boolean movedPastSlop(MotionEvent e) {
        for (int i = 0; i < e.getPointerCount(); i++) {
            float[] s = starts.get(e.getPointerId(i));
            if (s != null && Math.hypot(e.getX(i) - s[0], e.getY(i) - s[1]) > slop) return true;
        }
        return false;
    }

    private static float dist(MotionEvent e, int a, int b) {
        return (float) Math.hypot(e.getX(a) - e.getX(b), e.getY(a) - e.getY(b));
    }

    private static double angle(MotionEvent e, int a, int b) {
        return Math.atan2(e.getY(b) - e.getY(a), e.getX(b) - e.getX(a));
    }

    private LorieView view() { return activity.getLorieView(); }

    // View (parent) pixels -> X screen pixels: the LorieView draws the visible part of the X screen into its viewport.
    private float toX(float px) {
        LorieView v = view();
        Rect vp = v.getInputViewport();
        RectF src = v.getInputSourceRect();
        if (vp.width() <= 0) return px;
        return clamp(src.left + (px - v.getLeft() - vp.left) * src.width() / vp.width(), src.left, src.right - 1);
    }

    private float toY(float py) {
        LorieView v = view();
        Rect vp = v.getInputViewport();
        RectF src = v.getInputSourceRect();
        if (vp.height() <= 0) return py;
        return clamp(src.top + (py - v.getTop() - vp.top) * src.height() / vp.height(), src.top, src.bottom - 1);
    }

    private float xPerViewPixel() {
        LorieView v = view();
        Rect vp = v.getInputViewport();
        return vp.width() > 0 ? v.getInputSourceRect().width() / vp.width() : 1;
    }

    private static float clamp(float v, float lo, float hi) { return Math.max(lo, Math.min(hi, v)); }
}
