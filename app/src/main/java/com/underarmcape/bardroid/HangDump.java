package com.underarmcape.bardroid;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

/**
 * Where a hung engine is stuck, from the kernel's side. BAR's watchdog says "Hang detection triggered" when the main
 * thread has not moved for 30 s, but its own stack trace finds nothing under proot ("could not query
 * /proc/<pid>/task/<tid>/status", dev phone, 2026-11-10: three early-game hangs that evening, the cause unknown). The
 * app can read its own processes' /proc: each engine thread's name, kernel wait (wchan), system call (number and first
 * argument: an ioctl is the GPU driver, a futex a lock, "running" a loop) and state go to launcher.log as "[hang]"
 * lines, once a game. Read on its own thread: the engine's output reader must not wait for it.
 */
final class HangDump {
    private HangDump() {}

    /** Logs the engine's threads now, on a thread of its own. */
    static void dumpAsync() {
        Thread t = new Thread(HangDump::dump, "hang-dump");
        t.setDaemon(true);
        t.start();
    }

    static void dump() {
        File[] procs = new File("/proc").listFiles();
        int found = 0;
        for (File p : procs != null ? procs : new File[0]) {
            if (!p.getName().matches("\\d+")) continue;
            String cmd = read(new File(p, "cmdline"));   // (the engine's own argv[0]; proot's command line names it too)
            if (cmd == null || !cmd.split("\0", 2)[0].matches("(.*/)?spring")) continue;
            found++;
            File[] tasks = new File(p, "task").listFiles();
            int n = tasks != null ? tasks.length : 0;
            // (the shared logs' only, Log.detail: in the launcher's box ~22 lines of "[hang] 20419 ? | ? | ? | ?" stood
            // under the driver fault's note; dev phone 2026-11-19)
            Log.detail("svc", "[hang] the engine (pid " + p.getName() + ", " + n + " threads), each thread: name, kernel wait, system call, state");
            for (File t : tasks != null ? tasks : new File[0]) {
                String sys = read(new File(t, "syscall"));
                String state = "?";
                String status = read(new File(t, "status"));
                if (status != null) for (String l : status.split("\n")) if (l.startsWith("State:")) state = l.substring(6).trim();
                Log.detail("svc", "[hang] " + t.getName() + " " + oneLine(read(new File(t, "comm"))) + " | " + oneLine(read(new File(t, "wchan")))
                        + " | " + syscallName(sys) + " | " + state);
            }
        }
        if (found == 0) Log.detail("svc", "[hang] no engine process found to look at");
    }

    /** "98 0x5504d9f464 0x189 ..." as "futex 0x5504d9f464"; "running" as it is. */
    static String syscallName(String sys) {
        if (sys == null) return "?";
        String[] f = sys.trim().split("\\s+");
        if (f.length == 0 || !f[0].matches("\\d+")) return sys.trim();
        String name;
        switch (Integer.parseInt(f[0])) {   // (arm64's numbers)
            case 29: name = "ioctl"; break;
            case 98: name = "futex"; break;
            case 72: name = "pselect6"; break;
            case 73: name = "ppoll"; break;
            case 22: name = "epoll_pwait"; break;
            case 63: name = "read"; break;
            case 64: name = "write"; break;
            case 101: name = "nanosleep"; break;
            case 115: name = "clock_nanosleep"; break;
            case 211: name = "sendmsg"; break;
            case 212: name = "recvmsg"; break;
            case 243: name = "recvmmsg"; break;
            case 66: name = "writev"; break;
            default: name = "syscall " + f[0];
        }
        return f.length > 1 ? name + " " + f[1] : name;
    }

    private static String read(File f) {
        try { return new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8); }
        catch (Exception e) { return null; }
    }

    private static String oneLine(String s) { return s == null ? "?" : s.trim().replace('\n', ' '); }
}
