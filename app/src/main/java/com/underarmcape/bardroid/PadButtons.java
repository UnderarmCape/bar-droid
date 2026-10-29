package com.underarmcape.bardroid;

/**
 * The gamepad's buttons in SDL GameController order, as Kailil's Windows companion sends them in BARCTRL1 packets
 * (ControllerBridge) and as PadGame reads them: 15..20 misc/paddles (unused), 21 in all. No Android classes: PadGame
 * is checked on the laptop (tools/padgame-test).
 */
final class PadButtons {
    static final int A = 0, B = 1, X = 2, Y = 3, BACK = 4, GUIDE = 5, START = 6, LS = 7, RS = 8, LB = 9, RB = 10,
            DPAD_UP = 11, DPAD_DOWN = 12, DPAD_LEFT = 13, DPAD_RIGHT = 14;
    static final int COUNT = 21;

    private PadButtons() {}
}
