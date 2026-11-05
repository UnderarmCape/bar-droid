package com.underarmcape.bardroid;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.StatFs;
import android.text.TextPaint;
import android.util.TypedValue;
import android.view.View;
import android.view.ViewGroup;
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
        fitRowOnResize((ViewGroup) install.getParent(), 14, 10);
        fitRowOnResize((ViewGroup) glcheck.getParent(), 11, 9);
        // With a gamepad or keys (out of touch mode) the focus went to the top scroll view: a grey block over the title
        // and buttons, with nothing to press. The scroll views pass it on to their buttons and settings, Play vs AI first.
        findViewById(R.id.top).setFocusable(false);
        findViewById(R.id.settings).setFocusable(false);
        play.setFocusedByDefault(true);

        loadSettingsIntoUi();
        explainSettings(findViewById(android.R.id.content), secondaryTextColor());
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

    /**
     * Side by side on a wide screen (it opens that way after a game): one over the other left the settings 90 dp. Wide
     * is 600 dp or more, upright too: the Fold7 unfolded stacked them across its whole width, lines of 1,700 pixels.
     */
    private void fitLayout() {
        boolean wide = getResources().getConfiguration().screenWidthDp >= 600;
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
        // (out into the screen's edge by its scrollbar's margin, so its text ends where the buttons' do: the layout's
        // paddingEnd, the root's clipToPadding off)
        settings.rightMargin = -findViewById(R.id.settings).getPaddingEnd();
        findViewById(R.id.settings).setLayoutParams(settings);
        // the device lines: under the buttons on a wide screen (half of that side stood empty), else first in the settings
        View device = findViewById(R.id.device);
        ViewGroup to = (ViewGroup) ((ViewGroup) findViewById(wide ? R.id.top : R.id.settings)).getChildAt(0);
        if (device.getParent() != to) {
            ((ViewGroup) device.getParent()).removeView(device);
            if (wide) to.addView(device); else to.addView(device, 0);
        }
        // and the log under them on a wide screen: below the device lines the left column stood half empty (the Fold7
        // unfolded, 2026-11-04) while the log came last, under every setting; else last in the settings
        for (View v : new View[]{findViewById(R.id.logTitle), logScroll}) {
            if (v.getParent() != to) {
                ((ViewGroup) v.getParent()).removeView(v);
                to.addView(v);
            }
        }
    }

    /** fitRow again whenever the row's width changes (the first layout, a turn, a fold). */
    private void fitRowOnResize(ViewGroup row, float maxSp, float minSp) {
        row.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> {
            if (r - l != or - ol) v.post(() -> fitRow(row, maxSp, minSp));
        });
    }

    /**
     * A row of buttons in one text size: the largest, maxSp at most and minSp at least, at which every label fits inside
     * its button's padding (LauncherButton's). Sized one by one (Android's autosize), "Benchmark" ran from edge to edge
     * of its button (dev phone, 2026-11-03), or with that padding would have shrunk alone. A label still too wide at
     * minSp (the unfolded Fold7's half-width column: "Benchmar", 2026-11-04) gets its button's side padding down to
     * 5 dp (1 dp inside the button's own shape), and only then a smaller size.
     */
    private void fitRow(ViewGroup row, float maxSp, float minSp) {
        android.util.DisplayMetrics dm = getResources().getDisplayMetrics();
        float size = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, maxSp, dm);
        float least = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, minSp, dm);
        int edge = Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 5, dm));
        for (int i = 0; i < row.getChildCount(); i++) {
            TextView b = (TextView) row.getChildAt(i);
            if (!(b.getTag() instanceof int[])) b.setTag(new int[]{b.getPaddingLeft(), b.getPaddingRight()});
            int[] pad = (int[]) b.getTag();   // (the style's padding: a wider screen gets it back)
            int room = b.getWidth() - pad[0] - pad[1];
            if (b.getWidth() <= 0) return;   // (not laid out yet)
            TextPaint p = new TextPaint(b.getPaint());
            p.setTextSize(size);
            float w = p.measureText(b.getText().toString());
            if (w > room) size *= room / w;
        }
        size = Math.max(least, (float) Math.floor(size));
        float fits = size;
        for (int i = 0; i < row.getChildCount(); i++) {
            TextView b = (TextView) row.getChildAt(i);
            int[] pad = (int[]) b.getTag();
            TextPaint p = new TextPaint(b.getPaint());
            p.setTextSize(size);
            float w = (float) Math.ceil(p.measureText(b.getText().toString()));
            int left = pad[0], right = pad[1];
            if (w > b.getWidth() - left - right) {
                left = right = Math.max(edge, (int) ((b.getWidth() - w) / 2));
                if (w > b.getWidth() - left - right) fits = Math.min(fits, size * (b.getWidth() - left - right) / w);
            }
            if (b.getPaddingLeft() != left || b.getPaddingRight() != right)
                b.setPadding(left, b.getPaddingTop(), right, b.getPaddingBottom());
        }
        size = (float) Math.floor(fits);
        for (int i = 0; i < row.getChildCount(); i++) {
            TextView b = (TextView) row.getChildAt(i);
            if (b.getTextSize() != size) b.setTextSize(TypedValue.COMPLEX_UNIT_PX, size);
        }
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
                // (a failure says so and where to look, not "Installed, game ended with an error (3)")
                : !GameService.busy() && s.startsWith("game ended with an error") ? StatusText.forPlayers(s) + ": the log below says why"
                // (what the service does, in the notification's words: "Installed, running (skirmish)" said the install
                // state with the service's own word for it)
                : GameService.busy() || (!s.equals("idle") && !s.equals("stopped") && !s.equals("game ended")) ? StatusText.forPlayers(s) : "Ready";
        android.text.SpannableString text = new android.text.SpannableString(head + (note != null ? "\n" + note : "")
                + "\n" + Updater.summary(BarApp.get().paths()));
        text.setSpan(new android.text.style.StyleSpan(android.graphics.Typeface.BOLD), 0, head.length(), 0);
        // (the two warnings in amber: among the facts they read as one more status line, dev phone 2026-11-04; a GL
        // check's or the benchmark's answer is a result, amber only when it failed: "GL check: FD740, OpenGL 4.3" in
        // amber read as a problem, 2026-11-05)
        if (note != null && !StatusText.isResultNote(note)) warn(text, head.length() + 1, head.length() + 1 + note.length());
        int miss = text.toString().indexOf(Updater.MISSES);
        if (miss >= 0) warn(text, text.toString().lastIndexOf('\n', miss) + 1, miss + Updater.MISSES.length());
        statusView.setText(text);
    }

    private static void warn(android.text.SpannableString text, int start, int end) {
        text.setSpan(new android.text.style.ForegroundColorSpan(0xFFF2B84B), start, end, 0);
    }

    /** A setting's name, and under it what it does, smaller and in the secondary colour: the text after its first line
     *  break (strings.xml). At one size and colour the settings read as one wall of text (dev phone, 2026-11-04). */
    private static void explainSettings(View v, int color) {
        if (v instanceof ViewGroup) {
            ViewGroup g = (ViewGroup) v;
            for (int i = 0; i < g.getChildCount(); i++) explainSettings(g.getChildAt(i), color);
            return;
        }
        // (the settings' boxes, and the text fields' names: style LauncherFieldLabel tags them)
        if (!(v instanceof android.widget.CompoundButton) && !(v instanceof TextView && "explain".equals(v.getTag()))) return;
        TextView t = (TextView) v;
        CharSequence s = t.getText();
        int nl = android.text.TextUtils.indexOf(s, '\n');
        if (nl < 0 || nl + 1 >= s.length()) return;
        android.text.SpannableString text = new android.text.SpannableString(s);
        text.setSpan(new android.text.style.RelativeSizeSpan(0.82f), nl + 1, s.length(), 0);
        text.setSpan(new android.text.style.ForegroundColorSpan(color), nl + 1, s.length(), 0);
        t.setText(text);
    }

    private int secondaryTextColor() {
        android.content.res.TypedArray a = obtainStyledAttributes(new int[]{android.R.attr.textColorSecondary});
        int color = a.getColor(0, 0xFFB0B0B0);
        a.recycle();
        return color;
    }

    private void appendLog(String line) {
        logFollows = logScroll.getScrollY() + logScroll.getHeight() >= logView.getHeight();
        logView.append(line + "\n");
        if (logView.getLineCount() > 2500) logView.setText(Log.dump());
        // (the service's own lines are its status: the status line follows at once, not at the next 1.5 s tick; it
        // still read "Ready" after Install / Update had begun)
        if (line.contains(" [svc] ")) refresh();
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
        sb.append("BAR Droid ").append(BuildConfig.VERSION_NAME).append(", engine ").append(Prefs.engineVersion);
        String branch = engineBranchBuild();
        if (branch != null) sb.append(" (BAR Droid build ").append(branch).append(')');
        // (the GPU driver by its name, not the setting's word: "kgsl" alone meant nothing to a player; both are Mesa's,
        // which the Mesa setting names: "(Mesa)" stood alone on a line of its own sideways)
        String driver = "kgsl".equals(Prefs.mesaDriver) ? "GPU driver Freedreno"
                : "zink".equals(Prefs.mesaDriver) ? "GPU driver Turnip + Zink"
                : "llvmpipe".equals(Prefs.mesaDriver) ? "CPU rendering (llvmpipe)"
                : "virpipe".equals(Prefs.mesaDriver) ? "virgl" : Prefs.mesaDriver;
        sb.append(", ").append(driver);
        return sb.toString();
    }

    /**
     * The engine branch's build the games start with instead of BAR's own (docs/ENGINE-SIM.md on engine/sim): its
     * files/bar/dev-env.sh names it (ENGINE="$BAR/engine-sim/gcc-fold"), else null. The launcher said BAR's version
     * while the Fold7 ran the 30 fps build (2026-11-05).
     */
    private String engineBranchBuild() {
        java.io.File f = new java.io.File(new Paths(this).bar, "dev-env.sh");
        if (!f.isFile()) return null;
        try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(f))) {
            for (String line; (line = r.readLine()) != null; ) {
                java.util.regex.Matcher m = java.util.regex.Pattern.compile("^ENGINE=\"\\$BAR/engine-sim/([^\"/]+)\"").matcher(line.trim());
                if (m.find()) return m.group(1);
            }
        } catch (java.io.IOException e) {
            return null;
        }
        return null;
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
