package com.underarmcape.bardroid;

import android.content.Context;
import android.hardware.input.InputManager;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

/**
 * The app is the controller companion of Kailil's controller build (BAR Controller Support v0.8.5, the singleplayer
 * game): Android gamepad events become the BARCTRL1 UDP packets its luaui/Widgets/controller_socket_bridge.lua reads,
 * exactly as the Windows companion sends them in its v0.8.5 ("--codex") mode:
 *
 *   BARCTRL1|seq|connected|leftX|leftY|rightX|rightY|leftTrigger|rightTrigger|buttons
 *
 * raw axes -32768..32767 (Y down-positive; v0.8.5 applies its own deadzones), triggers 0..32767, buttons a 21-char
 * string of 0/1 in SDL order, no Guide. Packets go to 127.0.0.1:28777 (proot shares the network namespace). They flow
 * from the moment the game screen opens, a pad or not, so v0.8.5 never sees its companion missing; without changes a
 * packet goes out every 100 ms (v0.8.5 takes the stream for gone after 250 ms), which costs the game next to nothing.
 *
 * BAR's released game (online, spectating) has no v0.8.5: there the sticks drive the camera through
 * bardroid_touch.lua ({@link CameraSink}, "pad" lines, sent only when the sticks change).
 *
 * Where no game runs (the lobby, a loading screen) the pad is a mouse ({@link Mouse}, Kailil 2026-10-26: "just simple
 * mouse movement, scroll and A and B as left and right click"): the left stick moves the pointer, the right stick
 * scrolls, A and B are the left and right buttons.
 */
public final class ControllerBridge {
    // SDL GameController button order, as the Windows companion sends it:
    // 0 A, 1 B, 2 X, 3 Y, 4 Back, 5 Guide, 6 Start, 7 LeftStick, 8 RightStick, 9 LB, 10 RB,
    // 11 DPadUp, 12 DPadDown, 13 DPadLeft, 14 DPadRight, 15..20 misc/paddles (unused). 21 chars total.
    public static final int BTN_A = 0, BTN_B = 1, BTN_X = 2, BTN_Y = 3, BTN_BACK = 4, BTN_GUIDE = 5, BTN_START = 6,
            BTN_LS = 7, BTN_RS = 8, BTN_LB = 9, BTN_RB = 10,
            BTN_DPAD_UP = 11, BTN_DPAD_DOWN = 12, BTN_DPAD_LEFT = 13, BTN_DPAD_RIGHT = 14;
    public static final int BUTTON_COUNT = 21;
    private static final int IGNORED = -2;            // a pad key that is consumed but not sent (Guide, as v0.8.5 mode)
    private static final long TICK_MS = 16, HEARTBEAT_MS = 100, CAMERA_MS = 33;
    private static final int STICK_DEADZONE = 5000, TRIGGER_DEADZONE = 3000;   // v0.8.5's defaults

    /** Receives "pad lx ly rx ry lt lb" lines for the camera widget. */
    public interface CameraSink { void padLine(String line); }

    /** The X pointer, for screens without a game. Called on the pump thread. */
    public interface Mouse {
        boolean active();                       // no game widget answers: the lobby or a loading screen
        float pixelsPerSecond();                // pointer speed at full stick
        void move(int dx, int dy);              // relative, X screen pixels
        void button(boolean left, boolean down);
        void wheel(float dy);                   // Termux:X11 scroll units, 120 per click, > 0 scrolls down
    }
    private static final float MOUSE_CURVE = 2f, SCROLL_CLICKS_PER_SECOND = 10f;
    private static final long MOUSE_CHECK_MS = 250;

