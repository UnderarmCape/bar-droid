package android.speech;

import android.content.Context;
import android.content.Intent;

import java.util.ArrayList;
import java.util.List;

/**
 * Stand-in for Android's class, for tools/voice-chat-test: each recognizer made is kept (made), with its listener, so
 * the test can call it back as Android's recognition service would, a destroyed one too (the worst case: a late
 * callback that still arrives).
 */
public class SpeechRecognizer {
    public static final String RESULTS_RECOGNITION = "results_recognition";
    public static final int ERROR_NETWORK_TIMEOUT = 1;
    public static final int ERROR_NETWORK = 2;
    public static final int ERROR_AUDIO = 3;
    public static final int ERROR_SERVER = 4;
    public static final int ERROR_CLIENT = 5;
    public static final int ERROR_SPEECH_TIMEOUT = 6;
    public static final int ERROR_NO_MATCH = 7;
    public static final int ERROR_RECOGNIZER_BUSY = 8;
    public static final int ERROR_INSUFFICIENT_PERMISSIONS = 9;

    public static boolean available = true;
    public static final List<SpeechRecognizer> made = new ArrayList<>();

    public RecognitionListener listener;
    public int starts;
    public boolean destroyed;

    public static boolean isRecognitionAvailable(Context context) { return available; }

    public static SpeechRecognizer createSpeechRecognizer(Context context) {
        SpeechRecognizer r = new SpeechRecognizer();
        made.add(r);
        return r;
    }

    public void setRecognitionListener(RecognitionListener listener) { this.listener = listener; }

    public void startListening(Intent intent) { starts++; }

    public void destroy() { destroyed = true; }
}
