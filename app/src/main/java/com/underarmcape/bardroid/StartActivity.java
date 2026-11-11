package com.underarmcape.bardroid;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.TextView;

/**
 * What the app icon opens: straight into the lobby, or back to a game that is running, with BAR's icon on black in
 * between (its window background; no launcher screen). The launcher (LauncherActivity) opens instead for a first
 * install, an install step an app update added, a lobby that failed right away, or with the setting "Open the lobby
 * when the app starts" off; long-press the icon → "Launcher" (res/xml/shortcuts.xml) always opens it.
 */
public class StartActivity extends Activity {
    private static final long GIVE_UP_MS = 30_000;   // no game screen by then: show the launcher (and its log)
    private final Handler handler = new Handler(Looper.getMainLooper());
    /** The game screen (its own task) takes over: this task leaves recent apps, so the app shows there once. */
    private boolean toGame;
    /** The BAR update check (Updater) shows its status under the icon; the give-up clock waits for it. */
    private TextView updateView;
    private long waitingSince;
    private final Runnable tick = new Runnable() {
        @Override public void run() {
            if (isFinishing()) return;
            String s = GameService.status();
            long now = SystemClock.elapsedRealtime();
            boolean updating = s.startsWith("update: ") || s.startsWith("BAR update");
            if (updating) waitingSince = now;
            updateView.setText(updating ? StatusText.forPlayers(s.replaceFirst("^update: ", "")) : "");   // ("Checking for ...")
            if (now - waitingSince > GIVE_UP_MS) { toGame = false; openLauncher(); finishAndRemoveTask(); return; }
            handler.postDelayed(this, 500);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (GameService.busy()) {
            if (GameService.status().startsWith("running")) {
                startActivity(new Intent(this, GameActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
                finishAndRemoveTask();
            } else {
                openLauncher();   // installing
                finishAndRemoveTask();
            }
            return;
        }
        boolean lowMemoryExit = GameService.noteLowMemoryExit(this);   // (the launcher says why the game ended)
        if (!Prefs.autoLobby || !new Installer(this, BarApp.get().paths()).isInstalled() || Prefs.lobbyFailedFast(this)
                || lowMemoryExit) {
            // (once: the next tap on the icon tries the lobby again. The flag stayed until a lobby started from the
            // launcher, and the Fold7's icon opened the launcher every time after one failed start, Kailil 2026-11-10)
            if (Prefs.lobbyFailedFast(this)) {
                Log.i("app", "the lobby failed on its last start: showing the launcher (the icon opens the lobby next time)");
                Prefs.setLobbyFailedFast(this, false);
            }
            openLauncher();
            finishAndRemoveTask();   // (the icon's task goes: its next tap starts here again, LauncherActivity's own task)
            return;
        }
        GameService.start(this, GameService.ACTION_PLAY, "lobby");
        toGame = true;
        updateView = new TextView(this);
        updateView.setTextColor(0xffb0b0b0);
        updateView.setTextSize(14);
        updateView.setGravity(Gravity.CENTER_HORIZONTAL | Gravity.TOP);
        setContentView(updateView, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        // under the icon: the icon is the window's background, centred on the whole window, the text was centred
        // beside the navigation bar (landscape: ~70 px left of the icon on the dev phone); the bar's width on the
        // other side too
        updateView.post(() -> {
            android.view.WindowInsets in = getWindow().getDecorView().getRootWindowInsets();
            if (in == null) return;
            int left, right;
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                android.graphics.Insets bars = in.getInsetsIgnoringVisibility(android.view.WindowInsets.Type.systemBars());
                left = bars.left; right = bars.right;
            } else {
                left = in.getStableInsetLeft(); right = in.getStableInsetRight();   // (Android 9 and 10)
            }
            // just under the icon's picture, not at the screen's foot (650 px of black lay between them on the dev phone,
            // upright, 2026-11-08). start_background centres its 240 dp icon on the window, whose top is not the
            // screen's (under the status bar, more so at the Fold7's unfolded size): measured from the window's own
            // place; the picture ends 80 dp below its middle, the text 20 dp under that
            int[] at = new int[2], win = new int[2];
            updateView.getLocationOnScreen(at);
            android.view.View decor = getWindow().getDecorView();
            decor.getLocationOnScreen(win);
            float dp = getResources().getDisplayMetrics().density;
            int top = Math.max(0, Math.round(win[1] + decor.getHeight() / 2f + 100 * dp) - at[1]);
            updateView.setPadding(right, top, left, 0);
        });
        waitingSince = SystemClock.elapsedRealtime();
        handler.post(tick);
    }

    /** The game screen (its own task) or the launcher now covers this one. */
    @Override
    protected void onStop() {
        super.onStop();
        handler.removeCallbacksAndMessages(null);
        finishAndRemoveTask();   // (the game screen and the launcher have tasks of their own)
    }

    private void openLauncher() {
        startActivity(new Intent(this, LauncherActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION | Intent.FLAG_ACTIVITY_NEW_TASK));
    }
}
