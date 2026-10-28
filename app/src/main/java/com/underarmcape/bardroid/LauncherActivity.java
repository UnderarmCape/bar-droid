package com.underarmcape.bardroid;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.StatFs;
import android.view.View;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
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

        Button install = findViewById(R.id.btnInstall);
        Button play = findViewById(R.id.btnPlay);
        Button lobby = findViewById(R.id.btnLobby);
        Button glcheck = findViewById(R.id.btnGlCheck);
        Button stop = findViewById(R.id.btnStop);
        Button prefs = findViewById(R.id.btnDisplayPrefs);
        Button save = findViewById(R.id.btnSave);

        install.setOnClickListener(v -> GameService.start(this, GameService.ACTION_INSTALL, null));
        play.setOnClickListener(v -> GameService.start(this, GameService.ACTION_PLAY, "skirmish"));
        lobby.setOnClickListener(v -> GameService.start(this, GameService.ACTION_PLAY, "lobby"));
        glcheck.setOnClickListener(v -> GameService.start(this, GameService.ACTION_PLAY, "glcheck"));
        // Developer hook: long-press keeps the X display (and GPU server) up for an hour without starting the game,
        // so GL programs can be tried inside the container with tools\container-shell.bat.
        glcheck.setOnLongClickListener(v -> { GameService.start(this, GameService.ACTION_PLAY, "shell"); return true; });
        stop.setOnClickListener(v -> GameService.start(this, GameService.ACTION_STOP, null));
        prefs.setOnClickListener(v -> startActivity(new Intent(this, com.termux.x11.LoriePreferences.class)));
        save.setOnClickListener(v -> saveSettings());
        findViewById(R.id.btnShareLogs).setOnClickListener(v -> LogShare.share(this));

        findViewById(R.id.btnBench).setOnClickListener(v -> GameService.start(this, GameService.ACTION_PLAY, "bench"));

        loadSettingsIntoUi();
        deviceView.setText(deviceSummary());
        logView.setText(Log.dump());
        startFromIntent(getIntent());

        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1);
    }

    @Override protected void onNewIntent(Intent intent) { super.onNewIntent(intent); startFromIntent(intent); }

    /**
     * "start bench" in the intent starts BAR's benchmark scenario unattended (tools/phone-bench.ps1:
     * adb shell am start -n com.underarmcape.bardroid/.LauncherActivity --es start bench).
     */
    private void startFromIntent(Intent intent) {
        if (intent == null || !"bench".equals(intent.getStringExtra("start"))) return;
        intent.removeExtra("start");   // (not again when the screen is recreated)
        GameService.start(this, GameService.ACTION_PLAY, "bench");
    }

    @Override protected void onStart() { super.onStart(); Log.addListener(logListener); handler.post(ticker); }
    @Override protected void onStop() { Log.removeListener(logListener); handler.removeCallbacks(ticker); super.onStop(); }

    private void refresh() {
        Installer inst = new Installer(this, BarApp.get().paths());
        String s = GameService.status();
        statusView.setText((inst.isInstalled() ? "Installed. " : "Not installed. ") + s + "\n" + Updater.summary(BarApp.get().paths()));
    }

    private void appendLog(String line) {
        logView.append(line + "\n");
        if (logView.getLineCount() > 2500) logView.setText(Log.dump());
        logScroll.post(() -> logScroll.fullScroll(View.FOCUS_DOWN));
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
            sb.append(adreno ? "GPU: Qualcomm Adreno (/dev/kgsl-3d0 present) — supported\n"
                             : "GPU: no /dev/kgsl-3d0 — not an Adreno GPU; Mesa Freedreno/Turnip will not work on this phone\n");
        StatFs st = new StatFs(getFilesDir().getAbsolutePath());
        sb.append("Free storage: ").append(Downloader.human(st.getAvailableBytes())).append(" (need ~6 GB)\n");
        android.app.ActivityManager am = getSystemService(android.app.ActivityManager.class);
        android.app.ActivityManager.MemoryInfo mi = new android.app.ActivityManager.MemoryInfo();
        if (am != null) { am.getMemoryInfo(mi); sb.append("RAM: ").append(Downloader.human(mi.totalMem)).append(" (a match uses about 5-6 GB, part of it in swap)\n"); }
        sb.append("Engine: ").append(Prefs.engineVersion).append("  Driver: ").append(Prefs.mesaDriver);
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
        ((CheckBox) findViewById(R.id.cbMouseKeyboard)).setChecked(Prefs.mouseKeyboard);
        ((android.widget.RadioGroup) findViewById(R.id.rgFpsCap)).check(
                Prefs.fpsCap == 30 ? R.id.rbFps30 : Prefs.fpsCap == 60 ? R.id.rbFps60 : R.id.rbFpsNone);
        ((android.widget.RadioGroup) findViewById(R.id.rgRenderScale)).check(
                Prefs.renderScale == 85 ? R.id.rbRender85 : Prefs.renderScale == 70 ? R.id.rbRender70 : R.id.rbRender100);
        ((CheckBox) findViewById(R.id.cbUpscale)).setChecked(Prefs.upscale);
        ((CheckBox) findViewById(R.id.cbUpscaleCompare)).setChecked(Prefs.upscaleCompare);
        ((CheckBox) findViewById(R.id.cbLobbyBridge)).setChecked(Prefs.lobbyBridge);
        ((CheckBox) findViewById(R.id.cbAutoLobby)).setChecked(Prefs.autoLobby);
        ((CheckBox) findViewById(R.id.cbAutoUpdate)).setChecked(Prefs.autoUpdate);
        ((CheckBox) findViewById(R.id.cbNoSeccomp)).setChecked(Prefs.noSeccomp);
        ((CheckBox) findViewById(R.id.cbVerboseX)).setChecked(Prefs.verboseX);
    }

    private void saveSettings() {
        try {
            Prefs.workerThreads = Integer.parseInt(((EditText) findViewById(R.id.edWorkers)).getText().toString().trim());
        } catch (NumberFormatException e) { Toast.makeText(this, "bad number", Toast.LENGTH_SHORT).show(); return; }
        Prefs.mapName = ((EditText) findViewById(R.id.edMap)).getText().toString().trim();
        Prefs.mesaUrl = ((EditText) findViewById(R.id.edMesaUrl)).getText().toString().trim();
        boolean alt = ((CheckBox) findViewById(R.id.cbZink)).isChecked();
        Prefs.mesaDriver = Prefs.EMULATOR_BUILD ? (alt ? "llvmpipe" : "virpipe") : (alt ? "zink" : "kgsl");
        Prefs.forceCompat45 = ((CheckBox) findViewById(R.id.cbCompat45)).isChecked();
        Prefs.audio = ((CheckBox) findViewById(R.id.cbAudio)).isChecked();
        Prefs.gamepadGame = ((CheckBox) findViewById(R.id.cbGamepadGame)).isChecked();
        Prefs.rtsTouch = ((CheckBox) findViewById(R.id.cbRtsTouch)).isChecked();
        Prefs.mouseKeyboard = ((CheckBox) findViewById(R.id.cbMouseKeyboard)).isChecked();
        int cap = ((android.widget.RadioGroup) findViewById(R.id.rgFpsCap)).getCheckedRadioButtonId();
        Prefs.fpsCap = cap == R.id.rbFps30 ? 30 : cap == R.id.rbFps60 ? 60 : 0;
        int res = ((android.widget.RadioGroup) findViewById(R.id.rgRenderScale)).getCheckedRadioButtonId();
        Prefs.renderScale = res == R.id.rbRender85 ? 85 : res == R.id.rbRender70 ? 70 : 100;
        Prefs.upscale = ((CheckBox) findViewById(R.id.cbUpscale)).isChecked();
        Prefs.upscaleCompare = ((CheckBox) findViewById(R.id.cbUpscaleCompare)).isChecked();
        Prefs.lobbyBridge = ((CheckBox) findViewById(R.id.cbLobbyBridge)).isChecked();
        Prefs.autoLobby = ((CheckBox) findViewById(R.id.cbAutoLobby)).isChecked();
        Prefs.autoUpdate = ((CheckBox) findViewById(R.id.cbAutoUpdate)).isChecked();
        Prefs.noSeccomp = ((CheckBox) findViewById(R.id.cbNoSeccomp)).isChecked();
        Prefs.verboseX = ((CheckBox) findViewById(R.id.cbVerboseX)).isChecked();
        Prefs.save(this);
        deviceView.setText(deviceSummary());
        Toast.makeText(this, "Saved", Toast.LENGTH_SHORT).show();
    }
}
