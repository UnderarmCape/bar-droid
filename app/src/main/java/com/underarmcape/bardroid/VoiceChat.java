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
    }

    private final Activity activity;
    private final Sink sink;
    private SpeechRecognizer recognizer;
    private volatile boolean listening;
    private boolean waitingForPermission;
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
        if (recognizer == null) {
            recognizer = SpeechRecognizer.createSpeechRecognizer(activity);
            recognizer.setRecognitionListener(listener);
        }
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
        else if (wanted) Log.i("app", "voice chat: the microphone was not allowed");
    }

    private void cancel() {
        if (recognizer != null) recognizer.cancel();
        done();
    }

    private void done() {
        if (listening) {
            listening = false;
            sink.listening(false, ping);
        }
    }

    void close() {
        done();
        if (recognizer != null) {
            recognizer.destroy();
            recognizer = null;
        }
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

    private final RecognitionListener listener = new RecognitionListener() {
        @Override public void onReadyForSpeech(Bundle params) {}
        @Override public void onBeginningOfSpeech() {}
        @Override public void onRmsChanged(float rmsdB) {}
        @Override public void onBufferReceived(byte[] buffer) {}
        @Override public void onEndOfSpeech() {}
        @Override public void onPartialResults(Bundle partialResults) {}
        @Override public void onEvent(int eventType, Bundle params) {}

        @Override public void onError(int error) {   // (no speech, no match, a timeout: nothing is sent)
            Log.i("app", "voice chat: nothing sent (" + errorName(error) + ", recognizer error " + error + ")");
            done();
        }

        @Override public void onResults(Bundle results) {
            done();
            ArrayList<String> heard = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
            String text = heard != null && !heard.isEmpty() && heard.get(0) != null ? heard.get(0).trim() : "";
            if (!text.isEmpty()) sink.heard(text, ping);
        }
    };
}
