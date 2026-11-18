package android.os;

// (a stand-in: what is posted runs at once, on the caller's thread)
public class Handler {
    public Handler(Looper looper) {}
    public boolean post(Runnable r) { r.run(); return true; }
}
