package com.underarmcape.bardroid;

import android.content.Context;

import java.io.File;

/** Runs LobbyBridge for a write dir on the laptop: BridgeMain <write dir> <seconds>. */
public final class BridgeMain {
    public static void main(String[] a) throws Exception {
        LobbyBridge b = new LobbyBridge(new Context(), new Paths(new File(a[0])));
        b.start();
        Thread.sleep(Long.parseLong(a[1]) * 1000);
        b.stop();
        System.out.println("[test] bridge stopped");
        System.exit(0);
    }
}