    private final int port;
    private final CameraSink camera;
    private Mouse mouse;
    // pointer state, pump thread only
    private boolean mouseOn, leftDown, rightDown;
    private long mouseCheckAt, lastMouseTick;
    private float fracX, fracY, scrollAcc;
    // presses shorter than a pump tick still click (main thread sets, pump thread clears; guarded by this)
    private boolean aPressed, bPressed;
    private final InputManager inputs;
    private final Handler main = new Handler(Looper.getMainLooper());
    private DatagramSocket socket;
    private InetAddress loopback;
    private long seq;
    // pad state: written on the main thread, read by the pump (guarded by this)
    private final boolean[] buttons = new boolean[BUTTON_COUNT];
    private int lx, ly, rx, ry, lt, rt;
    private boolean connected, dirty;
    private boolean idle;   // the pump sleeps the heartbeat out (no pad); guarded by this
    private Thread pump;
    private volatile boolean running;

    private final InputManager.InputDeviceListener devices = new InputManager.InputDeviceListener() {
        @Override public void onInputDeviceAdded(int id) { updateConnected(); }
        @Override public void onInputDeviceRemoved(int id) { updateConnected(); }
        @Override public void onInputDeviceChanged(int id) { updateConnected(); }
    };

    public ControllerBridge(Context ctx, int port, CameraSink camera) {
        this.port = port;
        this.camera = camera;
        this.inputs = ctx.getSystemService(InputManager.class);
    }

    /** Before {@link #start}. */
    public void setMouse(Mouse mouse) { this.mouse = mouse; }

    public synchronized void start() {
        if (running) return;
        try {
            socket = new DatagramSocket();
            loopback = InetAddress.getByName("127.0.0.1");
        } catch (IOException e) { Log.e("pad", "udp socket", e); return; }
        if (inputs != null) inputs.registerInputDeviceListener(devices, main);
        updateConnected();
        running = true;
        pump = new Thread(this::run, "pad-pump");
        pump.setDaemon(true);
        pump.start();
        Log.i("pad", "controller bridge sending to 127.0.0.1:" + port + (connected ? " (pad connected)" : " (no pad yet)"));
    }

    public synchronized void stop() {
        running = false;
        if (inputs != null) inputs.unregisterInputDeviceListener(devices);
        if (pump != null) pump.interrupt();
        if (socket != null) socket.close();
    }

    /** The screen lost input (paused, picture-in-picture): no button stays held. */
    public synchronized void release() {
        java.util.Arrays.fill(buttons, false);
        lx = ly = rx = ry = lt = rt = 0;
        dirty = true;
        wakeIdle();
    }

