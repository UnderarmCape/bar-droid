package com.underarmcape.bardroid;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.StatFs;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import java.io.File;

/**
 * Device check, install, play, settings, live log. The app icon opens StartActivity (straight into the lobby); this
 * screen is long-press the icon → "Launcher", a first install, or what is left when something failed.
 */
public class LauncherActivity extends AppCompatActivity {
    private TextView statusView, deviceView, logView;
    private ScrollView logScroll;
    private Button stopButton;
    private boolean logFollows = true;   // the newest line stays in view, unless the reader has scrolled back
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Log.Listener logListener = line -> handler.post(() -> appendLog(line));
    private final Runnable ticker = new Runnable() { @Override public void run() { refresh(); handler.postDelayed(this, 1500); } };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_launcher);
        statusView = findViewById(R.id.status);
        deviceView = findViewById(R.id.device);
        logView = findViewById(R.id.log);
        logScroll = findViewById(R.id.logScroll);
        // (scrollTo: fullScroll takes the focus with it, out of a field being typed in, at every new line)
        logView.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> { if (logFollows) logScroll.scrollTo(0, b); });
        fitLayout();

        Button install = findViewById(R.id.btnInstall);
        Button play = findViewById(R.id.btnPlay);
        Button lobby = findViewById(R.id.btnLobby);
        Button glcheck = findViewById(R.id.btnGlCheck);
        stopButton = findViewById(R.id.btnStop);
        Button prefs = findViewById(R.id.btnDisplayPrefs);
        Button save = findViewById(R.id.btnSave);

        install.setOnClickListener(v -> start(GameService.ACTION_INSTALL, null));
        play.setOnClickListener(v -> start(GameService.ACTION_PLAY, "skirmish"));
        lobby.setOnClickListener(v -> start(GameService.ACTION_PLAY, "lobby"));
        glcheck.setOnClickListener(v -> start(GameService.ACTION_PLAY, "glcheck"));
        // Developer hook: long-press keeps the X display (and GPU server) up for an hour without starting the game,
        // so GL programs can be tried inside the container with tools\container-shell.bat.
        glcheck.setOnLongClickListener(v -> { GameService.start(this, GameService.ACTION_PLAY, "shell"); return true; });
        stopButton.setOnClickListener(v -> GameService.start(this, GameService.ACTION_STOP, null));
        prefs.setOnClickListener(v -> startActivity(new Intent(this, com.termux.x11.LoriePreferences.class)));
        save.setOnClickListener(v -> saveSettings(true));
        findViewById(R.id.btnShareLogs).setOnClickListener(v -> LogShare.share(this));

        findViewById(R.id.btnBench).setOnClickListener(v -> start(GameService.ACTION_PLAY, "bench"));

        loadSettingsIntoUi();
        GameService.noteLowMemoryExit(this);   // (also opened later than that: the long-press shortcut)
        deviceView.setText(deviceSummary());
        logView.setText(Log.dump());
        // (not when Android restores the screen, as it does after ending the app for lack of memory: it hands back the
        // first intent, and the game or benchmark started all over again by itself; removeExtra does not outlive that)
        if (savedInstanceState == null) startFromIntent(getIntent());

        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1);
    }

    @Override protected void onNewIntent(Intent intent) { super.onNewIntent(intent); startFromIntent(intent); }

    @Override public void onConfigurationChanged(android.content.res.Configuration c) { super.onConfigurationChanged(c); fitLayout(); }

    /** Side by side on a wide screen (it opens that way after a game): one over the other left the settings 90 dp. */
    private void fitLayout() {
        boolean wide = getResources().getConfiguration().orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE;
        int fill = LinearLayout.LayoutParams.MATCH_PARENT, wrap = LinearLayout.LayoutParams.WRAP_CONTENT;
        ((LinearLayout) findViewById(R.id.root)).setOrientation(wide ? LinearLayout.HORIZONTAL : LinearLayout.VERTICAL);
        findViewById(R.id.top).setLayoutParams(new LinearLayout.LayoutParams(wide ? 0 : fill, wide ? fill : wrap, wide ? 1 : 0));
        float dp = getResources().getDisplayMetrics().density;
        int line = Math.max(1, Math.round(dp)), gap = Math.round(12 * dp);
        LinearLayout.LayoutParams divider = new LinearLayout.LayoutParams(wide ? line : fill, wide ? fill : line);
        divider.leftMargin = wide ? gap : 0;
        divider.topMargin = wide ? 0 : Math.round(6 * dp);
        findViewById(R.id.divider).setLayoutParams(divider);
        LinearLayout.LayoutParams settings = new LinearLayout.LayoutParams(wide ? 0 : fill, wide ? fill : 0, 1);
        settings.leftMargin = wide ? gap : 0;
        findViewById(R.id.settings).setLayoutParams(settings);
    }

    /** A start takes what the screen shows: a setting changed and left unsaved was ignored without a word. */
    private void start(String action, String mode) {
        saveSettings(false);
        GameService.start(this, action, mode);
    }

    /**
     * "start bench" in the intent starts BAR's benchmark scenario unattended (tools/phone-bench.ps1:
     * adb shell am start -n com.underarmcape.bardroid/.LauncherActivity --es start bench); "start skirmish" the
     * Play vs AI game (tools/phone-memory.ps1).
     */
    private void startFromIntent(Intent intent) {
        String start = intent == null ? null : intent.getStringExtra("start");
        if (!"bench".equals(start) && !"skirmish".equals(start)) return;
        intent.removeExtra("start");   // (not again when the screen is recreated)
        GameService.start(this, GameService.ACTION_PLAY, start);
    }

    @Override protected void onStart() { super.onStart(); Log.addListener(logListener); handler.post(ticker); }
    @Override protected void onStop() { Log.removeListener(logListener); handler.removeCallbacks(ticker); super.onStop(); }

    private void refresh() {
        Installer inst = new Installer(this, BarApp.get().paths());
        String s = GameService.status();
        // (nothing to stop: dim, not off: after a crash here "idle" can hide a game's processes, which Stop still ends)
        stopButton.setAlpha(GameService.busy() ? 1f : 0.5f);
        // (again on each refresh in the process's first 20 s: Android restarts the app within a second of ending it and
        // files the reason a moment later, so the launcher it restores asked too early; an IPC, not for every tick)
        if (android.os.SystemClock.elapsedRealtime() - android.os.Process.getStartElapsedRealtime() < 20_000)
            GameService.noteLowMemoryExit(this);
        String note = GameService.exitNote();
        String head = !inst.isInstalled() ? "Not installed, " + s
                : GameService.busy() || (!s.equals("idle") && !s.equals("stopped")) ? "Installed, " + s : "Ready";
        android.text.SpannableString text = new android.text.SpannableString(head + (note != null ? "\n" + note : "")
                + "\n" + Updater.summary(BarApp.get().paths()));
        text.setSpan(new android.text.style.StyleSpan(android.graphics.Typeface.BOLD), 0, head.length(), 0);
        statusView.setText(text);
    }

    private void appendLog(String line) {
        logFollows = logScroll.getScrollY() + logScroll.getHeight() >= logView.getHeight();
        logView.append(line + "\n");
        if (logView.getLineCount() > 2500) logView.setText(Log.dump());
    }

    /**
     * An 8 GB phone (it reports ~7.2 GB; a 12 GB phone ~11 GB): launch-bar.sh starts the game in its low-memory mode
     * there (MemTotal under the same 9.5 GB), without which Android ended every game while it loaded (a Galaxy S23
     * Ultra, 2026-10-29).
     */
    static boolean lowRam(android.content.Context c) {
        android.app.ActivityManager am = c.getSystemService(android.app.ActivityManager.class);
        if (am == null) return false;
        android.app.ActivityManager.MemoryInfo mi = new android.app.ActivityManager.MemoryInfo();
        am.getMemoryInfo(mi);
        return mi.totalMem < 9_500_000_000L;
    }

    private String deviceSummary() {
        StringBuilder sb = new StringBuilder();
        sb.append(Build.MANUFACTURER).append(' ').append(Build.MODEL).append(", Android ").append(Build.VERSION.RELEASE)
          .append(", SoC ").append(Build.VERSION.SDK_INT >= 31 ? Build.SOC_MODEL : Build.HARDWARE).append('\n');
        boolean adreno = new File("/dev/kgsl-3d0").exists();
        if (Prefs.EMULATOR_BUILD)
            sb.append("Emulator build (x86_64): OpenGL ")
              .append("virpipe".equals(Prefs.mesaDriver) ? "on the GPU through Android's GLES (virgl)" : "on the CPU (llvmpipe), slow")
              .append("; ").append(Runtime.getRuntime().availableProcessors()).append(" CPU cores\n");
        else
            sb.append(adreno ? "GPU: Qualcomm Adreno, supported\n"
                             : "GPU: not a Qualcomm Adreno: BAR's graphics will not work on this phone\n");
        StatFs st = new StatFs(getFilesDir().getAbsolutePath());
        sb.append("Free storage: ").append(Downloader.human(st.getAvailableBytes())).append(" (need ~6 GB)\n");
        android.app.ActivityManager am = getSystemService(android.app.ActivityManager.class);
        android.app.ActivityManager.MemoryInfo mi = new android.app.ActivityManager.MemoryInfo();
        if (am != null) {
            am.getMemoryInfo(mi);
            sb.append("RAM: ").append(Downloader.human(mi.totalMem));
            if (lowRam(this)) sb.append(" — low-memory mode: plainer unit shading and map detail, skirmish on a smaller map; close other apps before a game\n");
            else sb.append(" (a match uses about 5-6 GB, part of it in swap)\n");
        }
        sb.append("BAR Droid ").append(BuildConfig.VERSION_NAME).append(", engine ").append(Prefs.engineVersion)
          .append(", ").append(Prefs.mesaDriver);
        return sb.toString();
    }

    private void loadSettingsIntoUi() {
        ((EditText) findViewById(R.id.edWorkers)).setText(String.valueOf(Prefs.workerThreads));
        ((EditText) findViewById(R.id.edMap)).setText(Prefs.mapName);
        ((EditText) findViewById(R.id.edMesaUrl)).setText(Prefs.mesaUrl);
        CheckBox alt = findViewById(R.id.cbZink);
        alt.setChecked("zink".equals(Prefs.mesaDriver) || "llvmpipe".equals(Prefs.mesaDriver));
        if (Prefs.EMULATOR_BUILD) {   // no Adreno: GPU via virgl, or CPU rendering for comparison
            alt.setText(R.string.cb_llvmpipe);
            findViewById(R.id.edMesaUrl).setEnabled(false);
        }
        ((CheckBox) findViewById(R.id.cbCompat45)).setChecked(Prefs.forceCompat45);
        ((CheckBox) findViewById(R.id.cbAudio)).setChecked(Prefs.audio);
        ((CheckBox) findViewById(R.id.cbGamepadGame)).setChecked(Prefs.gamepadGame);
        ((CheckBox) findViewById(R.id.cbRtsTouch)).setChecked(Prefs.rtsTouch);
        ((CheckBox) findViewById(R.id.cbCaptureShortcuts)).setChecked(Prefs.captureShortcuts);
        ((android.widget.RadioGroup) findViewById(R.id.rgFpsCap)).check(
                Prefs.fpsCap == 30 ? R.id.rbFps30 : Prefs.fpsCap == 60 ? R.id.rbFps60 : R.id.rbFpsNone);
        ((android.widget.RadioGroup) findViewById(R.id.rgRenderScale)).check(
                Prefs.renderScale == 85 ? R.id.rbRender85 : Prefs.renderScale == 70 ? R.id.rbRender70
                        : Prefs.renderScale == 0 ? R.id.rbRenderNative : R.id.rbRender100);
        ((CheckBox) findViewById(R.id.cbUpscale)).setChecked(Prefs.upscale);
        ((CheckBox) findViewById(R.id.cbUpscaleCompare)).setChecked(Prefs.upscaleCompare);
        ((CheckBox) findViewById(R.id.cbLobbyBridge)).setChecked(Prefs.lobbyBridge);
        ((CheckBox) findViewById(R.id.cbAutoLobby)).setChecked(Prefs.autoLobby);
        ((CheckBox) findViewById(R.id.cbAutoUpdate)).setChecked(Prefs.autoUpdate);
        ((CheckBox) findViewById(R.id.cbNoSeccomp)).setChecked(Prefs.noSeccomp);
        ((CheckBox) findViewById(R.id.cbVerboseX)).setChecked(Prefs.verboseX);
    }

    private void saveSettings(boolean say) {
        EditText workers = findViewById(R.id.edWorkers);
        try {
            int n = Integer.parseInt(workers.getText().toString().trim());
            if (n < 1) throw new NumberFormatException();
            Prefs.workerThreads = n;
        } catch (NumberFormatException e) {   // (only this one: giving up here lost the screen's other changes too)
            workers.setText(String.valueOf(Prefs.workerThreads));
            Toast.makeText(this, "Worker threads: a number from 1, kept " + Prefs.workerThreads, Toast.LENGTH_SHORT).show();
        }
        String map = ((EditText) findViewById(R.id.edMap)).getText().toString().trim();
        if (map.isEmpty()) ((EditText) findViewById(R.id.edMap)).setText(Prefs.mapName);   // (no game starts on no map)
        else {
            if (!map.equals(Prefs.mapName)) Prefs.mapChosen = true;   // (the player's from now on, also on an 8 GB phone)
            Prefs.mapName = map;
        }
        // (the field wraps: an Enter typed in it is no part of the address, nor is any space)
        EditText mesaField = findViewById(R.id.edMesaUrl);
        String mesa = mesaField.getText().toString().replaceAll("\\s", "");
        if (mesa.isEmpty() && !Prefs.EMULATOR_BUILD) mesaField.setText(Prefs.mesaUrl);   // (none is the emulator's: CPU drawing)
        else Prefs.mesaUrl = mesa;
        boolean alt = ((CheckBox) findViewById(R.id.cbZink)).isChecked();
        Prefs.mesaDriver = Prefs.EMULATOR_BUILD ? (alt ? "llvmpipe" : "virpipe") : (alt ? "zink" : "kgsl");
        Prefs.forceCompat45 = ((CheckBox) findViewById(R.id.cbCompat45)).isChecked();
        Prefs.audio = ((CheckBox) findViewById(R.id.cbAudio)).isChecked();
        Prefs.gamepadGame = ((CheckBox) findViewById(R.id.cbGamepadGame)).isChecked();
        Prefs.rtsTouch = ((CheckBox) findViewById(R.id.cbRtsTouch)).isChecked();
        Prefs.captureShortcuts = ((CheckBox) findViewById(R.id.cbCaptureShortcuts)).isChecked();
        int cap = ((android.widget.RadioGroup) findViewById(R.id.rgFpsCap)).getCheckedRadioButtonId();
        Prefs.fpsCap = cap == R.id.rbFps30 ? 30 : cap == R.id.rbFps60 ? 60 : 0;
        int res = ((android.widget.RadioGroup) findViewById(R.id.rgRenderScale)).getCheckedRadioButtonId();
        Prefs.renderScale = res == R.id.rbRender85 ? 85 : res == R.id.rbRender70 ? 70 : res == R.id.rbRenderNative ? 0 : 100;
        Prefs.upscale = ((CheckBox) findViewById(R.id.cbUpscale)).isChecked();
        Prefs.upscaleCompare = ((CheckBox) findViewById(R.id.cbUpscaleCompare)).isChecked();
        Prefs.lobbyBridge = ((CheckBox) findViewById(R.id.cbLobbyBridge)).isChecked();
        Prefs.autoLobby = ((CheckBox) findViewById(R.id.cbAutoLobby)).isChecked();
        Prefs.autoUpdate = ((CheckBox) findViewById(R.id.cbAutoUpdate)).isChecked();
        Prefs.noSeccomp = ((CheckBox) findViewById(R.id.cbNoSeccomp)).isChecked();
        Prefs.verboseX = ((CheckBox) findViewById(R.id.cbVerboseX)).isChecked();
        Prefs.save(this);
        deviceView.setText(deviceSummary());
        if (say) Toast.makeText(this, "Saved", Toast.LENGTH_SHORT).show();
    }
}
