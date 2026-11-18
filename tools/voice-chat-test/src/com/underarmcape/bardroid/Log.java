package com.underarmcape.bardroid;

import java.util.ArrayList;
import java.util.List;

/** Stand-in for the app's Log (launcher.log), for tools/voice-chat-test: the lines kept for the test to read. */
final class Log {
    static final List<String> lines = new ArrayList<>();

    static void i(String tag, String message) { lines.add("[" + tag + "] " + message); }
}
