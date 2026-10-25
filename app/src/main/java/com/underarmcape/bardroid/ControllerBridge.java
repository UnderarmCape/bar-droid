package com.underarmcape.bardroid;

import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;

/**
 * Turns Android gamepad events into the BARCTRL1 UDP packets consumed by the controller widgets
 * (luaui/Widgets/controller_socket_bridge.lua from UnderarmCape's BAR Controller Companion):
 *
 *   BARCTRL1|seq|connected|leftX|leftY|rightX|rightY|leftTrigger|rightTrigger|buttons
 *
 * axes are signed 16-bit (Y down-positive), triggers 0..32767, buttons a 21-char string of 0/1 in SDL order.
 * Packets go to 127.0.0.1:28777; proot shares the network namespace so the engine's Lua sees them.
 */
public final class ControllerBridge {
    // SDL GameController button order, as sent by the Windows companion bridge (BARControllerBridge.exe):
    // 0 A, 1 B, 2 X, 3 Y, 4 Back, 5 Guide, 6 Start, 7 LeftStick, 8 RightStick, 9 LB, 10 RB,
    // 11 DPadUp, 12 DPadDown, 13 DPadLeft, 14 DPadRight, 15..20 misc/paddles (unused). 21 chars total.
    public static final int BTN_A = 0, BTN_B = 1, BTN_X = 2, BTN_Y = 3, BTN_BACK = 4, BTN_GUIDE = 5, BTN_START = 6,
            BTN_LS = 7, BTN_RS = 8, BTN_LB = 9, BTN_RB = 10,
            BTN_DPAD_UP = 11, BTN_DPAD_DOWN = 12, BTN_DPAD_LEFT = 13, BTN_DPAD_RIGHT = 14;
    public static final int BUTTON_COUNT = 21;

    private final int port;
    private DatagramSocket socket;
    private InetAddress loopback;
    private long seq;
    private final boolean[] buttons = new boolean[BUTTON_COUNT];
    private int lx, ly, rx, ry, lt, rt;
    private boolean connected;
    private Thread pump;
    private volatile boolean running;

    public ControllerBridge(int port) { this.port = port; }

    public synchronized void start() {
        if (running) return;
        try {
            socket = new DatagramSocket();
            loopback = InetAddress.getByName("127.0.0.1");
        } catch (IOException e) { Log.e("pad", "udp socket", e); return; }
        running = true;
        pump = new Thread(() -> {
            while (running) {
                send();
                try { Thread.sleep(16); } catch (InterruptedException e) { break; }
            }
        }, "pad-pump");
        pump.setDaemon(true);
        pump.start();
        Log.i("pad", "controller bridge sending to 127.0.0.1:" + port);
    }

    public synchronized void stop() {
        running = false;
        if (pump != null) pump.interrupt();
        if (socket != null) socket.close();
    }

    public static boolean isGamepad(InputDevice d) {
        if (d == null) return false;
        int s = d.getSources();
        return (s & InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD || (s & InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK;
    }

    /** @return true if the event was a gamepad event and has been consumed. */
    public boolean onMotion(MotionEvent e) {
        if (!e.isFromSource(InputDevice.SOURCE_JOYSTICK) && !e.isFromSource(InputDevice.SOURCE_GAMEPAD)) return false;
        connected = true;
        lx = axis(e, MotionEvent.AXIS_X); ly = axis(e, MotionEvent.AXIS_Y);
        rx = axis(e, MotionEvent.AXIS_Z); ry = axis(e, MotionEvent.AXIS_RZ);
        lt = trigger(e, MotionEvent.AXIS_LTRIGGER, MotionEvent.AXIS_BRAKE);
        rt = trigger(e, MotionEvent.AXIS_RTRIGGER, MotionEvent.AXIS_GAS);
        float hx = e.getAxisValue(MotionEvent.AXIS_HAT_X), hy = e.getAxisValue(MotionEvent.AXIS_HAT_Y);
        buttons[BTN_DPAD_LEFT] = hx < -0.5f; buttons[BTN_DPAD_RIGHT] = hx > 0.5f;
        buttons[BTN_DPAD_UP] = hy < -0.5f; buttons[BTN_DPAD_DOWN] = hy > 0.5f;
        return true;
    }

    /** @return true if the key belongs to a gamepad and has been consumed. */
    public boolean onKey(KeyEvent e) {
        int idx = map(e.getKeyCode());
        boolean fromPad = isGamepad(e.getDevice()) || KeyEvent.isGamepadButton(e.getKeyCode());
        if (idx < 0 || !fromPad) return false;
        connected = true;
        buttons[idx] = e.getAction() == KeyEvent.ACTION_DOWN;
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
            case KeyEvent.KEYCODE_BUTTON_MODE: return BTN_GUIDE;
            case KeyEvent.KEYCODE_DPAD_UP: return BTN_DPAD_UP;
            case KeyEvent.KEYCODE_DPAD_DOWN: return BTN_DPAD_DOWN;
            case KeyEvent.KEYCODE_DPAD_LEFT: return BTN_DPAD_LEFT;
            case KeyEvent.KEYCODE_DPAD_RIGHT: return BTN_DPAD_RIGHT;
            default: return -1;
        }
    }

    private static int axis(MotionEvent e, int axis) {
        float v = e.getAxisValue(axis);
        if (Math.abs(v) < 0.08f) v = 0;
        return (int) Math.max(-32768, Math.min(32767, Math.round(v * 32767)));
    }
    private static int trigger(MotionEvent e, int a, int b) {
        float v = Math.max(e.getAxisValue(a), e.getAxisValue(b));
        return (int) Math.max(0, Math.min(32767, Math.round(v * 32767)));
    }

    private void send() {
        if (socket == null) return;
        StringBuilder sb = new StringBuilder(96);
        sb.append("BARCTRL1|").append(seq++ & 0xffffffffL).append('|').append(connected ? 1 : 0)
          .append('|').append(lx).append('|').append(ly)    // Android Y is down-positive, same as the SDL convention the widget expects
          .append('|').append(rx).append('|').append(ry)
          .append('|').append(lt).append('|').append(rt).append('|');
        for (boolean b : buttons) sb.append(b ? '1' : '0');
        byte[] data = sb.toString().getBytes(StandardCharsets.US_ASCII);
        try { socket.send(new DatagramPacket(data, data.length, loopback, port)); } catch (IOException ignored) {}
    }
}
