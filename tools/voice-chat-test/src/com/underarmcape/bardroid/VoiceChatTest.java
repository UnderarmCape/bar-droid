package com.underarmcape.bardroid;

import android.app.Activity;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.speech.SpeechRecognizer;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * VoiceChat.java (speak to chat) on the laptop, with stand-ins for Android's speech recognition: each session's words
 * reach the chat, a cancelled or past session's late callbacks (cancel()'s late onError(5), dev phone 2026-11-09) are
 * dropped and never end the session listening now, a busy recognizer is never used again, the screen going away stops
 * listening and refuses starts until it is back, the microphone question asked once at a time. The live microphone is
 * not opened by any check (the dev phone's is revoked); this covers the code's side of docs/DELIVERY.md "Speak to chat
 * started, cancelled and started again quickly".
 *   powershell -ExecutionPolicy Bypass -File tools\voice-chat-test.ps1
 */
public final class VoiceChatTest {
    private static int failures;

    /** What the game screen was told: "on chat", "off ping", "heard <words> chat", "denied", ... */
    static final class Sink implements VoiceChat.Sink {
        final List<String> events = new ArrayList<>();

        private static String kind(boolean ping) { return ping ? "ping" : "chat"; }

        @Override public void listening(boolean on, boolean ping) { events.add((on ? "on " : "off ") + kind(ping)); }
        @Override public void heard(String text, boolean ping) { events.add("heard " + text + " " + kind(ping)); }
        @Override public void unavailable() { events.add("unavailable"); }
        @Override public void denied() { events.add("denied"); }
        @Override public void offline() { events.add("offline"); }
    }

    private static Activity activity;
    private static Sink sink;
    private static VoiceChat voice;

    private static void fresh() {
        SpeechRecognizer.made.clear();
        SpeechRecognizer.available = true;
        Log.lines.clear();
        activity = new Activity();
        sink = new Sink();
        voice = new VoiceChat(activity, sink);
    }

    private static SpeechRecognizer rec(int i) { return SpeechRecognizer.made.get(i); }

    private static SpeechRecognizer last() { return SpeechRecognizer.made.get(SpeechRecognizer.made.size() - 1); }

    private static Bundle words(String... said) {
        Bundle b = new Bundle();
        b.putStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION, new ArrayList<>(Arrays.asList(said)));
        return b;
    }

    private static boolean logged(String part) {
        for (String l : Log.lines) if (l.contains(part)) return true;
        return false;
    }

    private static void check(String what, boolean ok, Object detail) {
        System.out.println((ok ? "PASS " : "FAIL ") + what + ": " + detail);
        if (!ok) failures++;
    }

    public static void main(String[] args) {
        // a session's words reach the chat, the recognizer ended with it
        fresh();
        voice.start();
        boolean wasListening = voice.listening();
        rec(0).listener.onResults(words("  hello team  "));
        check("one session: listening, then the words to chat (trimmed), the recognizer destroyed",
                wasListening && !voice.listening() && sink.events.equals(Arrays.asList("on chat", "off chat", "heard hello team chat"))
                        && rec(0).starts == 1 && rec(0).destroyed, sink.events);

        // a second start while listening cancels it
        fresh();
        voice.start();
        voice.start();
        check("a start while listening cancels: the note off, the recognizer destroyed, no new one",
                !voice.listening() && sink.events.equals(Arrays.asList("on chat", "off chat")) && rec(0).destroyed
                        && SpeechRecognizer.made.size() == 1, sink.events + ", made " + SpeechRecognizer.made.size());

        // DELIVERY's case: started, cancelled, started again; the first one's late onError(5) after the new start
        fresh();
        voice.start();
        voice.start();
        voice.start();
        SpeechRecognizer a = rec(0), b = rec(1);
        a.listener.onError(SpeechRecognizer.ERROR_CLIENT);
        boolean stillOn = voice.listening();
        a.listener.onResults(words("old words"));
        b.listener.onResults(words("gg"));
        check("cancel's late error 5 after the next start: dropped, the new session listens on and its words reach chat",
                stillOn && b != a && a.destroyed && b.destroyed && sink.events.equals(Arrays.asList("on chat", "off chat", "on chat",
                        "off chat", "heard gg chat")) && logged("a past session's error 5 dropped")
                        && logged("a past session's words dropped"), sink.events);

        // three quick start-and-cancel pairs (LB + RB twice, three times), then once and speak
        fresh();
        for (int i = 0; i < 3; i++) {
            voice.start();
            voice.start();
        }
        voice.start();
        for (int i = 0; i < 3; i++) rec(i).listener.onError(SpeechRecognizer.ERROR_CLIENT);
        boolean on = voice.listening();
        last().listener.onResults(words("push mid"));
        boolean eachDestroyed = rec(0).destroyed && rec(1).destroyed && rec(2).destroyed && last().destroyed;
        check("three quick starts and cancels, then one: three late errors dropped, the last session's words to chat",
                on && SpeechRecognizer.made.size() == 4 && eachDestroyed
                        && sink.events.get(sink.events.size() - 1).equals("heard push mid chat"),
                sink.events + ", made " + SpeechRecognizer.made.size());

        // a busy recognizer (error 8): nothing sent, the next session a new one
        fresh();
        voice.start();
        rec(0).listener.onError(SpeechRecognizer.ERROR_RECOGNIZER_BUSY);
        voice.start();
        check("recognizer busy: nothing sent, its recognizer destroyed, the next start makes a new one",
                rec(0).destroyed && SpeechRecognizer.made.size() == 2 && !rec(1).destroyed && voice.listening()
                        && sink.events.equals(Arrays.asList("on chat", "off chat", "on chat")), sink.events);

        // the errors' notes: silence nothing, the network offline, the microphone denied
        int[][] errs = {{6, 0}, {7, 0}, {1, 1}, {2, 1}, {4, 1}, {13, 1}, {9, 2}};
        for (int[] e : errs) {
            fresh();
            voice.start();
            rec(0).listener.onError(e[0]);
            String note = e[1] == 0 ? null : e[1] == 1 ? "offline" : "denied";
            List<String> want = note == null ? Arrays.asList("on chat", "off chat") : Arrays.asList("on chat", "off chat", note);
            check("error " + e[0] + " (" + VoiceChat.errorName(e[0]) + "): " + (note == null ? "no note" : note),
                    sink.events.equals(want) && !voice.listening(), sink.events);
        }

        // nothing understood: empty words, no list
        fresh();
        voice.start();
        rec(0).listener.onResults(words("   "));
        voice.start();
        rec(1).listener.onResults(new Bundle());
        check("blank words or none: nothing to chat",
                sink.events.equals(Arrays.asList("on chat", "off chat", "on chat", "off chat")), sink.events);

        // a ping's label: not chat listening (the channel keys stay the game's), the words as the ping's
        fresh();
        voice.start(true);
        boolean chatListening = voice.listening();
        rec(0).listener.onResults(words("attack here"));
        check("a ping's label: listening() false meanwhile, the words to the ping",
                !chatListening && sink.events.equals(Arrays.asList("on ping", "off ping", "heard attack here ping")), sink.events);

        // the screen gone: listening stops, starts refused until it is back, the old session's words dropped
        fresh();
        voice.start();
        voice.close();
        rec(0).listener.onResults(words("said after the lock"));
        voice.start();
        boolean refused = SpeechRecognizer.made.size() == 1 && !voice.listening();
        voice.opened();
        voice.start();
        check("the screen gone: listening off, its late words dropped, no start until it is back",
                refused && voice.listening() && SpeechRecognizer.made.size() == 2 && logged("the game screen is gone")
                        && sink.events.equals(Arrays.asList("on chat", "off chat", "on chat")), sink.events);

        // the microphone question: asked once, a second start meanwhile does nothing, Allow starts the waiting one
        fresh();
        activity.permission = PackageManager.PERMISSION_DENIED;
        voice.start(true);
        voice.start(true);
        int asked = activity.requests;
        activity.permission = PackageManager.PERMISSION_GRANTED;
        voice.permissionResult(true);
        check("the microphone asked once, Allow starts the waiting ping session",
                asked == 1 && logged("question is still open") && rec(0).starts == 1
                        && sink.events.equals(Arrays.asList("on ping")) && SpeechRecognizer.made.size() == 1,
                sink.events + ", asked " + asked);

        fresh();
        activity.permission = PackageManager.PERMISSION_DENIED;
        voice.start();
        voice.permissionResult(false);
        voice.permissionResult(false);
        check("the microphone not allowed: one note, nothing listens",
                sink.events.equals(Arrays.asList("denied")) && SpeechRecognizer.made.isEmpty(), sink.events);

        fresh();
        activity.permission = PackageManager.PERMISSION_DENIED;
        voice.start();
        voice.close();
        activity.permission = PackageManager.PERMISSION_GRANTED;
        voice.permissionResult(true);
        check("Allow after the screen went away: nothing starts",
                sink.events.isEmpty() && SpeechRecognizer.made.isEmpty(), sink.events);

        fresh();
        SpeechRecognizer.available = false;
        voice.start();
        check("no recognition service: the note, nothing made",
                sink.events.equals(Arrays.asList("unavailable")) && SpeechRecognizer.made.isEmpty(), sink.events);

        System.out.println(failures == 0 ? "ALL PASS" : failures + " FAILED");
        System.exit(failures == 0 ? 0 : 1);
    }
}
