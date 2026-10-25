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

/** Home screen: device check, install, play, settings, live log. */
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
        stop.setOnClickListener(v -> GameService.start(this, GameService.ACTION_STOP, null));
        prefs.setOnClickListener(v -> startActivity(new Intent(this, com.termux.x11.LoriePreferences.class)));
        save.setOnClickListener(v -> saveSettings());

        loadSettingsIntoUi();
        deviceView.setText(deviceSummary());
        logView.setText(Log.dump());

        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1);
    }

    @Override protected void onStart() { super.onStart(); Log.addListener(logListener); handler.post(ticker); }
    @Override protected void onStop() { Log.removeListener(logListener); handler.removeCallbacks(ticker); super.onStop(); }

    private void refresh() {
        Installer inst = new Installer(this, BarApp.get().paths());
        String s = GameService.status();
        statusView.setText((inst.isInstalled() ? "Installed. " : "Not installed. ") + s);
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
        sb.append(adreno ? "GPU: Qualcomm Adreno (/dev/kgsl-3d0 present) — supported\n"
                         : "GPU: no /dev/kgsl-3d0 — not an Adreno GPU; Mesa Freedreno/Turnip will not work on this phone\n");
        StatFs st = new StatFs(getFilesDir().getAbsolutePath());
        sb.append("Free storage: ").append(Downloader.human(st.getAvailableBytes())).append(" (need ~6 GB)\n");
        android.app.ActivityManager am = getSystemService(android.app.ActivityManager.class);
        android.app.ActivityManager.MemoryInfo mi = new android.app.ActivityManager.MemoryInfo();
        if (am != null) { am.getMemoryInfo(mi); sb.append("RAM: ").append(Downloader.human(mi.totalMem)).append(" (BAR wants 12 GB)\n"); }
        sb.append("Engine: ").append(Prefs.engineVersion).append("  Driver: ").append(Prefs.mesaDriver);
        return sb.toString();
    }

    private void loadSettingsIntoUi() {
        ((EditText) findViewById(R.id.edWorkers)).setText(String.valueOf(Prefs.workerThreads));
        ((EditText) findViewById(R.id.edUiScale)).setText(String.valueOf(Prefs.uiScale));
        ((EditText) findViewById(R.id.edMap)).setText(Prefs.mapName);
        ((EditText) findViewById(R.id.edMesaUrl)).setText(Prefs.mesaUrl);
        ((CheckBox) findViewById(R.id.cbZink)).setChecked("zink".equals(Prefs.mesaDriver));
        ((CheckBox) findViewById(R.id.cbCompat45)).setChecked(Prefs.forceCompat45);
        ((CheckBox) findViewById(R.id.cbAudio)).setChecked(Prefs.audio);
        ((CheckBox) findViewById(R.id.cbShadows)).setChecked(Prefs.shadows);
        ((CheckBox) findViewById(R.id.cbNoSeccomp)).setChecked(Prefs.noSeccomp);
        ((CheckBox) findViewById(R.id.cbVerboseX)).setChecked(Prefs.verboseX);
    }

    private void saveSettings() {
        try {
            Prefs.workerThreads = Integer.parseInt(((EditText) findViewById(R.id.edWorkers)).getText().toString().trim());
            Prefs.uiScale = Float.parseFloat(((EditText) findViewById(R.id.edUiScale)).getText().toString().trim());
        } catch (NumberFormatException e) { Toast.makeText(this, "bad number", Toast.LENGTH_SHORT).show(); return; }
        Prefs.mapName = ((EditText) findViewById(R.id.edMap)).getText().toString().trim();
        Prefs.mesaUrl = ((EditText) findViewById(R.id.edMesaUrl)).getText().toString().trim();
        Prefs.mesaDriver = ((CheckBox) findViewById(R.id.cbZink)).isChecked() ? "zink" : "kgsl";
        Prefs.forceCompat45 = ((CheckBox) findViewById(R.id.cbCompat45)).isChecked();
        Prefs.audio = ((CheckBox) findViewById(R.id.cbAudio)).isChecked();
        Prefs.shadows = ((CheckBox) findViewById(R.id.cbShadows)).isChecked();
        Prefs.noSeccomp = ((CheckBox) findViewById(R.id.cbNoSeccomp)).isChecked();
        Prefs.verboseX = ((CheckBox) findViewById(R.id.cbVerboseX)).isChecked();
        Prefs.save(this);
        deviceView.setText(deviceSummary());
        Toast.makeText(this, "Saved", Toast.LENGTH_SHORT).show();
    }
}
