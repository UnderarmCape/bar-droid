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
 * there {@link PadGame} rebuilds v0.8.5's controls on a mouse and keyboard, which no lobby setting or widget rule can
 * see or block, with the camera through bardroid_touch.lua ({@link CameraSink}, "pad" lines).
 *
 * Where no game runs (the lobby, a loading screen) the pad is a simpler mouse ({@link Mouse}, Kailil 2026-10-26: "just
 * simple mouse movement, scroll and A and B as left and right click"): the left stick moves the pointer, the right
 * stick scrolls, A and B are the left and right buttons. In the controller game v0.8.5 reads the packets and the pad
 * is neither.
 */
public final class ControllerBridge {
    // SDL GameController button order, as the Windows companion sends it (PadButtons)
    public static final int BTN_A = PadButtons.A, BTN_B = PadButtons.B, BTN_X = PadButtons.X, BTN_Y = PadButtons.Y,
            BTN_BACK = PadButtons.BACK, BTN_GUIDE = PadButtons.GUIDE, BTN_START = PadButtons.START,
            BTN_LS = PadButtons.LS, BTN_RS = PadButtons.RS, BTN_LB = PadButtons.LB, BTN_RB = PadButtons.RB,
            BTN_DPAD_UP = PadButtons.DPAD_UP, BTN_DPAD_DOWN = PadButtons.DPAD_DOWN,
            BTN_DPAD_LEFT = PadButtons.DPAD_LEFT, BTN_DPAD_RIGHT = PadButtons.DPAD_RIGHT;
    public static final int BUTTON_COUNT = PadButtons.COUNT;
    private static final int IGNORED = -2;            // a pad key that is consumed but not sent (Guide, as v0.8.5 mode)
    private static final long TICK_MS = 16, HEARTBEAT_MS = 100, CAMERA_MS = 33;
    private static final int STICK_DEADZONE = 5000, TRIGGER_DEADZONE = 3000;   // v0.8.5's defaults

    /** Receives "pad lx ly rx ry lt lb" lines for the camera widget. */
    public interface CameraSink { void padLine(String line); }

    /** The X pointer and keyboard (PadMouse). Called on the pump thread. */
    public interface Mouse extends PadMouse {}
    public static final int MODE_LOBBY = PadMouse.MODE_LOBBY, MODE_GAME = PadMouse.MODE_GAME, MODE_OFF = PadMouse.MODE_OFF;
    private static final float MOUSE_CURVE = 2f, SCROLL_CLICKS_PER_SECOND = 10f;
    private static final int TRIGGER_HELD = 16000;                    // a trigger past this: held
    private static final long MOUSE_CHECK_MS = 250;

    private final int port;
    private final CameraSink camera;
    private Mouse mouse;
    private PadGame game;
    // pointer and key state, pump thread only
    private int mode = MODE_OFF;
    private boolean leftDown, rightDown;
    private static final long LOBBY_RB_TAPS_MS = 350;   // the lobby: RB's taps with LB held, the next within this
    private int lobbyRbTaps;
    private long lobbyRbAt;
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
    public void setMouse(Mouse mouse) {
        this.mouse = mouse;
        game = new PadGame(mouse);
    }

    /** Touch or a real mouse moved the pointer (any thread): in a game the pad centres it again when next used. */
    public void otherInput() { if (game != null) game.otherInput(); }

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
        if (!any && mouse != null) mouse.act("fingers");   // (the pad's ways end with it: no three taps to get the menus back)
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
                hat(BTN_DPAD_LEFT, hx < -0.5f); hat(BTN_DPAD_RIGHT, hx > 0.5f);
                hat(BTN_DPAD_UP, hy < -0.5f); hat(BTN_DPAD_DOWN, hy > 0.5f);
            }
            dirty = true;
            wakeIdle();
        }
        return true;
    }

    /** A stick or trigger past v0.8.5's deadzones or a button down: a pad at rest sends motion too, it only jitters. */
    public synchronized boolean inUse() {
        if (stick(lx) != 0 || stick(ly) != 0 || stick(rx) != 0 || stick(ry) != 0
                || lt > TRIGGER_DEADZONE || rt > TRIGGER_DEADZONE) return true;
        for (boolean b : buttons) if (b) return true;
        return false;
    }

    /** A D-pad direction from the hat axes (lock held): a press counts even if shorter than a pump tick. */
    private void hat(int idx, boolean down) {
        if (down && !buttons[idx]) pressed[idx] = true;
        buttons[idx] = down;
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
                if (camera != null && now - lastCamera >= CAMERA_MS) cameraLine = cameraLine(mode == MODE_GAME && !game.reticle());
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
                        : m == MODE_GAME ? "pad mouse and keys on (BAR's game)" : "pad mouse off (catching up with the game)");
                releaseAll();   // nothing stays held across a change
            }
            mode = m;
            mouseCheckAt = now + MOUSE_CHECK_MS;
        }
        float dt = lastMouseTick == 0 ? 0 : Math.min(0.1f, (now - lastMouseTick) / 1000f);
        lastMouseTick = now;
        boolean[] held = new boolean[BUTTON_COUNT], tapped = new boolean[BUTTON_COUNT];
        boolean rtHeld, ltHeld, active;
        float x, y, scroll;
        synchronized (this) {
            System.arraycopy(buttons, 0, held, 0, BUTTON_COUNT);
            System.arraycopy(pressed, 0, tapped, 0, BUTTON_COUNT);
            java.util.Arrays.fill(pressed, false);
            x = stick(lx); y = stick(ly); scroll = stick(ry);
            rtHeld = rt > TRIGGER_HELD;
            ltHeld = lt > TRIGGER_DEADZONE;
            active = x != 0 || y != 0 || scroll != 0 || stick(rx) != 0 || ltHeld || rt > TRIGGER_DEADZONE;
            for (int i = 0; i < BUTTON_COUNT && !active; i++) active = held[i] || tapped[i];
        }
        if (mode == MODE_OFF) return;
        if (mode == MODE_GAME) {   // v0.8.5's controls (PadGame)
            game.tick(held, tapped, x, y, ltHeld, rtHeld, active, dt);
            return;
        }
        if (tapped[BTN_START]) {   // the lobby's scale, 100% and 130% (bardroid_lobby_touch.lua catches the key)
            mouse.key(KeyEvent.KEYCODE_SCROLL_LOCK, true);
            mouse.key(KeyEvent.KEYCODE_SCROLL_LOCK, false);
        }
        // The D-pad from control to control (bardroid_lobby_touch.lua puts the pointer on the next one that way: A clicks
        // it; Kailil, 2026-11-06: "allow dpad menu navigation via selection in the lobby"); while speak to chat listens,
        // left / right its target. LB held + RB twice: speak to chat, as in the game.
        boolean listening = mouse.voiceListening();
        if (tapped[BTN_DPAD_UP]) mouse.act("lobby_nav_up");
        if (tapped[BTN_DPAD_DOWN]) mouse.act("lobby_nav_down");
        if (tapped[BTN_DPAD_LEFT]) mouse.act(listening ? "voice_channel_prev" : "lobby_nav_left");
        if (tapped[BTN_DPAD_RIGHT]) mouse.act(listening ? "voice_channel_next" : "lobby_nav_right");
        if (held[BTN_LB] && tapped[BTN_RB]) {
            lobbyRbTaps = now - lobbyRbAt <= LOBBY_RB_TAPS_MS ? lobbyRbTaps + 1 : 1;
            lobbyRbAt = now;
            if (lobbyRbTaps == 2) mouse.voice(false);
        }
        boolean a = held[BTN_A], b = held[BTN_B];
        if ((a || tapped[BTN_A]) && !leftDown) { leftDown = true; mouse.button(true, true); }
        if (!a && leftDown) { leftDown = false; mouse.button(true, false); }
        if ((b || tapped[BTN_B]) && !rightDown) { rightDown = true; mouse.button(false, true); }
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

    /** Lets go of every mouse button and key the pad holds. Pump thread. */
    private void releaseAll() {
        if (leftDown) { leftDown = false; mouse.button(true, false); }
        if (rightDown) { rightDown = false; mouse.button(false, false); }
        game.release();
    }

    /** -1..1 past v0.8.5's deadzone, squared for fine control near the centre. */
    private static float stick(int raw) {
        float m = Math.abs(raw);
        if (m < STICK_DEADZONE) return 0;
        float n = (float) Math.pow(Math.min(1f, (m - STICK_DEADZONE) / (32767f - STICK_DEADZONE)), MOUSE_CURVE);
        return raw < 0 ? -n : n;
    }

    /** While the app has the pad (PadGame, also in the controller game when switched) v0.8.5 sees it disconnected. */
    private String packet() {
        boolean on = connected && mode != MODE_GAME;
        int c = on ? 1 : 0;
        StringBuilder sb = new StringBuilder(96);
        sb.append("BARCTRL1|").append(seq++ & 0xffffffffL).append('|').append(c)
          .append('|').append(c * lx).append('|').append(c * ly)    // Android Y is down-positive, as the protocol
          .append('|').append(c * rx).append('|').append(c * ry)
          .append('|').append(c * lt).append('|').append(c * rt).append('|');
        for (boolean b : buttons) sb.append(on && b ? '1' : '0');
        return sb.toString();
    }

    /**
     * Sticks inside v0.8.5's deadzones count as centred and the rest moves in steps of 256 (of 32767), so a resting
     * or steadily held pad sends no camera lines. In BAR's game with a free pointer (a menu has the pad, Back+Start,
     * before the start) the left stick is the pointer, so the right stick pans, and with LB held turns and zooms: the
     * line's pan, turn and zoom come from it (lt and lb 0). Otherwise (the pointer in the middle) v0.8.5's camera.
     */
    private String cameraLine(boolean freePointer) {
        if (freePointer) {
            boolean lb = buttons[BTN_LB];
            return String.format(Locale.US, "pad %d %d %d %d 0 0", lb ? 0 : dead(rx, STICK_DEADZONE),
                    lb ? 0 : dead(ry, STICK_DEADZONE), lb ? dead(rx, STICK_DEADZONE) : 0, lb ? dead(ry, STICK_DEADZONE) : 0);
        }
        boolean still = game != null && game.stickTaken();   // (the area select's filter radial has the left stick)
        return String.format(Locale.US, "pad %d %d %d %d %d %d", still ? 0 : dead(lx, STICK_DEADZONE),
                still ? 0 : dead(ly, STICK_DEADZONE), dead(rx, STICK_DEADZONE), dead(ry, STICK_DEADZONE),
                dead(lt, TRIGGER_DEADZONE), buttons[BTN_LB] ? 1 : 0);
    }
    private static int dead(int v, int deadzone) { return Math.abs(v) < deadzone ? 0 : v / 256 * 256; }
}
