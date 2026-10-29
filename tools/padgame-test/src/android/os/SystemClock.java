package android.os;

/** tools/padgame-test's clock: the test sets it. */
public final class SystemClock {
    public static long now = 1_000_000;

    public static long uptimeMillis() { return now; }
}
