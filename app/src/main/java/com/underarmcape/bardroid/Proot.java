package com.underarmcape.bardroid;

import android.os.Build;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Builds proot command lines for the Debian container. Mirrors what proot-distro's `login` does on Termux
 * (link2symlink, sysvipc, kill-on-exit, fake /proc data, /dev/shm bind), using the Termux proot binary
 * that ships in our jniLibs.
 */
public final class Proot {
    private final Paths p;

    public Proot(Paths p) { this.p = p; }

    /** Environment for the proot process itself (host side). */
    public Map<String, String> hostEnv() {
        Map<String, String> env = new HashMap<>();
        env.put("PATH", "/system/bin:/system/xbin");
        env.put("HOME", p.filesDir.getAbsolutePath());
        env.put("TMPDIR", p.prootTmp.getAbsolutePath());
        env.put("PROOT_TMP_DIR", p.prootTmp.getAbsolutePath());
        env.put("PROOT_LOADER", p.prootLoader().getAbsolutePath());
        //noinspection ResultOfMethodCallIgnored
        p.l2s().mkdirs();
        env.put("PROOT_L2S_DIR", p.l2s().getAbsolutePath());
        env.put("LD_LIBRARY_PATH", p.nativeLibDir);
        if (Prefs.noSeccomp) env.put("PROOT_NO_SECCOMP", "1");
        env.put("ANDROID_DATA", "/data");
        env.put("ANDROID_ROOT", "/system");
        return env;
    }

    /** Common proot flags + binds. */
    private List<String> base(boolean fullBinds) {
        List<String> c = new ArrayList<>();
        c.add(p.proot().getAbsolutePath());
        c.add("--kill-on-exit");
        c.add("--link2symlink");
        c.add("-L");
        if (fullBinds) c.add("--sysvipc");
        // proot-distro fakes the kernel release; that loads proot's kompat extension, which traps every futex()
        // (half the engine's render-thread time on the emulator). glibc only needs >= 3.2, so fake it only below that.
        if (kernelMajor() < 4) c.add("--kernel-release=6.6.0-bardroid");
        c.add("--root-id");
        c.add("--rootfs=" + p.rootfs.getAbsolutePath());
        c.add("--cwd=/root");
        c.add("--bind=/dev");
        c.add("--bind=/proc");
        c.add("--bind=/sys");
        c.add("--bind=/dev/urandom:/dev/random");
        if (!new File("/dev/fd").exists()) c.add("--bind=/proc/self/fd:/dev/fd");
        String[] std = {"stdin", "stdout", "stderr"};
        for (int i = 0; i < 3; i++)
            if (!new File("/dev/" + std[i]).exists()) c.add("--bind=/proc/self/fd/" + i + ":/dev/" + std[i]);
        if (fullBinds) {
            for (String[] f : FAKE_PROC) {
                File src = new File(p.fakeProc, f[0]);
                if (src.exists()) c.add("--bind=" + src.getAbsolutePath() + ":" + f[1]);
            }
            c.add("--bind=" + p.shm.getAbsolutePath() + ":/dev/shm");
            c.add("--bind=" + p.bar.getAbsolutePath() + ":/root/bar");
            c.add("--bind=" + p.importDir.getAbsolutePath() + ":/root/import");
            c.add("--bind=" + p.downloads.getAbsolutePath() + ":/root/downloads");
            // Our app-private storage is also where Android keeps the extracted APK libraries; nothing else needed.
        }
        return c;
    }

    private static int kernelMajor() {
        try { return Integer.parseInt(System.getProperty("os.version", "0").split("\\.")[0]); }
        catch (NumberFormatException e) { return 0; }
    }

    /** `proot ... /usr/bin/env -i KEY=VAL ... cmd args` with a clean guest environment. */
    public List<String> command(Map<String, String> guestEnv, List<String> guestCmd) {
        List<String> c = base(true);
        c.add("/usr/bin/env");
        c.add("-i");
        Map<String, String> e = new HashMap<>();
        e.put("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin");
        e.put("HOME", "/root");
        e.put("USER", "root");
        e.put("LOGNAME", "root");
        e.put("SHELL", "/bin/bash");
        e.put("TERM", "xterm-256color");
        e.put("LANG", "C.UTF-8");
        e.put("LC_ALL", "C.UTF-8");
        e.put("TMPDIR", "/tmp");
        e.put("XDG_RUNTIME_DIR", "/tmp");
        e.put("DEBIAN_FRONTEND", "noninteractive");
        e.put("BARDROID", "1");
        e.put("BARDROID_ANDROID_SDK", String.valueOf(Build.VERSION.SDK_INT));
        if (guestEnv != null) e.putAll(guestEnv);
        for (Map.Entry<String, String> kv : e.entrySet()) c.add(kv.getKey() + "=" + kv.getValue());
        c.addAll(guestCmd);
        return c;
    }

