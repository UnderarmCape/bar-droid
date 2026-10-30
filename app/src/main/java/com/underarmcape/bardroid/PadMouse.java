package com.underarmcape.bardroid;

/**
 * The X pointer and keyboard as the gamepad uses them (GameActivity), and what the game tells it (RtsTouch reads the
 * widgets' files). Called on ControllerBridge's pump thread. No Android classes: PadGame is checked on the laptop
 * (tools/padgame-test).
 */
interface PadMouse {
    /** No game widget answers (the lobby, a loading screen) / BAR's released game / the controller game (v0.8.5). */
    int MODE_LOBBY = 0, MODE_GAME = 1, MODE_OFF = 2;

    int mode();                             // MODE_LOBBY, MODE_GAME or MODE_OFF
    float pixelsPerSecond();                // pointer speed at full stick
    boolean onInterface();                  // the pointer is over the game's interface (the game's last answer)
    void move(int dx, int dy);              // relative, X screen pixels
    void button(boolean left, boolean down);
    void wheel(float dy);                   // Termux:X11 scroll units, 120 per click, > 0 scrolls down
    void key(int keyCode, boolean down);    // an Android key code, as a keyboard key
    void act(String name);                  // a game action (bardroid_touch.lua, bardroid_pad.lua)
    void centre();                          // the pointer to the middle of the screen
    void moveTo(float x, float y);          // the pointer to X screen pixel (x, y)
    int width();                            // the X screen
    int height();
    float[] pointer();                      // where the pointer is by the game's last answer (x, y), or null
    String padFocus();                      // "build", "orders" or "none": a menu has the pad (bardroid_pad.txt)
    boolean pregame();                      // before the start (bardroid_pad.txt)
    String armed();                         // the order picked: "build", "area", "unitarea", "other" or "none"
    float drawSpeed();                      // the pointer's speed while drawing, for the zoom (1: the speed at full zoom out)
}
