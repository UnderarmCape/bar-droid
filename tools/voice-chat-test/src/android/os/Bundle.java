package android.os;

import java.util.ArrayList;
import java.util.HashMap;

/** Stand-in for Android's class, for tools/voice-chat-test: string lists only. */
public class Bundle {
    private final HashMap<String, ArrayList<String>> lists = new HashMap<>();

    public ArrayList<String> getStringArrayList(String key) { return lists.get(key); }

    public void putStringArrayList(String key, ArrayList<String> value) { lists.put(key, value); }
}
