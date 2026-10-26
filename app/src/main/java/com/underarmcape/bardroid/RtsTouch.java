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
 *   tap                  left click (select, buttons, place a building); a quick second tap is a double click
 *   drag                 pan: the map follows the finger, and keeps gliding after a flick. A drag that starts on the
 *                        game's interface (minimap, sliders, windows) is a left drag instead
 *   tap, then drag       left drag: box select
 *   long press           right button: lift = right click (move/attack order), keep dragging = right drag (formation)
 *   two-finger tap       right click at the first finger
 *   two fingers          move = pan, pinch = zoom (mouse wheel at the pinch centre; BAR zooms towards the cursor),
 *                        twist = rotate the camera
 *   two fingers up/down  tilt the camera (both fingers moving the same way, side by side)
 *   three-finger tap     show / hide the keyboard
 *
 * Touch-only mode (launcher option, TOUCH-UI.md) adds, with the touch HUD widget in the game:
 *   drag on the map      with a command armed: a left drag (formation line, area circle; a line of buildings with
 *                        QUEUE); with a building armed and QUEUE off: the ghost follows a centimetre above the finger
 *                        and lifting places it; with BOX latched: box select
 *   tap, then drag       box select drawn by the HUD (no mouse button: a left press on the map is always a tap there)
 *   two fingers          zoom is a camera line (smooth, unaffected by a held Shift/Ctrl); on the interface: scroll
 *
 * Camera moves go to bardroid_touch.lua in the game through files (BAR's sandbox gives user widgets no sockets); the
 * widget answers through bardroid_hover.txt whether the pointer is over the game's interface and what is armed.
 */
final class RtsTouch {
    private static final long LONG_PRESS_MS = 450, MULTI_TAP_MS = 500;
    private static final float GHOST_MM = 10;                  // building ghost above the finger (touch-only)
    private static final float SCROLL_MM = 5;                  // two-finger travel per wheel click on the interface
    private static final long HOVER_WAIT_MS = 250;            // a drag waits this long at most for the widget's answer
    private static final long HOVER_STALE_MS = 3000;          // older answers: the widget is not running
    private static final long LOG_RESTART_BYTES = 256 * 1024;
    private static final double ZOOM_STEP = Math.log(1.12);   // one wheel click per 12% change in finger distance
    private static final float WHEEL_CLICK = 120;              // Termux:X11 scroll units per wheel click
    private static final double ROTATE_START = Math.toRadians(8);   // twist before the camera starts to turn
    private static final long FLING_FRAME_MS = 16;
    private static final float FLING_DECAY = 0.92f;            // velocity kept per fling frame

    private enum State { IDLE, PENDING, DRAG_WAIT, PAN, LEFT_DRAG, RIGHT_HOLD, MULTI_PENDING, TWO_FINGER, TILT, DONE,
                         BOX, GHOST, SCROLL, RADIAL }   // the last four: touch-only mode

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
    private FileOutputStream log;
    private long logBytes;
    private final TouchUiLink link;                 // touch-only mode: the HUD's requests; null when off
    private final boolean touchOnly;

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
    private float scrollAcc;                        // two-finger scroll on the interface, view pixels
    private float lastTapX = -1, lastTapY;          // X screen pixels
    private long lastTapTime;
    private float flingX, flingY, flingVx, flingVy; // view pixels, pixels per second
    private float radialX, radialY;                 // X screen pixels of the finger, last sent to the radial menu

    private final Runnable longPress = this::onLongPress;

    private void onLongPress() {
        if (state != State.PENDING) return;
        view().performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
        if (touchOnly && Boolean.FALSE.equals(overInterface(downX, downY))) {
            // press and hold on the map: the HUD's radial menu at the finger (slide to a choice, lift)
            state = State.RADIAL;
            radialX = toX(downX); radialY = toY(downY);
            send(String.format(Locale.US, "radial %.0f %.0f", radialX, radialY));
            return;
        }
        state = State.RIGHT_HOLD;
        press(downX, downY, InputStub.BUTTON_RIGHT, true);
    }

    /** The game has not said in time whether the drag started on its interface: pan. */
    private final Runnable hoverTimeout = () -> { if (state == State.DRAG_WAIT) startPan(); };

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
        link = Prefs.touchOnly ? new TouchUiLink(activity, widgetDir, io) : null;
        touchOnly = link != null;
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
     * The X screen changed size or the display its refresh rate (a foldable folded or unfolded): the widget resizes
     * the game window and keeps the frame cap (30 fps, or 60) at this refresh rate. The file stays, so a game that
     * is still loading picks it up too.
     */
    void screenSize(int w, int h, int refreshHz) {
        if (w <= 0 || h <= 0 || (w == screenW && h == screenH && refreshHz == hz)) return;
        Log.i("display", "X screen " + w + "x" + h + ", display " + refreshHz + " Hz");   // fold/unfold steps
        screenW = w; screenH = h; hz = refreshHz;
        int cap = Prefs.EMULATOR_BUILD ? 0 : Prefs.fps60 ? 60 : 30;   // 0: the widget leaves VSync alone
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
        ui.removeCallbacks(fling);
        if (link != null) link.close();
        io.post(() -> { try { if (log != null) log.close(); } catch (IOException ignored) {} });
        ioThread.quitSafely();
    }

    /** A mouse, keyboard or gamepad was used: the touch HUD steps aside until the next finger touch. */
    void otherInput(String kind) { if (link != null) link.inputUsed(kind); }

    /** Finger touches on the touchscreen are ours (and the rest of a gesture we started). */
    boolean handles(MotionEvent e) {
        if (state != State.IDLE && state != State.DONE) return true;
        return (Prefs.rtsTouch || touchOnly) && e.isFromSource(InputDevice.SOURCE_TOUCHSCREEN)
                && e.getToolType(e.getActionIndex()) == MotionEvent.TOOL_TYPE_FINGER;
    }

    /** @param e in the coordinates of the LorieView's parent (as Termux:X11's own listener gets it) */
    boolean onTouch(MotionEvent e) {
        if (velocity != null) velocity.addMovement(e);
        switch (e.getActionMasked()) {
            case MotionEvent.ACTION_DOWN: {
                cancelGesture();
                ui.removeCallbacks(fling);   // a touch stops a gliding map
                if (link != null) link.inputUsed("touch");   // the touch HUD comes back
                state = State.PENDING;
                firstId = e.getPointerId(0);
                downX = curX = e.getX(); downY = curY = e.getY();
                downTime = e.getEventTime();
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
                if (state == State.PENDING) {
                    ui.removeCallbacks(longPress);
                    state = State.MULTI_PENDING;
                } else if (state == State.RADIAL) {
                    send("radialcancel");   // a second finger: never mind
                    state = State.DONE;
                } else if (state == State.PAN || state == State.DRAG_WAIT || state == State.GHOST || state == State.BOX) {
                    ui.removeCallbacks(hoverTimeout);
                    if (state == State.BOX) send("boxcancel");
                    beginTwoFinger(e, State.TWO_FINGER);   // a second finger joins a pan: pinch/twist from here
                }
                break;
            }
            case MotionEvent.ACTION_MOVE:
                onMove(e);
                break;
            case MotionEvent.ACTION_POINTER_UP:
                if ((state == State.TWO_FINGER || state == State.TILT || state == State.SCROLL) && e.getPointerCount() <= 2)
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
                if (!secondTap) decideDrag(hover(downX, downY));
                else if (touchOnly && !Boolean.TRUE.equals(overInterface(downX, downY))) startBox();
                else startLeftDrag();
                return;
            }
            case DRAG_WAIT:
                decideDrag(hover(downX, downY));
                return;
            case PAN:
                panTo(curX, curY);
                return;
            case LEFT_DRAG:
            case RIGHT_HOLD:
                if (i >= 0) moveCursor(curX, curY);
                return;
            case BOX:
                if (i >= 0) { moveCursor(curX, curY); sendBox("box"); }
                return;
            case GHOST:
                if (i >= 0) moveCursor(curX, curY - ghostOffset());
                return;
            case RADIAL: {
                float x = toX(curX), y = toY(curY);
                if (i >= 0 && (Math.abs(x - radialX) >= 1 || Math.abs(y - radialY) >= 1)) {
                    radialX = x; radialY = y;
                    send(String.format(Locale.US, "radialmove %.0f %.0f", x, y));
                }
                return;
            }
            case MULTI_PENDING: {
                if (e.getPointerCount() < 2 || !movedPastSlop(e)) return;
                if (touchOnly && Boolean.TRUE.equals(overInterface(downX, downY))) beginTwoFinger(e, State.SCROLL);
                else beginTwoFinger(e, isTilt(e) ? State.TILT : State.TWO_FINGER);
                return;
            }
            case SCROLL: {
                int a = e.findPointerIndex(idA), b = e.findPointerIndex(idB);
                if (a < 0 || b < 0) return;
                float cx = (e.getX(a) + e.getX(b)) / 2, cy = (e.getY(a) + e.getY(b)) / 2;
                float step = SCROLL_MM * link.viewPxPerMm();
                scrollAcc += cy - lastCy;
                while (scrollAcc >= step) { wheel(cx, cy, -WHEEL_CLICK); scrollAcc -= step; }   // fingers down: scroll up
                while (scrollAcc <= -step) { wheel(cx, cy, WHEEL_CLICK); scrollAcc += step; }
                lastCx = cx; lastCy = cy;
                return;
            }
            case TWO_FINGER: {
                int a = e.findPointerIndex(idA), b = e.findPointerIndex(idB);
                if (a < 0 || b < 0) return;
                float cx = (e.getX(a) + e.getX(b)) / 2, cy = (e.getY(a) + e.getY(b)) / 2, d = dist(e, a, b);
                if (cx != lastCx || cy != lastCy) sendPan(lastCx, lastCy, cx, cy);
                if (touchOnly && lastDist > 0 && d > 0 && d != lastDist) {
                    // a camera line, not the wheel: a latched Shift/Ctrl turns the wheel into fast zoom / tilt
                    send(String.format(Locale.US, "zoom %.5f %.1f %.1f", d / lastDist, toX(cx), toY(cy)));
                } else if (!touchOnly && lastDist > 0 && d > 0) {
                    zoomAcc += Math.log(d / lastDist);
                    while (zoomAcc >= ZOOM_STEP) { wheel(cx, cy, -WHEEL_CLICK); zoomAcc -= ZOOM_STEP; }   // spread: zoom in
                    while (zoomAcc <= -ZOOM_STEP) { wheel(cx, cy, WHEEL_CLICK); zoomAcc += ZOOM_STEP; }   // pinch: zoom out
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
        curX = e.getX(); curY = e.getY();
        switch (state) {
            case PENDING:
                tap(downX, downY);
                break;
            case DRAG_WAIT:
                if (Boolean.TRUE.equals(overInterface(downX, downY))) {   // a quick drag on the interface
                    press(downX, downY, InputStub.BUTTON_LEFT, true);
                    press(curX, curY, InputStub.BUTTON_LEFT, false);
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
                break;
            case RIGHT_HOLD:
                press(curX, curY, InputStub.BUTTON_RIGHT, false);
                break;
            case BOX:
                sendBox("boxend");
                break;
            case RADIAL:
                send(String.format(Locale.US, "radialup %.0f %.0f", toX(curX), toY(curY)));
                break;
            case GHOST: {   // place the building where its ghost is
                float y = curY - ghostOffset();
                press(curX, y, InputStub.BUTTON_LEFT, true);
                press(curX, y, InputStub.BUTTON_LEFT, false);
                break;
            }
            case MULTI_PENDING:
                if (e.getEventTime() - downTime <= MULTI_TAP_MS) {
                    if (maxFingers == 2 && touchOnly) {
                        send("cancel");   // the HUD: disarm the command or building, else deselect (phone RTS "back")
                    } else if (maxFingers == 2) {
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
        if (velocity != null) { velocity.recycle(); velocity = null; }
        io.post(() -> { if (logBytes > LOG_RESTART_BYTES) restartLog(); });   // between gestures only
    }

    private void cancelGesture() {
        ui.removeCallbacks(longPress);
        ui.removeCallbacks(hoverTimeout);
        if (state == State.LEFT_DRAG) press(downX, downY, InputStub.BUTTON_LEFT, false);
        if (state == State.RIGHT_HOLD) press(downX, downY, InputStub.BUTTON_RIGHT, false);
        if (state == State.BOX) send("boxcancel");
        if (state == State.RADIAL) send("radialcancel");
        state = State.IDLE;
    }

    /**
     * A one-finger drag: a left drag where it started on the game's interface, else a pan; null = not known yet.
     * Touch-only mode, on the map: box select with BOX latched; with a command armed a left drag (formation line,
     * area circle, a line of buildings with QUEUE), with a building armed and QUEUE off the ghost follows the finger.
     */
    private void decideDrag(int[] hover) {
        if (hover == null) {
            if (state != State.DRAG_WAIT) {
                state = State.DRAG_WAIT;
                ui.postDelayed(hoverTimeout, HOVER_WAIT_MS);
            }
            return;
        }
        ui.removeCallbacks(hoverTimeout);
        int armed = hover[1];
        if (hover[0] == 1) startLeftDrag();
        else if (!touchOnly) startPan();
        else if (link.boxSelect()) startBox();
        else if (armed == ARMED_OTHER || (armed == ARMED_BUILD && link.shift())) startLeftDrag();
        else if (armed == ARMED_BUILD) startGhost();
        else startPan();
    }

    private void startBox() {
        state = State.BOX;
        if (secondTap) lastTapX = -1;
        moveCursor(curX, curY);
        sendBox("box");
    }

    /** The selection box from the touch's start to the finger, for the HUD (X screen pixels). */
    private void sendBox(String kind) {
        send(String.format(Locale.US, "%s %.0f %.0f %.0f %.0f", kind, toX(downX), toY(downY), toX(curX), toY(curY)));
    }

    private void startGhost() {
        state = State.GHOST;
        moveCursor(curX, curY - ghostOffset());
    }

    /** The building ghost floats this far (view pixels) above the finger, where the finger does not hide it. */
    private float ghostOffset() { return GHOST_MM * link.viewPxPerMm(); }

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
        zoomAcc = 0; rotateAcc = 0; rotating = false; scrollAcc = 0;
    }

    /** Both fingers moving up or down together, side by side: a tilt (as in map apps), not a pan. */
    private boolean isTilt(MotionEvent e) {
        float[] sa = starts.get(e.getPointerId(0)), sb = starts.get(e.getPointerId(1));
        if (sa == null || sb == null) return false;
        float ax = e.getX(0) - sa[0], ay = e.getY(0) - sa[1], bx = e.getX(1) - sb[0], by = e.getY(1) - sb[1];
        boolean sideBySide = Math.abs(sa[0] - sb[0]) > Math.abs(sa[1] - sb[1]);
        return sideBySide && Math.signum(ay) == Math.signum(by) && Math.abs(ay) > slop / 2 && Math.abs(by) > slop / 2
                && Math.abs(ay) > 2 * Math.abs(ax) && Math.abs(by) > 2 * Math.abs(bx);
    }

    private boolean nearLastTap(float x, float y) {
        float tol = slop * 2 * xPerViewPixel();
        return lastTapX >= 0 && SystemClock.uptimeMillis() - lastTapTime <= doubleTapMs
                && Math.abs(x - lastTapX) <= tol && Math.abs(y - lastTapY) <= tol;
    }

    private void tap(float vx, float vy) {
        float x = toX(vx), y = toY(vy);
        // A double click needs both clicks on the same pixel; fingers land a few pixels apart.
        if (nearLastTap(x, y)) {
            x = lastTapX; y = lastTapY;
            lastTapX = -1;
        } else {
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

    /** Appends one line to the touch log (the widget reads complete lines each frame). */
    private void send(String msg) {
        byte[] data = (msg + "\n").getBytes(StandardCharsets.US_ASCII);
        io.post(() -> {
            if (log == null) return;
            try { log.write(data); logBytes += data.length; } catch (IOException e) { Log.e("touch", "touch log", e); }
        });
    }

    private static final int ARMED_BUILD = 1, ARMED_OTHER = 2;   // hover()[1]; 0 = no command armed

    /**
     * The widget's last answer for view pixel (x, y): {1 if the game's interface (or the minimap) is there else 0,
     * the armed command: 0 none, ARMED_BUILD, ARMED_OTHER}; null while it has not answered for that point. The answer
     * is "x y 0|1 cmd" in X screen pixels, written when the pointer moves and every second. Without a widget (the
     * lobby, a game still loading) everything is interface: drags stay mouse drags.
     */
    private int[] hover(float vx, float vy) {
        if (System.currentTimeMillis() - hoverFile.lastModified() > HOVER_STALE_MS) return new int[]{1, 0};
        byte[] b = new byte[64];
        int n;
        try (FileInputStream in = new FileInputStream(hoverFile)) { n = in.read(b); } catch (IOException e) { return null; }
        if (n <= 0) return null;
        String[] f = new String(b, 0, n, StandardCharsets.US_ASCII).trim().split(" ");
        if (f.length < 3) return null;
        try {
            if (Math.abs(Integer.parseInt(f[0]) - toX(vx)) > 2 || Math.abs(Integer.parseInt(f[1]) - toY(vy)) > 2) return null;
            return new int[]{f[2].equals("1") ? 1 : 0, f.length > 3 ? Integer.parseInt(f[3]) : 0};
        } catch (NumberFormatException e) { return null; }
    }

    /** Whether the game's interface is under view pixel (x, y); null = not known yet (see {@link #hover}). */
    private Boolean overInterface(float vx, float vy) {
        int[] h = hover(vx, vy);
        return h == null ? null : h[0] == 1;
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