    public static boolean isGamepad(InputDevice d) {
        if (d == null || d.isVirtual()) return false;
        int s = d.getSources();
        return (s & InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD || (s & InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK;
    }

    private void updateConnected() {
        boolean any = false;
        for (int id : InputDevice.getDeviceIds()) if (isGamepad(InputDevice.getDevice(id))) { any = true; break; }
        synchronized (this) {
            if (any == connected) return;
            if (!any) release();
            connected = any;
            dirty = true;
            wakeIdle();
        }
        Log.i("pad", any ? "gamepad connected" : "gamepad disconnected");
    }

    /** @return true if the event was a gamepad event and has been consumed. */
    public boolean onMotion(MotionEvent e) {
        if (!e.isFromSource(InputDevice.SOURCE_JOYSTICK) && !e.isFromSource(InputDevice.SOURCE_GAMEPAD)) return false;
        synchronized (this) {
            connected = true;
            lx = axis(e, MotionEvent.AXIS_X); ly = axis(e, MotionEvent.AXIS_Y);
            rx = axis(e, MotionEvent.AXIS_Z); ry = axis(e, MotionEvent.AXIS_RZ);
            lt = trigger(e, MotionEvent.AXIS_LTRIGGER, MotionEvent.AXIS_BRAKE);
            rt = trigger(e, MotionEvent.AXIS_RTRIGGER, MotionEvent.AXIS_GAS);
            // Only a pad with a hat reports its D-pad here; others send DPAD keys, which a stick move must not clear.
            InputDevice d = e.getDevice();
            if (d == null || d.getMotionRange(MotionEvent.AXIS_HAT_X) != null) {
                float hx = e.getAxisValue(MotionEvent.AXIS_HAT_X), hy = e.getAxisValue(MotionEvent.AXIS_HAT_Y);
                buttons[BTN_DPAD_LEFT] = hx < -0.5f; buttons[BTN_DPAD_RIGHT] = hx > 0.5f;
                buttons[BTN_DPAD_UP] = hy < -0.5f; buttons[BTN_DPAD_DOWN] = hy > 0.5f;
            }
            dirty = true;
            wakeIdle();
        }
        return true;
    }

    /** @return true if the key belongs to a gamepad and has been consumed. */
    public boolean onKey(KeyEvent e) {
        int idx = map(e.getKeyCode());
        boolean fromPad = isGamepad(e.getDevice()) || KeyEvent.isGamepadButton(e.getKeyCode());
        if (idx == -1 || !fromPad) return false;
        if (idx == IGNORED) return true;
        synchronized (this) {
            connected = true;
            boolean down = e.getAction() == KeyEvent.ACTION_DOWN;
            buttons[idx] = down;
            if (down && idx == BTN_A) aPressed = true;
            if (down && idx == BTN_B) bPressed = true;
            dirty = true;
            wakeIdle();
        }
        return true;
    }

    private static int map(int keyCode) {
        switch (keyCode) {
            case KeyEvent.KEYCODE_BUTTON_A: return BTN_A;
            case KeyEvent.KEYCODE_BUTTON_B: return BTN_B;
            case KeyEvent.KEYCODE_BUTTON_X: return BTN_X;
            case KeyEvent.KEYCODE_BUTTON_Y: return BTN_Y;
            case KeyEvent.KEYCODE_BUTTON_L1: return BTN_LB;
            case KeyEvent.KEYCODE_BUTTON_R1: return BTN_RB;
            case KeyEvent.KEYCODE_BUTTON_THUMBL: return BTN_LS;
            case KeyEvent.KEYCODE_BUTTON_THUMBR: return BTN_RS;
            case KeyEvent.KEYCODE_BUTTON_START: return BTN_START;
            case KeyEvent.KEYCODE_BUTTON_SELECT: return BTN_BACK;
            case KeyEvent.KEYCODE_BUTTON_MODE: return IGNORED;   // the v0.8.5 companion never reports Guide
            case KeyEvent.KEYCODE_DPAD_UP: return BTN_DPAD_UP;
            case KeyEvent.KEYCODE_DPAD_DOWN: return BTN_DPAD_DOWN;
            case KeyEvent.KEYCODE_DPAD_LEFT: return BTN_DPAD_LEFT;
            case KeyEvent.KEYCODE_DPAD_RIGHT: return BTN_DPAD_RIGHT;
            default: return -1;
        }
    }

    private static int axis(MotionEvent e, int axis) {
        return Math.max(-32768, Math.min(32767, Math.round(e.getAxisValue(axis) * 32767)));
    }
    private static int trigger(MotionEvent e, int a, int b) {
        float v = Math.max(e.getAxisValue(a), e.getAxisValue(b));
        return Math.max(0, Math.min(32767, Math.round(v * 32767)));
    }

    private void run() {
        long lastSend = 0, lastCamera = 0;
        String cameraSent = "pad 0 0 0 0 0 0";
        while (running) {
            long now = SystemClock.uptimeMillis();
            String packet = null, cameraLine = null;
            synchronized (this) {
                if (dirty || now - lastSend >= HEARTBEAT_MS) { packet = packet(); dirty = false; }
                if (camera != null && now - lastCamera >= CAMERA_MS) cameraLine = cameraLine();
            }
            if (packet != null) {
                byte[] data = packet.getBytes(StandardCharsets.US_ASCII);
                try { socket.send(new DatagramPacket(data, data.length, loopback, port)); } catch (IOException ignored) {}
                lastSend = now;
            }
            if (mouse != null) mouseTick(now);
            if (cameraLine != null && !mouseOn && !cameraLine.equals(cameraSent)) {
                camera.padLine(cameraLine);
                cameraSent = cameraLine;
                lastCamera = now;
            }
            // No pad: only the heartbeat is due, so the thread wakes 10 times a second instead of 60 (a pad that
            // connects or sends an event wakes it at once)
            try {
                synchronized (this) {
                    if (connected || dirty) wait(TICK_MS);
                    else { idle = true; wait(HEARTBEAT_MS); idle = false; }
                }
            } catch (InterruptedException e) { break; }
        }
    }

    /** Called with the lock held whenever the pad state changes: ends the pump's idle sleep. */
    private void wakeIdle() { if (idle) notifyAll(); }

    private void mouseTick(long now) {
        if (now >= mouseCheckAt) {
            boolean on = mouse.active();
            if (on != mouseOn) Log.i("pad", on ? "pad mouse on (no game running)" : "pad mouse off (a game runs)");
            mouseOn = on;
            mouseCheckAt = now + MOUSE_CHECK_MS;
        }
        float dt = lastMouseTick == 0 ? 0 : Math.min(0.1f, (now - lastMouseTick) / 1000f);
        lastMouseTick = now;
        boolean a, b, aTap, bTap;
        float x, y, scroll;
        synchronized (this) {
            a = buttons[BTN_A]; b = buttons[BTN_B]; aTap = aPressed; bTap = bPressed;
            aPressed = bPressed = false;
            x = stick(lx); y = stick(ly); scroll = stick(ry);
        }
        if (!mouseOn) { a = b = aTap = bTap = false; x = y = scroll = 0; }
        if ((a || aTap) && !leftDown) { leftDown = true; mouse.button(true, true); }
        if (!a && leftDown) { leftDown = false; mouse.button(true, false); }
        if ((b || bTap) && !rightDown) { rightDown = true; mouse.button(false, true); }
        if (!b && rightDown) { rightDown = false; mouse.button(false, false); }
        if (x != 0 || y != 0) {
            float step = mouse.pixelsPerSecond() * dt;
            fracX += x * step; fracY += y * step;
            int ix = (int) fracX, iy = (int) fracY;
            fracX -= ix; fracY -= iy;
            if (ix != 0 || iy != 0) mouse.move(ix, iy);
        } else {
            fracX = fracY = 0;
        }
        if (scroll != 0) {   // stick up scrolls up
            scrollAcc += scroll * SCROLL_CLICKS_PER_SECOND * dt;
            while (scrollAcc >= 1) { mouse.wheel(120); scrollAcc -= 1; }
            while (scrollAcc <= -1) { mouse.wheel(-120); scrollAcc += 1; }
        } else {
            scrollAcc = 0;
        }
    }

    /** -1..1 past v0.8.5's deadzone, squared for fine control near the centre. */
    private static float stick(int raw) {
        float m = Math.abs(raw);
        if (m < STICK_DEADZONE) return 0;
        float n = (float) Math.pow(Math.min(1f, (m - STICK_DEADZONE) / (32767f - STICK_DEADZONE)), MOUSE_CURVE);
        return raw < 0 ? -n : n;
    }

    private String packet() {
        int c = connected ? 1 : 0;
        StringBuilder sb = new StringBuilder(96);
        sb.append("BARCTRL1|").append(seq++ & 0xffffffffL).append('|').append(c)
          .append('|').append(c * lx).append('|').append(c * ly)    // Android Y is down-positive, as the protocol
          .append('|').append(c * rx).append('|').append(c * ry)
          .append('|').append(c * lt).append('|').append(c * rt).append('|');
        for (boolean b : buttons) sb.append(connected && b ? '1' : '0');
        return sb.toString();
    }

    /**
     * Sticks inside v0.8.5's deadzones count as centred and the rest moves in steps of 256 (of 32767), so a resting
     * or steadily held pad sends no camera lines.
     */
    private String cameraLine() {
        return String.format(Locale.US, "pad %d %d %d %d %d %d", dead(lx, STICK_DEADZONE), dead(ly, STICK_DEADZONE),
                dead(rx, STICK_DEADZONE), dead(ry, STICK_DEADZONE), dead(lt, TRIGGER_DEADZONE), buttons[BTN_LB] ? 1 : 0);
    }
    private static int dead(int v, int deadzone) { return Math.abs(v) < deadzone ? 0 : v / 256 * 256; }
}
