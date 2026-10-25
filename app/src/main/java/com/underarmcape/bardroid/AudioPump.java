package com.underarmcape.bardroid;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import android.system.Os;
import android.system.OsConstants;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;

/**
 * Plays raw PCM (s16le, 48 kHz, stereo) that PulseAudio's module-pipe-sink writes inside the container to
 * rootfs/tmp/bardroid-audio.fifo. The FIFO is created here (the app side) so it exists before pulseaudio starts.
 */
public final class AudioPump {
    private final File fifo;
    private Thread thread;
    private volatile boolean running;

    public AudioPump(File fifo) { this.fifo = fifo; }

    public void start() {
        running = true;
        thread = new Thread(this::run, "audio-pump");
        thread.setDaemon(true);
        thread.start();
    }

    public void stop() {
        running = false;
        if (thread != null) thread.interrupt();
        // A reader blocked in open() ignores interrupts; a non-blocking writer open wakes it so the thread can exit.
        try {
            java.io.FileDescriptor fd = Os.open(fifo.getAbsolutePath(), OsConstants.O_WRONLY | OsConstants.O_NONBLOCK, 0);
            Os.close(fd);
        } catch (Exception ignored) {}
    }

    private void run() {
        try {
            if (!fifo.exists()) Os.mkfifo(fifo.getAbsolutePath(), OsConstants.S_IRUSR | OsConstants.S_IWUSR | OsConstants.S_IRGRP | OsConstants.S_IWGRP);
        } catch (Exception e) { Log.e("audio", "mkfifo failed", e); return; }
        int rate = 48000;
        int minBuf = AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT);
        AudioTrack track = new AudioTrack.Builder()
                .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                .setAudioFormat(new AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(rate).setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).build())
                .setBufferSizeInBytes(Math.max(minBuf * 2, 32 * 1024))
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build();
        track.play();
        byte[] buf = new byte[8192];
        while (running) {
            // Opening a FIFO for reading blocks until a writer appears; re-open after the writer goes away.
            try (InputStream in = new FileInputStream(fifo)) {
                int n;
                while (running && (n = in.read(buf)) > 0) track.write(buf, 0, n);
            } catch (IOException e) {
                if (!running) break;
                try { Thread.sleep(250); } catch (InterruptedException ie) { break; }
            }
        }
        track.stop();
        track.release();
    }
}
