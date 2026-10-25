package com.underarmcape.bardroid;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import android.system.Os;
import android.system.OsConstants;

import java.io.DataInputStream;
import java.io.EOFException;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;

/**
 * Plays the game's sound. Inside the container OpenAL Soft's wave writer (launch-bar.sh) streams a WAV header and
 * then raw PCM into rootfs/tmp/bardroid-audio.fifo, paced by the engine's own mixer clock: after a stall (the engine
 * runs under ptrace, on a busy CPU) it catches up instead of leaving a hole. The track starts once {@link #CUSHION_MS}
 * are buffered, so such stalls only eat into the cushion. The FIFO is created here (the app side) so it exists
 * before the engine starts.
 */
public final class AudioPump {
    private static final int CUSHION_MS = 200;
    private static final long UNDERRUN_LOG_MS = 30_000;

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
        android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO);
        try {
            if (!fifo.exists()) Os.mkfifo(fifo.getAbsolutePath(), OsConstants.S_IRUSR | OsConstants.S_IWUSR | OsConstants.S_IRGRP | OsConstants.S_IWGRP);
        } catch (Exception e) { Log.e("audio", "mkfifo failed", e); return; }
        while (running) {
            // Opening a FIFO for reading blocks until a writer appears; each writer (each OpenAL device) is a stream.
            try (DataInputStream in = new DataInputStream(new FileInputStream(fifo))) {
                play(in);
            } catch (EOFException e) {
                // the writer went away (game closed its sound device)
            } catch (IOException e) {
                if (!running) break;
                Log.e("audio", "audio stream", e);
                try { Thread.sleep(250); } catch (InterruptedException ie) { break; }
            }
        }
    }

    /** Sample format of a stream (OpenAL Soft writes 48 kHz stereo 16-bit with launch-bar.sh's settings). */
    private static final class Format {
        int rate = 48000, channels = 2, bits = 16;
        boolean isFloat;
    }

    private void play(DataInputStream in) throws IOException {
        byte[] buf = new byte[8192];
        Format f = new Format();
        int carry = readHeader(in, f, buf);   // bytes of sample data already in buf (a stream without a header)
        int frame = Math.max(1, f.channels * f.bits / 8);
        int cushion = f.rate * CUSHION_MS / 1000 * frame;
        AudioTrack track = openTrack(f, cushion * 2);
        Log.i("audio", "stream " + f.rate + " Hz, " + f.channels + " ch, " + f.bits + (f.isFloat ? "-bit float" : "-bit")
                + (track == null ? ", discarded" : ""));
        long queued = 0, nextLog = android.os.SystemClock.uptimeMillis() + UNDERRUN_LOG_MS;
        int underruns = 0;
        boolean playing = false;
        try {
            int n;
            while (running && (n = in.read(buf, carry, buf.length - carry)) > 0) {
                int len = carry + n, whole = len - len % frame;   // whole frames only; keep the rest for next time
                if (track != null && whole > 0) {
                    track.write(ByteBuffer.wrap(buf, 0, whole), whole, AudioTrack.WRITE_BLOCKING);
                    // MODE_STREAM: what is written before play() is played first, so playback starts on the cushion
                    if (!playing && (queued += whole) >= cushion) { track.play(); playing = true; }
                }
                carry = len - whole;
                System.arraycopy(buf, whole, buf, 0, carry);
                if (playing && android.os.SystemClock.uptimeMillis() >= nextLog) {
                    nextLog += UNDERRUN_LOG_MS;
                    int u = track.getUnderrunCount();
                    if (u != underruns) Log.i("audio", "underruns: " + u);
                    underruns = u;
                }
            }
        } finally {
            if (track != null) { if (playing) track.stop(); track.release(); }
        }
    }

    /**
     * Reads the RIFF/WAVE header of OpenAL Soft's wave writer up to the sample data and fills in the format.
     * A stream without one is taken as raw 48 kHz stereo 16-bit; its first bytes are left in buf.
     * @return the number of sample bytes already in buf
     */
    private static int readHeader(DataInputStream in, Format f, byte[] buf) throws IOException {
        in.readFully(buf, 0, 4);
        if (!"RIFF".equals(new String(buf, 0, 4, StandardCharsets.US_ASCII))) return 4;
        in.readFully(buf, 0, 8);   // RIFF size, "WAVE"
        for (;;) {
            in.readFully(buf, 0, 8);
            String id = new String(buf, 0, 4, StandardCharsets.US_ASCII);
            int size = ByteBuffer.wrap(buf, 4, 4).order(ByteOrder.LITTLE_ENDIAN).getInt();
            if (id.equals("data")) return 0;   // its size is a placeholder: the stream has no end
            if (size < 0 || size > buf.length) throw new IOException("bad WAV chunk " + id + " " + size);
            in.readFully(buf, 0, size);
            if (id.equals("fmt ") && size >= 16) {
                ByteBuffer b = ByteBuffer.wrap(buf, 0, size).order(ByteOrder.LITTLE_ENDIAN);
                int tag = b.getShort(0) & 0xffff;
                f.channels = b.getShort(2);
                f.rate = b.getInt(4);
                f.bits = b.getShort(14);
                if (tag == 0xFFFE && size >= 26) tag = b.getShort(24) & 0xffff;   // WAVE_FORMAT_EXTENSIBLE sub-format
                f.isFloat = tag == 3;
            }
        }
    }

    private static AudioTrack openTrack(Format f, int bufferBytes) {
        int encoding = f.isFloat ? AudioFormat.ENCODING_PCM_FLOAT
                : f.bits == 8 ? AudioFormat.ENCODING_PCM_8BIT : AudioFormat.ENCODING_PCM_16BIT;
        int mask = f.channels == 1 ? AudioFormat.CHANNEL_OUT_MONO : AudioFormat.CHANNEL_OUT_STEREO;
        try {
            int minBuf = AudioTrack.getMinBufferSize(f.rate, mask, encoding);
            return new AudioTrack.Builder()
                    .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                    .setAudioFormat(new AudioFormat.Builder().setEncoding(encoding).setSampleRate(f.rate).setChannelMask(mask).build())
                    .setBufferSizeInBytes(Math.max(minBuf, bufferBytes))
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .build();
        } catch (Exception e) {
            // No audio output (e.g. an emulator started with -no-audio): keep draining the FIFO so the game never blocks.
            Log.e("audio", "no AudioTrack; discarding game audio", e);
            return null;
        }
    }
}
