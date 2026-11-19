package com.underarmcape.bardroid;

/**
 * The GPU driver's rare fault on Adreno phones (docs/DELIVERY.md, "A replay on the dev phone hung"): the kernel driver
 * refuses the engine's GPU context ("MESA: error: flush_submit_list:89: submit failed -1 (Resource deadlock
 * avoided)"), every later submit fails, and the game's picture stops for good while its process lives on: the player
 * saw a frozen game until they closed the app. Four times on the dev phone (2026-11-02 to 11-05), never recovered.
 *
 * Fed every line of the engine's output, this says when the game is lost: the driver's refusal, and then BAR's watchdog
 * saying the main thread has not moved for its 30 s. Either alone is not enough (a refused submit the engine got past,
 * a long load). No Android classes: tools/status-text-test checks it on the laptop.
 */
public final class DriverWatch {
    static final String REFUSED = "Resource deadlock avoided";
    static final String HUNG = "Hang detection triggered";

    private boolean refused, lost;

    /** One line of the engine's output; true once, at the line that shows the game is lost. */
    public synchronized boolean onLine(String line) {
        if (lost || line == null) return false;
        if (!refused) {
            if (line.contains("submit failed") && line.contains(REFUSED)) refused = true;
            return false;
        }
        if (line.contains(HUNG)) { lost = true; return true; }
        return false;
    }

    public synchronized boolean refused() { return refused; }
    public synchronized boolean lost() { return lost; }

    /**
     * Sooner than the watchdog (the player looked at a frozen, half-drawn picture for its 30 s; dev phone 2026-11-19,
     * a skirmish 25 s in): the refusal came while the game's own widget was answering (it writes its hover file at
     * least every 2 s), and that widget has now been silent STALL_MS: the main thread is stuck. A refusal while loading
     * (no widget yet) still waits for the watchdog. True once, as onLine.
     */
    static final long STALL_MS = 8000;
    public synchronized boolean stalled(boolean widgetAtRefusal, long widgetSilentMs) {
        if (lost || !refused || !widgetAtRefusal || widgetSilentMs < STALL_MS) return false;
        lost = true;
        return true;
    }

    /** What the launcher says afterwards. */
    public static String note() {
        return "The phone's GPU driver stopped the game's graphics (a rare driver fault), so the app closed the frozen"
                + " game. Start it again; an online game can be rejoined from the lobby.";
    }
}
