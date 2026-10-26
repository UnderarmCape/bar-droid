package com.underarmcape.bardroid;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;

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
        handler.postDelayed(() -> { if (!isFinishing()) { toGame = false; openLauncher(); finish(); } }, GIVE_UP_MS);
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
