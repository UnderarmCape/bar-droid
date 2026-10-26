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
 *   two fingers          move = pan, pinch = zoom about the pinch (in the lobby: the mouse wheel, which scrolls),
 *                        twist = rotate the camera
 *   two fingers up/down  tilt the camera (both fingers moving the same way, side by side)
 *   three-finger tap     show / hide the keyboard
 * The X pointer is hidden while two or more fingers are down.
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

    private enum State { IDLE, PENDING, DRAG_WAIT, PAN, LEFT_DRAG, RIGHT_HOLD, MULTI_PENDING, TWO_FINGER, TILT, DONE }

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
    private float flingX, flingY, flingVx, flingVy; // view pixels, pixels per second
    private boolean cursorHidden;

    private final Runnable longPress = () -> {
        if (state != State.PENDING) return;
        state = State.RIGHT_HOLD;
        view().performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
        press(downX, downY, InputStub.BUTTON_RIGHT, true);
    };

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
        ui.removeCallbacks(fling);
        ui.removeCallbacks(longPress);
        ui.removeCallbacks(hoverTimeout);
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
                cancelGesture();
                ui.removeCallbacks(fling);   // a touch stops a gliding map
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
                showCursor(false);   // Kailil: the pointer flickering between two fingers looked broken
                if (state == State.PENDING) {
                    ui.removeCallbacks(longPress);
                    state = State.MULTI_PENDING;
                } else if (state == State.PAN || state == State.DRAG_WAIT) {
                    ui.removeCallbacks(hoverTimeout);
                    beginTwoFinger(e, State.TWO_FINGER);   // a second finger joins a pan: pinch/twist from here
                }
                break;
            }
            case MotionEvent.ACTION_MOVE:
                onMove(e);
                break;
            case MotionEvent.ACTION_POINTER_UP:
                if ((state == State.TWO_FINGER || state == State.TILT) && e.getPointerCount() <= 2)
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
                if (secondTap) startLeftDrag();
                else decideDrag(overInterface(downX, downY));
                return;
            }
            case DRAG_WAIT:
                decideDrag(overInterface(downX, downY));
                return;
            case PAN:
                panTo(curX, curY);
                return;
            case LEFT_DRAG:
            case RIGHT_HOLD:
                if (i >= 0) moveCursor(curX, curY);
                return;
            case MULTI_PENDING: {
                if (e.getPointerCount() < 2 || !movedPastSlop(e)) return;
                beginTwoFinger(e, isTilt(e) ? State.TILT : State.TWO_FINGER);
                return;
            }
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
            case MULTI_PENDING:
                if (e.getEventTime() - downTime <= MULTI_TAP_MS) {
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
        if (state == State.LEFT_DRAG) press(downX, downY, InputStub.BUTTON_LEFT, false);
        if (state == State.RIGHT_HOLD) press(downX, downY, InputStub.BUTTON_RIGHT, false);
        state = State.IDLE;
        showCursor(true);
    }

    /** The X pointer is hidden while two or more fingers are down. */
    private void showCursor(boolean visible) {
        if (cursorHidden == !visible) return;
        cursorHidden = !visible;
        view().setCursorVisible(visible);
    }

    /** A one-finger drag: a left drag where it started on the game's interface, else a pan; null = not known yet. */
    private void decideDrag(Boolean onInterface) {
        if (onInterface == null) {
            if (state != State.DRAG_WAIT) {
                state = State.DRAG_WAIT;
                ui.postDelayed(hoverTimeout, HOVER_WAIT_MS);
            }
            return;
        }
        ui.removeCallbacks(hoverTimeout);
        if (onInterface) startLeftDrag();
        else startPan();
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

    /** The gamepad camera's stick state (ControllerBridge, any thread): the widget moves the camera every frame. */
    void padLine(String line) { send(line); }

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
     * Whether the game's interface (or the minimap) is under view pixel (x, y), from the widget's last answer
     * ("x y 0|1" in X screen pixels, written when the pointer moves and every second); null while it has not
     * answered for that point. Without a widget (the lobby, a game still loading) everything is interface: drags
     * stay mouse drags.
     */
    private Boolean overInterface(float vx, float vy) {
        if (System.currentTimeMillis() - hoverFile.lastModified() > HOVER_STALE_MS) return Boolean.TRUE;
        byte[] b = new byte[64];
        int n;
        try (FileInputStream in = new FileInputStream(hoverFile)) { n = in.read(b); } catch (IOException e) { return null; }
        if (n <= 0) return null;
        String[] f = new String(b, 0, n, StandardCharsets.US_ASCII).trim().split(" ");
        if (f.length != 3) return null;
        try {
            if (Math.abs(Integer.parseInt(f[0]) - toX(vx)) > 2 || Math.abs(Integer.parseInt(f[1]) - toY(vy)) > 2) return null;
            return f[2].equals("1");
        } catch (NumberFormatException e) { return null; }
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
