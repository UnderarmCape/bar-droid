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
            updateView.setText(updating ? s.replaceFirst("^update: ", "") : "");
            if (now - waitingSince > GIVE_UP_MS) { toGame = false; openLauncher(); finish(); return; }
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
                finish();
            }
            return;
        }
        if (!Prefs.autoLobby || !new Installer(this, BarApp.get().paths()).isInstalled() || Prefs.lobbyFailedFast(this)) {
            if (Prefs.lobbyFailedFast(this)) Log.i("app", "the lobby failed on its last start: showing the launcher");
            openLauncher();
            finish();
            return;
        }
        GameService.start(this, GameService.ACTION_PLAY, "lobby");
        toGame = true;
        updateView = new TextView(this);
        updateView.setTextColor(0xffb0b0b0);
        updateView.setTextSize(14);
        updateView.setGravity(Gravity.CENTER_HORIZONTAL | Gravity.BOTTOM);
        updateView.setPadding(0, 0, 0, 48);
        setContentView(updateView, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        waitingSince = SystemClock.elapsedRealtime();
        handler.post(tick);
    }

    /** The game screen (its own task) or the launcher now covers this one. */
    @Override
    protected void onStop() {
        super.onStop();
        handler.removeCallbacksAndMessages(null);
        if (toGame) finishAndRemoveTask();
        else finish();
    }

    private void openLauncher() {
        startActivity(new Intent(this, LauncherActivity.class));
        overridePendingTransition(0, 0);
    }
}