    /**
     * Writes files/container.sh: the same proot setup the app uses, for debugging over adb:
     *   adb shell -t run-as com.underarmcape.bardroid sh files/container.sh            interactive bash
     *   adb shell run-as com.underarmcape.bardroid sh files/container.sh 'glxinfo -B'  one command
     * The native-lib directory moves on every app update, and the script is regenerated only before an install or
     * launch, so it looks the directory up itself ("pm path"; the path at writing time if that fails).
     */
    public void writeShellScript(File out) throws IOException {
        Map<String, String> guest = new HashMap<>();
        guest.put("DISPLAY", ":0");
        Prefs.putGpuEnv(guest);
        List<String> cmd = command(guest, new ArrayList<>());
        String lib = p.nativeLibDir;
        StringBuilder sb = new StringBuilder("#!/system/bin/sh\n# Generated by BAR Droid; see Proot.writeShellScript.\n");
        sb.append("LIB=$(pm path ").append(BuildConfig.APPLICATION_ID).append(" 2>/dev/null | sed -n 's|^package:\\(.*\\)/base.apk$|\\1/lib/")
          .append(new File(lib).getName()).append("|p')\n");
        sb.append("[ -d \"$LIB\" ] || LIB=").append(quote(lib)).append('\n');
        for (Map.Entry<String, String> kv : hostEnv().entrySet())
            sb.append("export ").append(kv.getKey()).append('=').append(quoteLib(kv.getValue(), lib)).append('\n');
        sb.append("if [ $# -eq 0 ]; then set -- /bin/bash -l; else set -- /bin/bash -lc \"$*\"; fi\nexec");
        for (String c : cmd) sb.append(' ').append(quoteLib(c, lib));
        sb.append(" \"$@\"\n");
        try (FileWriter w = new FileWriter(out)) { w.write(sb.toString()); }
    }

    private static String quote(String s) { return "'" + s.replace("'", "'\\''") + "'"; }

    /** Quoted for sh, with the native-lib directory replaced by "$LIB". */
    private static String quoteLib(String s, String lib) {
        int i = s.indexOf(lib);
        if (i < 0) return quote(s);
        return quote(s.substring(0, i)) + "\"$LIB\"" + quoteLib(s.substring(i + lib.length()), lib);
    }

    /** Runs a shell script that lives inside the rootfs, as root, with output streamed to the log. */
    public int runScript(String tag, String guestScriptPath, Map<String, String> guestEnv, List<String> args) throws IOException, InterruptedException {
        List<String> cmd = new ArrayList<>();
        cmd.add("/bin/bash");
        cmd.add(guestScriptPath);
        if (args != null) cmd.addAll(args);
        return Proc.run(tag, command(guestEnv, cmd), hostEnv(), p.filesDir);
    }

    /**
     * Unpacks a rootfs tarball into the (empty) rootfs directory using the static busybox, under proot
     * so that hard links become symlinks (Android forbids apps from creating hard links) and ownership /
     * device-node failures are faked away.
     */
    public int extractRootfs(File tarball) throws IOException, InterruptedException {
        List<String> c = base(false);
        // busybox picks the applet from argv[0]; a name starting with "busybox" makes it take the applet from argv[1].
        c.add("--bind=" + p.busybox().getAbsolutePath() + ":/busybox-bardroid");
        c.add("--bind=" + tarball.getAbsolutePath() + ":/.bardroid-rootfs.tar.gz");
        c.add("/busybox-bardroid");
        c.add("tar");                   // Debian's busybox-static has no --exclude; the layer holds no device nodes anyway
        c.add("-xzf");
        c.add("/.bardroid-rootfs.tar.gz");
        c.add("-C");
        c.add("/");
        return Proc.run("rootfs", c, hostEnv(), p.filesDir);
    }

    private static final String[][] FAKE_PROC = {
            {"loadavg", "/proc/loadavg"},
            {"stat", "/proc/stat"},
            {"uptime", "/proc/uptime"},
            {"version", "/proc/version"},
            {"vmstat", "/proc/vmstat"},
            {"cap_last_cap", "/proc/sys/kernel/cap_last_cap"},
            {"cpuinfo", "/proc/cpuinfo"},
    };

    /** Writes the fake /proc files Android hides from apps (proot-distro does the same). */
    public void writeFakeProc() throws IOException {
        //noinspection ResultOfMethodCallIgnored
        p.fakeProc.mkdirs();
        write("loadavg", "0.12 0.07 0.02 1/200 1\n");
        write("stat", "cpu  1000 0 500 100000 100 0 10 0 0 0\ncpu0 1000 0 500 100000 100 0 10 0 0 0\n"
                + "intr 0\nctxt 0\nbtime 1700000000\nprocesses 1\nprocs_running 1\nprocs_blocked 0\nsoftirq 0\n");
        write("uptime", "1000.00 2000.00\n");
        write("version", "Linux version 6.6.0-bardroid (bardroid@android) (gcc version 13) #1 SMP PREEMPT\n");
        write("vmstat", "nr_free_pages 100000\nnr_zone_inactive_anon 0\nnr_zone_active_anon 0\nnr_zone_inactive_file 0\n"
                + "nr_zone_active_file 0\nnr_mlock 0\npgpgin 0\npgpgout 0\npswpin 0\npswpout 0\n");
        write("cap_last_cap", "40\n");
        // Recoil names the CPU after the first "model name" line, which ARM kernels do not write: the engine's hardware
        // string was "11102MB RAM" (the lobby's analytics threw on it, BAR's system info took the RAM for the CPU).
        String cpuinfo = readText("/proc/cpuinfo");
        if (!cpuinfo.contains("model name")) {
            String vendor = Build.VERSION.SDK_INT >= 31 ? Build.SOC_MANUFACTURER : "";
            String soc = (("QTI".equals(vendor) ? "Qualcomm" : vendor) + " "
                    + (Build.VERSION.SDK_INT >= 31 ? Build.SOC_MODEL : Build.HARDWARE)).trim();
            cpuinfo = "model name\t: " + soc + "\n" + cpuinfo;
        }
        write("cpuinfo", cpuinfo);
    }

    private void write(String name, String content) throws IOException {
        try (FileWriter w = new FileWriter(new File(p.fakeProc, name))) { w.write(content); }
    }

    private static String readText(String path) {
        StringBuilder sb = new StringBuilder();
        try (BufferedReader r = new BufferedReader(new FileReader(path))) {
            for (String l; (l = r.readLine()) != null; ) sb.append(l).append('\n');
        } catch (IOException ignored) {}
        return sb.toString();
    }
}
