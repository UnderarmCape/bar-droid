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
        // (the box as tall as its lines, up to the layout's 300 dp: after a start two lines sat over an empty dark box
        // the screen's height tall, dev phone 2026-11-08; the log is last in its column, nothing moves under it)
        final int logMax = logScroll.getLayoutParams().height;
        logView.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> {
            int want = Math.min(logMax, b - t);
            android.view.ViewGroup.LayoutParams lp = logScroll.getLayoutParams();
            if (want > 0 && lp.height != want) {
                lp.height = want;
                logScroll.post(() -> logScroll.setLayoutParams(lp));
            }
        });
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
        for (int id : new int[]{R.id.rgFpsCap, R.id.rgRenderScale, R.id.rgMapCap}) {
            android.widget.RadioGroup g = findViewById(id);
            g.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> {
                if (r - l != or - ol) v.post(() -> fitChoices(g));
            });
        }
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
    private ViewGroup topContent;   // the title, status lines and buttons: in the top block, or first on the one page

    private void fitLayout() {
        android.content.res.Configuration cfg = getResources().getConfiguration();
        boolean wide = cfg.screenWidthDp >= 600;
        // One scrolling page on a narrow screen that is not much taller than wide (under 600 dp, under 1.5 times as tall:
        // the dev phone at 1080x1198, large display sizes): one over the other the top block took the height it needs
        // and left the settings one line, or none (2026-11-12). Kailil, 2026-11-12: "one scrolling page". The top
        // block's content goes first in the settings' scroll; a tall phone keeps its buttons in sight above them.
        boolean onePage = !wide && cfg.screenHeightDp < cfg.screenWidthDp * 1.5f;
        ScrollView topScroll = findViewById(R.id.top);
        ViewGroup settingsContent = (ViewGroup) ((ViewGroup) findViewById(R.id.settings)).getChildAt(0);
        if (topContent == null) topContent = (ViewGroup) topScroll.getChildAt(0);
        ViewGroup topHome = onePage ? settingsContent : topScroll;
        if (topContent.getParent() != topHome) {
            ((ViewGroup) topContent.getParent()).removeView(topContent);
            if (onePage) settingsContent.addView(topContent, 0); else topScroll.addView(topContent);
        }
        topScroll.setVisibility(onePage ? View.GONE : View.VISIBLE);
        findViewById(R.id.divider).setVisibility(onePage ? View.GONE : View.VISIBLE);
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
        ViewGroup to = wide ? topContent : settingsContent;
        if (device.getParent() != to) {
            ((ViewGroup) device.getParent()).removeView(device);
            if (wide) to.addView(device); else to.addView(device, onePage ? 1 : 0);   // (one page: under the buttons)
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

    /**
     * A row of choices kept on one line: their words a step smaller at a time (to 70 % at most) until each one's circle,
     * padding and words fit the row together. At their full size "Native" wrapped as "Nativ e" on the unfolded Fold7's
     * width (dev phone at 1198x1080); equal shares of the row made "100%" wrap too. Full size wherever they fit.
     */
    private void fitChoices(android.widget.RadioGroup g) {
        int room = g.getWidth() - g.getPaddingLeft() - g.getPaddingRight();
        if (room <= 0 || g.getChildCount() == 0) return;
        Float base = (Float) g.getTag(R.id.rgFpsCap);   // (the words' own size, kept: this runs at every resize)
        if (base == null) {
            base = ((TextView) g.getChildAt(0)).getTextSize();
            g.setTag(R.id.rgFpsCap, base);
        }
        float size = base;
        // (in twentieths: k -= 0.05f came to 0.69999993 after six steps, under 0.7f, and 70 % was never tried)
        for (int k = 20; k >= 14; k--) {
            size = base * k / 20f;
            float need = 0;
            for (int i = 0; i < g.getChildCount(); i++) {
                TextView b = (TextView) g.getChildAt(i);
                android.graphics.Paint p = new android.graphics.Paint(b.getPaint());
                p.setTextSize(size);
                need += p.measureText(b.getText().toString()) + b.getCompoundPaddingLeft() + b.getCompoundPaddingRight();
            }
            if (need <= room) break;
        }
        for (int i = 0; i < g.getChildCount(); i++) {
            ((TextView) g.getChildAt(i)).setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, size);
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
    private static final int[] START_BUTTONS = { R.id.btnInstall, R.id.btnPlay, R.id.btnLobby, R.id.btnGlCheck, R.id.btnBench };

    private void start(String action, String mode) {
        saveSettings(false);
        if (GameService.busy()) {   // (the service ignores it: said, not a tap that did nothing)
            Toast.makeText(this, "A game is running: Stop ends it", Toast.LENGTH_SHORT).show();
            return;
        }
        GameService.start(this, action, mode);
    }

    /**
     * Leaving the launcher keeps what it shows too (Kailil's Fold7, 2026-11-09: "Play upright" ticked, the launcher left
     * by Home and the lobby opened from the app icon: the box was never saved and the lobby stayed sideways).
     */
    @Override
    protected void onPause() {
        saveSettings(false);
        super.onPause();
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

    @Override protected void onStart() {
        super.onStart();
        Log.addListener(logListener);
        handler.post(ticker);
        mapCapLabel();   // (the maps' size now: a game since may have downloaded some, its start removed others)
        // (and the device lines: a phone build set aside by the game since, or a BAR update, changed the engine line;
        // it said "(phone build)" until the launcher was made again; review 2026-11-16)
        deviceView.setText(deviceSummary());
        refreshMapList();
    }

    private android.widget.ArrayAdapter<String> mapsAdapter;
    private long mapsStamp;

    /** The newest engine archive cache's time (0: none): it changes when an engine run scanned the maps again. */
    static long archiveCacheStamp(File bar) {
        File[] caches = new File(bar, "cache").listFiles((d, n) -> n.startsWith("ArchiveCache") && n.endsWith(".lua"));
        long newest = 0;
        for (File f : caches == null ? new File[0] : caches) newest = Math.max(newest, f.lastModified());
        return newest;
    }

    /**
     * Play vs AI's map list made again when the engine's archive cache changed: it was made once, when the launcher was
     * created, and kept the maps of then after a game downloaded others or the map storage limit removed some. The
     * cache is ~4.6 MB, read only when it changed (dev phone, 2026-11-12).
     */
    private void refreshMapList() {
        File bar = new Paths(this).bar;
        long stamp = archiveCacheStamp(bar);
        if (mapsAdapter == null || stamp == mapsStamp) return;
        mapsStamp = stamp;
        java.util.List<String> now = installedMaps(bar);
        mapsAdapter.clear();
        mapsAdapter.addAll(now);
        Log.i("app", "map list made again: " + now.size() + " maps");   // (tools)
    }
    @Override protected void onStop() { Log.removeListener(logListener); handler.removeCallbacks(ticker); super.onStop(); }

    private void refresh() {
        Installer inst = new Installer(this, BarApp.get().paths());
        String s = GameService.status();
        // (nothing to stop: dim, not off: after a crash here "idle" can hide a game's processes, which Stop still ends)
        stopButton.setAlpha(GameService.busy() ? 1f : 0.5f);
        // (and the buttons that start something dim while a game runs: the service takes no start then, and they looked
        // ready, dev phone 2026-11-16; a tap says so, start)
        for (int id : START_BUTTONS) {
            View b = findViewById(id);
            if (b != null) b.setAlpha(GameService.busy() ? 0.5f : 1f);
        }
        // (again on each refresh in the process's first 20 s: Android restarts the app within a second of ending it and
        // files the reason a moment later, so the launcher it restores asked too early; an IPC, not for every tick)
        if (android.os.SystemClock.elapsedRealtime() - android.os.Process.getStartElapsedRealtime() < 20_000)
            GameService.noteLowMemoryExit(this);
        String note = GameService.exitNote();
        String head = !inst.isInstalled() ? "Not installed, " + s
                // (a failure says so and where to look, not "Installed, game ended with an error (3)")
                // (with a note under it, the engine's own message, that note says why)
                : !GameService.busy() && s.startsWith("game ended with an error") ? StatusText.forPlayers(s) + (note != null ? "" : ": the log below says why")
                // (what the service does, in the notification's words: "Installed, running (skirmish)" said the install
                // state with the service's own word for it)
                : GameService.busy() || (!s.equals("idle") && !s.equals("stopped") && !s.equals("game ended")) ? StatusText.forPlayers(s) : "Ready";
        String summary = Updater.summary(BarApp.get().paths());
        android.text.SpannableString text = new android.text.SpannableString(head + (note != null ? "\n" + note : "")
                + "\n" + summary);
        text.setSpan(new android.text.style.StyleSpan(android.graphics.Typeface.BOLD), 0, head.length(), 0);
        // (the version and update lines grey, as the device lines under the buttons are: all in white at the status's
        // size, "Ready" read as one more line of four, dev phone 2026-11-16; a miss in them still turns amber below)
        text.setSpan(new android.text.style.ForegroundColorSpan(secondaryTextColor()), text.length() - summary.length(),
                text.length(), 0);
        // (the two warnings in amber: among the facts they read as one more status line, dev phone 2026-11-04; a GL
        // check's or the benchmark's answer is a result, amber only when it failed: "GL check: FD740, OpenGL 4.3" in
        // amber read as a problem, 2026-11-05)
        if (note != null && !StatusText.isResultNote(note)) {
            // (a note's first line is the warning; lines after it, what to do, as a setting's explanation: smaller, grey)
            int at = head.length() + 1, nl = note.indexOf('\n');
            warn(text, at, at + (nl < 0 ? note.length() : nl));
            if (nl >= 0) {
                text.setSpan(new android.text.style.RelativeSizeSpan(0.82f), at + nl + 1, at + note.length(), 0);
                text.setSpan(new android.text.style.ForegroundColorSpan(secondaryTextColor()), at + nl + 1, at + note.length(), 0);
            }
        }
        int miss = text.toString().indexOf(Updater.MISSES);
        if (miss >= 0) {
            int end = miss + Updater.MISSES.length();
            warn(text, text.toString().lastIndexOf('\n', miss) + 1, end);
            // (the miss it names, under it as a setting's explanation is: in amber at full size, two lines of an engine
            // key's name read as a second, louder warning, dev phone 2026-11-11)
            int detail = text.toString().indexOf('\n', end + 1);
            if (detail < 0) detail = text.length();
            if (end + 1 < detail) {
                text.setSpan(new android.text.style.RelativeSizeSpan(0.82f), end + 1, detail, 0);
                text.setSpan(new android.text.style.ForegroundColorSpan(secondaryTextColor()), end + 1, detail, 0);
            }
        }
        statusView.setText(text);
    }

    private static String gb(long bytes) {
        return String.format(java.util.Locale.US, "%.1f GB", bytes / 1073741824.0);
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

    /** "Samsung SM-S918U": Android's lowercase maker capitalised; a model that starts with the maker ("Xiaomi 14") alone. */
    static String phoneName(String maker, String model) {
        maker = maker == null ? "" : maker.trim();
        model = model == null ? "" : model.trim();
        if (maker.isEmpty() || model.toLowerCase(java.util.Locale.ROOT).startsWith(maker.toLowerCase(java.util.Locale.ROOT)))
            return model.isEmpty() ? maker : model;
        String m = maker.equals(maker.toLowerCase(java.util.Locale.ROOT))
                ? Character.toUpperCase(maker.charAt(0)) + maker.substring(1) : maker;   // (OnePlus, HMD keep theirs)
        return model.isEmpty() ? m : m + " " + model;
    }

    private CharSequence deviceSummary() {
        StringBuilder sb = new StringBuilder();
        sb.append(phoneName(Build.MANUFACTURER, Build.MODEL)).append(", Android ").append(Build.VERSION.RELEASE)
          .append(", SoC ").append(Build.VERSION.SDK_INT >= 31 ? Build.SOC_MODEL : Build.HARDWARE).append('\n');
        boolean adreno = new File("/dev/kgsl-3d0").exists();
        // (the GPU driver by its name, not the setting's word: "kgsl" alone meant nothing to a player; both are Mesa's,
        // which the Mesa setting names. On the GPU's line: at the end of the version line it wrapped, "Freedreno" alone
        // on a line under "GPU driver", dev phone 2026-11-15)
        String driver = "kgsl".equals(Prefs.mesaDriver) ? "driver Freedreno"
                : "zink".equals(Prefs.mesaDriver) ? "driver Turnip + Zink"
                : "llvmpipe".equals(Prefs.mesaDriver) ? "drawn on the CPU (llvmpipe)" : Prefs.mesaDriver;
        if (Prefs.EMULATOR_BUILD)
            sb.append("Emulator build (x86_64): OpenGL ")
              .append("virpipe".equals(Prefs.mesaDriver) ? "on the GPU through Android's GLES (virgl)" : "on the CPU (llvmpipe), slow")
              .append("; ").append(Runtime.getRuntime().availableProcessors()).append(" CPU cores\n");
        else
            sb.append(adreno ? "GPU: Qualcomm Adreno, supported; " + driver + "\n"
                             : "GPU: not a Qualcomm Adreno: BAR's graphics will not work on this phone\n");
        StatFs st = new StatFs(getFilesDir().getAbsolutePath());
        // (one decimal: "75.85 GB" and "6.91 GB" said more than a player reads there; downloads keep two, Downloader.human)
        sb.append("Free storage: ").append(gb(st.getAvailableBytes())).append(" (need ~6 GB)\n");
        android.app.ActivityManager am = getSystemService(android.app.ActivityManager.class);
        android.app.ActivityManager.MemoryInfo mi = new android.app.ActivityManager.MemoryInfo();
        if (am != null) {
            am.getMemoryInfo(mi);
            sb.append("RAM: ").append(gb(mi.totalMem));
            // (the mode's name on the RAM line, what it does under it a step smaller: run on after an em dash, the
            // sentence wrapped over three lines and read as one more fact, dev phone 2026-11-08)
            // (the smaller map only while it is the app's choice, Prefs.mapName: a map the player picked is theirs)
            // (a capital first, as each setting's explanation beside it: in lower case it read as a cut-off line)
            if (lowRam(this)) sb.append(", low-memory mode\n").append(NOTE_START)
                    .append("Plainer unit shading and map detail")
                    .append(!Prefs.mapChosen && Installer.BENCH_MAP.equals(Prefs.mapName) ? ", skirmish on a smaller map" : "")
                    .append("; close other apps before a game")
                    .append(NOTE_END).append('\n');
            else sb.append('\n').append(NOTE_START).append("A match uses about 5-6 GB, part of it in swap").append(NOTE_END).append('\n');
        }
        sb.append("BAR Droid ").append(BuildConfig.VERSION_NAME).append(", engine ").append(Prefs.engineVersion);
        String branch = engineBranchBuild();
        if (branch != null) sb.append(" (BAR Droid build ").append(branch).append(')');
        else if (Prefs.phoneEngine) {   // (Installer.installPhoneEngine; launch-bar.sh starts it, or BAR's official one
            // after the build could not run: its name in .bardroid-phone-failed)
            File bar = new Paths(this).bar, phone = new File(bar, "engine/recoil_" + Prefs.engineVersion + "-phone");
            if (new File(phone, "spring").isFile()) {
                String build = firstLine(new File(phone, "BUILD.txt"));
                sb.append(build != null && build.equals(firstLine(new File(bar, ".bardroid-phone-failed")))
                        ? " (official: the phone build could not run here)" : " (phone build)");
            }
        }
        return styleSummary(sb.toString());
    }

    private static final char NOTE_START = '\u0002', NOTE_END = '\u0003';

    /** The phone's name in the primary colour, as the block's title; a note (between NOTE_START and NOTE_END) a step
     *  smaller. In one colour and size the block read as a wall of facts (dev phone, 2026-11-08). */
    private CharSequence styleSummary(String s) {
        android.text.SpannableStringBuilder b = new android.text.SpannableStringBuilder();
        int at = 0;
        java.util.List<int[]> notes = new java.util.ArrayList<>();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == NOTE_START) at = b.length();
            else if (c == NOTE_END) notes.add(new int[]{at, b.length()});
            else b.append(c);
        }
        int nl = android.text.TextUtils.indexOf(b, '\n');
        if (nl > 0) {
            android.content.res.TypedArray a = obtainStyledAttributes(new int[]{android.R.attr.textColorPrimary});
            int primary = a.getColor(0, 0xFFFFFFFF);
            a.recycle();
            b.setSpan(new android.text.style.ForegroundColorSpan(primary), 0, nl, 0);
            b.setSpan(new android.text.style.StyleSpan(android.graphics.Typeface.BOLD), 0, nl, 0);
        }
        for (int[] n : notes) b.setSpan(new android.text.style.RelativeSizeSpan(0.88f), n[0], n[1], 0);
        return b;
    }

    /**
     * The engine branch's build the games start with instead of BAR's own (docs/ENGINE-SIM.md on engine/sim): its
     * files/bar/dev-env.sh names it (ENGINE="$BAR/engine-sim/gcc-fold"), else null. The launcher said BAR's version
     * while the Fold7 ran the 30 fps build (2026-11-05).
     */
    /** A small text file's first line, trimmed; null when there is none. */
    private static String firstLine(File f) {
        if (!f.isFile()) return null;
        try (java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(f))) {
            String l = r.readLine();
            return l == null ? null : l.trim();
        } catch (java.io.IOException e) {
            return null;
        }
    }

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

    /**
     * The maps installed, by the names BAR lists them under ("Starwatcher 1.0"): the engine's archive cache
     * (cache/ArchiveCache*.lua, each archive's archivedata; a map's modtype is 3), sorted. Empty before a first game.
     */
    static java.util.List<String> installedMaps(File bar) {
        java.util.TreeSet<String> out = new java.util.TreeSet<>(String.CASE_INSENSITIVE_ORDER);
        File[] caches = new File(bar, "cache").listFiles((d, n) -> n.startsWith("ArchiveCache") && n.endsWith(".lua"));
        if (caches == null || caches.length == 0) return new java.util.ArrayList<>(out);
        java.util.Arrays.sort(caches, (a, b) -> Long.compare(b.lastModified(), a.lastModified()));   // (the newest)
        String text;
        try {
            text = new String(java.nio.file.Files.readAllBytes(caches[0].toPath()), java.nio.charset.StandardCharsets.UTF_8);
        } catch (java.io.IOException | OutOfMemoryError e) {
            return new java.util.ArrayList<>(out);
        }
        // (each archive's data, to the next one's: its own fields one tab deeper than "archivedata", nested tables such
        // as a dependency list deeper still)
        String[] parts = text.split("archivedata = \\{");
        java.util.regex.Pattern lead = java.util.regex.Pattern.compile("(\\t+)archivedata = \\{");
        for (int i = 1; i < parts.length; i++) {
            java.util.regex.Matcher t = lead.matcher(parts[i - 1].substring(Math.max(0, parts[i - 1].lastIndexOf('\n'))) + "archivedata = {");
            String tabs = (t.find() ? t.group(1) : "\t\t\t") + "\t";
            java.util.regex.Matcher type = java.util.regex.Pattern.compile("\\n" + tabs + "modtype = (\\d+),").matcher(parts[i]);
            java.util.regex.Matcher m = java.util.regex.Pattern.compile("\\n" + tabs + "name = \"([^\"]+)\",").matcher(parts[i]);
            if (type.find() && "3".equals(type.group(1)) && m.find()) out.add(m.group(1));
        }
        return new java.util.ArrayList<>(out);
    }

    /** Map storage's label with what the maps take now (MapStore). */
    private void mapCapLabel() {
        long[] u = MapStore.usage(new Paths(this).bar);
        String size = u[0] >= (1L << 30) ? String.format(java.util.Locale.ROOT, "%.1f GB", u[0] / (double) (1L << 30))
                : (u[0] >> 20) + " MB";
        TextView label = findViewById(R.id.lblMapCap);
        label.setText(getString(R.string.lbl_map_cap_now, getString(R.string.lbl_map_cap), size, (int) u[1]));
        explainSettings(label, secondaryTextColor());   // (its name above, what it does smaller: as the other settings)
    }

    private void loadSettingsIntoUi() {
        ((EditText) findViewById(R.id.edWorkers)).setText(String.valueOf(Prefs.workerThreads));
        android.widget.AutoCompleteTextView mapField = findViewById(R.id.edMap);
        mapField.setText(Prefs.mapName);
        // (a tap drops down every map installed, typing narrows them; any other name still goes, and is downloaded)
        mapsStamp = archiveCacheStamp(new Paths(this).bar);
        android.widget.ArrayAdapter<String> maps = new android.widget.ArrayAdapter<>(this,
                android.R.layout.simple_dropdown_item_1line, new java.util.ArrayList<>(installedMaps(new Paths(this).bar)));
        mapsAdapter = maps;   // (made again in onStart when the engine's archive cache changes: refreshMapList)
        mapField.setAdapter(maps);
        Runnable all = () -> maps.getFilter().filter(null, n -> { if (n > 0 && mapField.isShown()) mapField.showDropDown(); });
        mapField.setOnClickListener(v -> all.run());
        mapField.setOnFocusChangeListener((v, focused) -> { if (focused) all.run(); });
        ((EditText) findViewById(R.id.edMesaUrl)).setText(Prefs.mesaUrl);
        CheckBox alt = findViewById(R.id.cbZink);
        alt.setChecked("zink".equals(Prefs.mesaDriver) || "llvmpipe".equals(Prefs.mesaDriver));
        if (Prefs.EMULATOR_BUILD) {   // no Adreno: GPU via virgl, or CPU rendering for comparison
            alt.setText(R.string.cb_llvmpipe);
            findViewById(R.id.edMesaUrl).setEnabled(false);
        }
        ((CheckBox) findViewById(R.id.cbCompat45)).setChecked(Prefs.forceCompat45);
        ((CheckBox) findViewById(R.id.cbAudio)).setChecked(Prefs.audio);
        ((CheckBox) findViewById(R.id.cbRtsTouch)).setChecked(Prefs.rtsTouch);
        ((CheckBox) findViewById(R.id.cbTurnWithPhone)).setChecked(Prefs.turnWithPhone);
        ((CheckBox) findViewById(R.id.cbPortrait)).setChecked(Prefs.portrait);
        ((CheckBox) findViewById(R.id.cbLandDock)).setChecked(Prefs.landDock);
        ((CheckBox) findViewById(R.id.cbCaptureShortcuts)).setChecked(Prefs.captureShortcuts);
        ((android.widget.RadioGroup) findViewById(R.id.rgFpsCap)).check(
                Prefs.fpsCap == 30 ? R.id.rbFps30 : Prefs.fpsCap == 60 ? R.id.rbFps60 : R.id.rbFpsNone);
        ((android.widget.RadioGroup) findViewById(R.id.rgMapCap)).check(
                Prefs.mapCapMb == 5120 ? R.id.rbMap5 : Prefs.mapCapMb == 0 ? R.id.rbMapNone : R.id.rbMap3);
        mapCapLabel();
        ((android.widget.RadioGroup) findViewById(R.id.rgRenderScale)).check(
                Prefs.renderScale == 85 ? R.id.rbRender85 : Prefs.renderScale == 70 ? R.id.rbRender70
                        : Prefs.renderScale == 0 ? R.id.rbRenderNative : R.id.rbRender100);
        ((CheckBox) findViewById(R.id.cbUpscale)).setChecked(Prefs.upscale);
        ((CheckBox) findViewById(R.id.cbUpscaleCompare)).setChecked(Prefs.upscaleCompare);
        ((CheckBox) findViewById(R.id.cbLateDrop)).setChecked(Prefs.lateDrop);
        ((CheckBox) findViewById(R.id.cbLobbyBridge)).setChecked(Prefs.lobbyBridge);
        ((CheckBox) findViewById(R.id.cbAutoLobby)).setChecked(Prefs.autoLobby);
        ((CheckBox) findViewById(R.id.cbAutoUpdate)).setChecked(Prefs.autoUpdate);
        ((CheckBox) findViewById(R.id.cbPhoneEngine)).setChecked(Prefs.phoneEngine);
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
        Prefs.rtsTouch = ((CheckBox) findViewById(R.id.cbRtsTouch)).isChecked();
        Prefs.turnWithPhone = ((CheckBox) findViewById(R.id.cbTurnWithPhone)).isChecked();
        Prefs.portrait = ((CheckBox) findViewById(R.id.cbPortrait)).isChecked();
        Prefs.landDock = ((CheckBox) findViewById(R.id.cbLandDock)).isChecked();
        Prefs.captureShortcuts = ((CheckBox) findViewById(R.id.cbCaptureShortcuts)).isChecked();
        int cap = ((android.widget.RadioGroup) findViewById(R.id.rgFpsCap)).getCheckedRadioButtonId();
        Prefs.fpsCap = cap == R.id.rbFps30 ? 30 : cap == R.id.rbFps60 ? 60 : 0;
        int maps = ((android.widget.RadioGroup) findViewById(R.id.rgMapCap)).getCheckedRadioButtonId();
        Prefs.mapCapMb = maps == R.id.rbMap5 ? 5120 : maps == R.id.rbMapNone ? 0 : 3072;
        int res = ((android.widget.RadioGroup) findViewById(R.id.rgRenderScale)).getCheckedRadioButtonId();
        Prefs.renderScale = res == R.id.rbRender85 ? 85 : res == R.id.rbRender70 ? 70 : res == R.id.rbRenderNative ? 0 : 100;
        Prefs.upscale = ((CheckBox) findViewById(R.id.cbUpscale)).isChecked();
        Prefs.upscaleCompare = ((CheckBox) findViewById(R.id.cbUpscaleCompare)).isChecked();
        Prefs.lateDrop = ((CheckBox) findViewById(R.id.cbLateDrop)).isChecked();
        Prefs.lobbyBridge = ((CheckBox) findViewById(R.id.cbLobbyBridge)).isChecked();
        Prefs.autoLobby = ((CheckBox) findViewById(R.id.cbAutoLobby)).isChecked();
        Prefs.autoUpdate = ((CheckBox) findViewById(R.id.cbAutoUpdate)).isChecked();
        Prefs.phoneEngine = ((CheckBox) findViewById(R.id.cbPhoneEngine)).isChecked();
        Prefs.noSeccomp = ((CheckBox) findViewById(R.id.cbNoSeccomp)).isChecked();
        Prefs.verboseX = ((CheckBox) findViewById(R.id.cbVerboseX)).isChecked();
        Prefs.save(this);
        deviceView.setText(deviceSummary());
        if (say) Toast.makeText(this, "Saved", Toast.LENGTH_SHORT).show();
    }
}
