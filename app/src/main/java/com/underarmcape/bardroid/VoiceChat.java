package com.underarmcape.bardroid;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.util.Log;

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
        void listening(boolean on);   // "SPEAK TO CHAT" shown while true
        void heard(String text);      // what was said, to chat
        void unavailable();           // the phone has no recognition service
    }

    private final Activity activity;
    private final Sink sink;
    private SpeechRecognizer recognizer;
    private boolean listening, waitingForPermission;

    VoiceChat(Activity activity, Sink sink) {
        this.activity = activity;
        this.sink = sink;
    }

    /** Starts listening; while it listens, cancels instead (a second double tap). */
    void start() {
        if (listening) {
            cancel();
            return;
        }
        if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
            Log.i("app", "voice chat: no speech recognition on this phone");
            sink.unavailable();
            return;
        }
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
        sink.listening(true);
        recognizer.startListening(intent);
    }

    /** The microphone permission answered (GameActivity.onRequestPermissionsResult): the waiting start goes on, or not. */
    void permissionResult(boolean granted) {
        boolean wanted = waitingForPermission;
        waitingForPermission = false;
        if (wanted && granted) start();
        else if (wanted) Log.i("app", "voice chat: the microphone was not allowed");
    }

    private void cancel() {
        if (recognizer != null) recognizer.cancel();
        done();
    }

    private void done() {
        if (listening) {
            listening = false;
            sink.listening(false);
        }
    }

    void close() {
        done();
        if (recognizer != null) {
            recognizer.destroy();
            recognizer = null;
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
            Log.i("app", "voice chat: nothing sent (recognizer error " + error + ")");
            done();
        }

        @Override public void onResults(Bundle results) {
            done();
            ArrayList<String> heard = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
            String text = heard != null && !heard.isEmpty() && heard.get(0) != null ? heard.get(0).trim() : "";
            if (!text.isEmpty()) sink.heard(text);
        }
    };
}
