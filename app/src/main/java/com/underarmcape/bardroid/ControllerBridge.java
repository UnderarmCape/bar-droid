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
 * BAR's released game (online, spectating) has no v0.8.5 (BAR's sandbox keeps it out: docs/HISTORY.md, 2026-10-28):
 * there the pad is a mouse and keyboard, one button one input, as Steam Input is on a PC (Kailil, 2026-10-28, yes to
 * that plan), which no lobby setting or widget rule can see or block:
 *
 *   left stick   the pointer (slower over the interface; LT held: fine aim)
 *   right stick  pans the camera; with LB held, turns (x) and zooms (y)   (bardroid_touch.lua, "pad" lines)
 *   A / B        left / right mouse button (held: box select or a build line / a formation)
 *   RT held      Shift (queue)          LB held  Ctrl (LB + D-pad: Ctrl+1..4, assign a group)
 *   D-pad        1, 2, 3, 4 (up, right, down, left: control groups)
 *   Back         Escape                 Start    F10 (BAR's options)
 *   X            attack-move (fight; A places it)        Y  the next idle builder
 *   LS click     select all              RS click  the whole map / back
 *
 * Where no game runs (the lobby, a loading screen) the pad is a simpler mouse ({@link Mouse}, Kailil 2026-10-26: "just
 * simple mouse movement, scroll and A and B as left and right click"): the left stick moves the pointer, the right
 * stick scrolls, A and B are the left and right buttons. In the controller game v0.8.5 reads the packets and the pad
 * is neither.
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

    /** The X pointer and keyboard. Called on the pump thread. */
    public interface Mouse {
        int mode();                             // MODE_LOBBY, MODE_GAME or MODE_OFF
        float pixelsPerSecond();                // pointer speed at full stick
        boolean onInterface();                  // the pointer is over the game's interface (the game's last answer)
        void move(int dx, int dy);              // relative, X screen pixels
        void button(boolean left, boolean down);
        void wheel(float dy);                   // Termux:X11 scroll units, 120 per click, > 0 scrolls down
        void key(int keyCode, boolean down);    // an Android key code, as a keyboard key
        void act(String name);                  // a game action (bardroid_touch.lua ACTIONS)
    }
    /** No game widget answers (the lobby, a loading screen) / BAR's released game / the controller game (v0.8.5). */
    public static final int MODE_LOBBY = 0, MODE_GAME = 1, MODE_OFF = 2;
    private static final float MOUSE_CURVE = 2f, SCROLL_CLICKS_PER_SECOND = 10f;
    private static final float FINE_AIM = 0.35f, ON_INTERFACE = 0.6f;   // pointer speed factors in a game
    private static final int TRIGGER_HELD = 16000;                    // RT past this: Shift held
    private static final long MOUSE_CHECK_MS = 250;
    /** In a game: the buttons held as keys (button index, Android key code) and the ones that send an action. */
    private static final int[][] GAME_KEYS = {
            { BTN_LB, KeyEvent.KEYCODE_CTRL_LEFT },
            { BTN_DPAD_UP, KeyEvent.KEYCODE_1 }, { BTN_DPAD_RIGHT, KeyEvent.KEYCODE_2 },
            { BTN_DPAD_DOWN, KeyEvent.KEYCODE_3 }, { BTN_DPAD_LEFT, KeyEvent.KEYCODE_4 },
            { BTN_BACK, KeyEvent.KEYCODE_ESCAPE }, { BTN_START, KeyEvent.KEYCODE_F10 },
    };
    private static final String[] GAME_ACTS = new String[BUTTON_COUNT];
    static {
        GAME_ACTS[BTN_X] = "fight";
        GAME_ACTS[BTN_Y] = "idle_next";
        GAME_ACTS[BTN_LS] = "select_all";
        GAME_ACTS[BTN_RS] = "overview";
    }

    private final int port;
    private final CameraSink camera;
    private Mouse mouse;
    // pointer and key state, pump thread only
    private int mode = MODE_OFF;
    private boolean leftDown, rightDown, shiftHeld;
    private final boolean[] keysHeld = new boolean[GAME_KEYS.length];
    private long mouseCheckAt, lastMouseTick;
    private float fracX, fracY, scrollAcc;
    // presses shorter than a pump tick still count (main thread sets, pump thread clears; guarded by this)
    private final boolean[] pressed = new boolean[BUTTON_COUNT];
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
            if (down && !buttons[idx]) pressed[idx] = true;   // (not on key repeats)
            buttons[idx] = down;
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
                if (camera != null && now - lastCamera >= CAMERA_MS) cameraLine = cameraLine(mode == MODE_GAME);
            }
            if (packet != null) {
                byte[] data = packet.getBytes(StandardCharsets.US_ASCII);
                try { socket.send(new DatagramPacket(data, data.length, loopback, port)); } catch (IOException ignored) {}
                lastSend = now;
            }
            if (mouse != null) mouseTick(now);
            if (cameraLine != null && mode != MODE_LOBBY && !cameraLine.equals(cameraSent)) {
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
            int m = mouse.mode();
            if (m != mode) {
                Log.i("pad", m == MODE_LOBBY ? "pad mouse on (no game running)"
                        : m == MODE_GAME ? "pad mouse and keys on (BAR's game)" : "pad mouse off (the controller game)");
                releaseAll();   // nothing stays held across a change
            }
            mode = m;
            mouseCheckAt = now + MOUSE_CHECK_MS;
        }
        float dt = lastMouseTick == 0 ? 0 : Math.min(0.1f, (now - lastMouseTick) / 1000f);
        lastMouseTick = now;
        boolean[] held = new boolean[BUTTON_COUNT], tapped = new boolean[BUTTON_COUNT];
        boolean rtHeld, fine;
        float x, y, scroll;
        synchronized (this) {
            System.arraycopy(buttons, 0, held, 0, BUTTON_COUNT);
            System.arraycopy(pressed, 0, tapped, 0, BUTTON_COUNT);
            java.util.Arrays.fill(pressed, false);
            x = stick(lx); y = stick(ly); scroll = stick(ry);
            rtHeld = rt > TRIGGER_HELD;
            fine = lt > TRIGGER_DEADZONE;
        }
        if (mode == MODE_OFF) return;
        boolean a = held[BTN_A], b = held[BTN_B];
        if ((a || tapped[BTN_A]) && !leftDown) { leftDown = true; mouse.button(true, true); }
        if (!a && leftDown) { leftDown = false; mouse.button(true, false); }
        if ((b || tapped[BTN_B]) && !rightDown) { rightDown = true; mouse.button(false, true); }
        if (!b && rightDown) { rightDown = false; mouse.button(false, false); }
        if (mode == MODE_GAME) {
            gameKeys(held, tapped, rtHeld);
            scroll = 0;   // the right stick moves the camera
        }
        if (x != 0 || y != 0) {
            float step = mouse.pixelsPerSecond() * dt;
            if (mode == MODE_GAME) step *= (fine ? FINE_AIM : 1f) * (mouse.onInterface() ? ON_INTERFACE : 1f);
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

    /** BAR's game: the buttons that are keys (held as long as the button) and the ones that send an action. */
    private void gameKeys(boolean[] held, boolean[] tapped, boolean rtHeld) {
        if (rtHeld != shiftHeld) { shiftHeld = rtHeld; mouse.key(KeyEvent.KEYCODE_SHIFT_LEFT, rtHeld); }
        for (int i = 0; i < GAME_KEYS.length; i++) {
            int button = GAME_KEYS[i][0], key = GAME_KEYS[i][1];
            if ((held[button] || tapped[button]) && !keysHeld[i]) { keysHeld[i] = true; mouse.key(key, true); }
            if (!held[button] && keysHeld[i]) { keysHeld[i] = false; mouse.key(key, false); }
        }
        for (int i = 0; i < BUTTON_COUNT; i++) if (tapped[i] && GAME_ACTS[i] != null) mouse.act(GAME_ACTS[i]);
    }

    /** Lets go of every mouse button and key the pad holds. Pump thread. */
    private void releaseAll() {
        if (leftDown) { leftDown = false; mouse.button(true, false); }
        if (rightDown) { rightDown = false; mouse.button(false, false); }
        if (shiftHeld) { shiftHeld = false; mouse.key(KeyEvent.KEYCODE_SHIFT_LEFT, false); }
        for (int i = 0; i < GAME_KEYS.length; i++) {
            if (keysHeld[i]) { keysHeld[i] = false; mouse.key(GAME_KEYS[i][1], false); }
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
     * or steadily held pad sends no camera lines. In BAR's game (the pad also a mouse) the right stick pans, and with
     * LB held turns and zooms: the line's pan, turn and zoom come from it (lt and lb 0).
     */
    private String cameraLine(boolean game) {
        if (game) {
            boolean lb = buttons[BTN_LB];
            return String.format(Locale.US, "pad %d %d %d %d 0 0", lb ? 0 : dead(rx, STICK_DEADZONE),
                    lb ? 0 : dead(ry, STICK_DEADZONE), lb ? dead(rx, STICK_DEADZONE) : 0, lb ? dead(ry, STICK_DEADZONE) : 0);
        }
        return String.format(Locale.US, "pad %d %d %d %d %d %d", dead(lx, STICK_DEADZONE), dead(ly, STICK_DEADZONE),
                dead(rx, STICK_DEADZONE), dead(ry, STICK_DEADZONE), dead(lt, TRIGGER_DEADZONE), buttons[BTN_LB] ? 1 : 0);
    }
    private static int dead(int v, int deadzone) { return Math.abs(v) < deadzone ? 0 : v / 256 * 256; }
}
