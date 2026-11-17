package com.underarmcape.bardroid;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;

import java.util.ArrayList;

/**
 * Speak to chat (Kailil, 2026-11-06: "I double tap three fingers, a toast pops up saying speak to chat. I talk then after
 * im done talking it enters into chat automatically. If nothing is said. Do nothing"): the phone's own speech recognition
 * (Android's SpeechRecognizer, the recognition service the phone has: Google's or Samsung's), no keyboard. The words go
 * to BAR's chat as a message (bardroid_chat.lua, the channel Enter opens); silence or an error sends nothing. The
 * microphone is asked for the first time it is used. Main thread only.
 */
final class VoiceChat {
    static final int PERMISSION_REQUEST = 4711;

    interface Sink {
        void listening(boolean on, boolean ping);   // "SPEAK TO CHAT" / "SPEAK THE PING" shown while on
        void heard(String text, boolean ping);      // what was said: to chat, or a ping's label
        void unavailable();                         // the phone has no recognition service
        void denied();                              // the microphone is not allowed: a note says where to allow it
        void offline();                             // the recognition needed a connection: a note says nothing went
    }

    private final Activity activity;
    private final Sink sink;
    // A fresh recognizer for each session, destroyed when it ends: cancel() answered with a late onError(5), which ended
    // the next session (its note gone, its words dropped) when it came after that session's start (dev phone,
    // 2026-11-09); a destroyed recognizer calls nothing back, and what an older session still says is dropped by number.
    private SpeechRecognizer recognizer;
    private int session;   // the session listening now (main thread)
    private volatile boolean listening;
    private boolean waitingForPermission;
    // the game screen stopped (close) until it starts again (opened): a start already on its way (the three-finger tap's
    // 350 ms wait for a double tap, the pad's chord, a post) does not begin listening behind a locked phone; review
    // 2026-11-15
    private boolean screenGone;
    private volatile boolean ping;   // what this listening is for: a ping's label (the pad: hold LB, RB three times), else chat

    VoiceChat(Activity activity, Sink sink) {
        this.activity = activity;
        this.sink = sink;
    }

    /** Speak to chat (three fingers; hold LB, RB twice). */
    void start() { start(false); }

    /** Listening for chat now: the D-pad's or a swipe's left and right pick the chat's channel meanwhile. Any thread. */
    boolean listening() { return listening && !ping; }

    /**
     * Starts listening, for chat or for a ping's label (Kailil, 2026-11-06: the pad's LB held and RB three times "sets
     * a ping ... (voice stt tho) then it enters the ping either the text"); while it listens, cancels instead.
     */
    void start(boolean forPing) {
        if (listening) {
            cancel();
            return;
        }
        if (screenGone) {
            Log.i("app", "voice chat: not started, the game screen is gone");
            return;
        }
        if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
            Log.i("app", "voice chat: no speech recognition on this phone");
            sink.unavailable();
            return;
        }
        ping = forPing;
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            waitingForPermission = true;
            activity.requestPermissions(new String[] {Manifest.permission.RECORD_AUDIO}, PERMISSION_REQUEST);
            return;
        }
        endRecognizer();
        recognizer = SpeechRecognizer.createSpeechRecognizer(activity);
        recognizer.setRecognitionListener(new Listener(++session, forPing));
        Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
                .putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, activity.getPackageName());
        listening = true;
        sink.listening(true, ping);
        recognizer.startListening(intent);
    }

    /** The microphone permission answered (GameActivity.onRequestPermissionsResult): the waiting start goes on, or not. */
    void permissionResult(boolean granted) {
        boolean wanted = waitingForPermission;
        waitingForPermission = false;
        if (wanted && granted) start(ping);
        else if (wanted) {
            // (after two "Don't allow" Android stops asking and answers no at once: without a word speak to chat did
            // nothing at all, every time)
            Log.i("app", "voice chat: the microphone was not allowed");
            sink.denied();
        }
    }

    private void cancel() {
        session++;
        endRecognizer();
        done();
    }

    private void endRecognizer() {
        if (recognizer != null) {
            recognizer.destroy();
            recognizer = null;
        }
    }

    private void done() {
        if (listening) {
            listening = false;
            sink.listening(false, ping);
        }
    }

    /** The game screen started again (GameActivity.onStart): starts are taken again. */
    void opened() {
        screenGone = false;
    }

    /**
     * Stops listening: the game screen gone (GameActivity.onStop: the phone locked or another app in front) or closed.
     * Listening on after the screen went away sent what was said next, perhaps to someone else in the room, to the
     * game's chat, online a public one.
     */
    void close() {
        screenGone = true;
        if (listening) Log.i("app", "voice chat: stopped listening, the game screen went away");
        // (and a start waiting for the microphone's permission dropped: a yes given after the screen went away would
        // have started listening then)
        waitingForPermission = false;
        session++;
        endRecognizer();
        done();
    }

    /** SpeechRecognizer's error codes in words, for launcher.log (what was said is never logged). */
    static String errorName(int error) {
        switch (error) {
            case 1: return "network timeout";
            case 2: return "no network";
            case 3: return "microphone audio";
            case 4: return "recognition server";
            case 5: return "cancelled";
            case 6: return "nothing said";
            case 7: return "nothing understood";
            case 8: return "recognizer busy";
            case 9: return "microphone not allowed";
            case 10: return "too many requests";
            case 11: return "recognition service gone";
            case 12: return "language not supported";
            case 13: return "language not downloaded";
            default: return "other";
        }
    }

    /** One session's callbacks: a session no longer listening is past (cancelled, or another started), its words dropped. */
    private final class Listener implements RecognitionListener {
        private final int id;
        private final boolean forPing;

        Listener(int id, boolean forPing) {
            this.id = id;
            this.forPing = forPing;
        }

        private boolean past(String what) {
            if (id == session) return false;
            Log.i("app", "voice chat: a past session's " + what + " dropped");
            return true;
        }

        @Override public void onReadyForSpeech(Bundle params) {}
        @Override public void onBeginningOfSpeech() {}
        @Override public void onRmsChanged(float rmsdB) {}
        @Override public void onBufferReceived(byte[] buffer) {}
        @Override public void onEndOfSpeech() {}
        @Override public void onPartialResults(Bundle partialResults) {}
        @Override public void onEvent(int eventType, Bundle params) {}

        @Override public void onError(int error) {   // (no speech, no match, a timeout: nothing is sent)
            if (past("error " + error)) return;
            Log.i("app", "voice chat: nothing sent (" + errorName(error) + ", recognizer error " + error + ")");
            endRecognizer();   // (busy, error 8, too: the next session's recognizer is a new one)
            done();
            if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) sink.denied();
            // (a recognizer that needs the network, with none or a server not answering: what was said is lost, and the
            // note only went away, as for silence; review 2026-11-17, the dev phone without a connection)
            else if (error == SpeechRecognizer.ERROR_NETWORK_TIMEOUT || error == SpeechRecognizer.ERROR_NETWORK
                    || error == SpeechRecognizer.ERROR_SERVER) sink.offline();
        }

        @Override public void onResults(Bundle results) {
            if (past("words")) return;
            endRecognizer();
            done();
            ArrayList<String> heard = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
            String text = heard != null && !heard.isEmpty() && heard.get(0) != null ? heard.get(0).trim() : "";
            if (!text.isEmpty()) sink.heard(text, forPing);
        }
    }
}
