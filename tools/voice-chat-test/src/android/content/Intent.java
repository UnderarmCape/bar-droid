package android.content;

/** Stand-in for Android's class, for tools/voice-chat-test: the extras are not kept. */
public class Intent {
    public Intent(String action) {}

    public Intent putExtra(String name, String value) { return this; }

    public Intent putExtra(String name, int value) { return this; }

    public Intent putExtra(String name, boolean value) { return this; }
}
