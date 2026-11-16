package com.s22.omarchyphone;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * The connection to the omarchy-phone daemon inside the Omarchy container: one TCP stream of
 * newline-separated JSON over the container's private network (172.28.0.0/16, routed only on the
 * phone). Both ends prove they hold the shared token (files/token, written at install) with an
 * HMAC over the other's random challenge before anything else is exchanged. Reconnects forever.
 */
final class Link {
    static final String TAG = "OmarchyPhone";

    interface Listener {
        void onConnected();

        void onCommand(JSONObject cmd) throws Exception;
    }

    private static Link sInstance;

    static synchronized Link get(Context c) {
        if (sInstance == null) sInstance = new Link(c.getApplicationContext());
        return sInstance;
    }

    private final Context ctx;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService writer = Executors.newSingleThreadExecutor();
    private volatile BufferedWriter out;
    private volatile Socket socket;
    private volatile Listener listener;
    private volatile boolean running;

    private Link(Context ctx) {
        this.ctx = ctx;
    }

    synchronized void start(Listener l) {
        listener = l;
        if (running) return;
        running = true;
        new Thread(this::loop, "omarchy-link").start();
    }

    boolean connected() {
        return out != null;
    }

    void send(JSONObject msg) {
        final String line = msg.toString();
        writer.execute(() -> {
            BufferedWriter w = out;
            if (w == null) return;
            try {
                w.write(line);
                w.write('\n');
                w.flush();
            } catch (IOException e) {
                drop();
            }
        });
    }

    private void drop() {
        Socket s = socket;
        out = null;
        socket = null;
        if (s != null) try {
            s.close();
        } catch (IOException ignored) {
        }
    }

    private String setting(String name, String fallback) {
        try {
            File f = new File(ctx.getFilesDir(), name);
            if (f.exists()) {
                String v = new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8).trim();
                if (!v.isEmpty()) return v;
            }
        } catch (IOException ignored) {
        }
        return fallback;
    }

    private void loop() {
        long backoff = 2000;
        while (running) {
            String token = setting("token", null);
            String[] endpoint = setting("endpoint", "172.28.79.5:47700").split(":");
            if (token == null) {
                pause(10000);
                continue;
            }
            Socket s = new Socket();
            try {
                s.connect(new InetSocketAddress(endpoint[0], Integer.parseInt(endpoint[1])), 3000);
                s.setTcpNoDelay(true);
                s.setKeepAlive(true);
                s.setSoTimeout(8000);
                BufferedReader in = new BufferedReader(new InputStreamReader(s.getInputStream(), StandardCharsets.UTF_8));
                BufferedWriter w = new BufferedWriter(new OutputStreamWriter(s.getOutputStream(), StandardCharsets.UTF_8));
                JSONObject challenge = new JSONObject(in.readLine());
                String mine = randomHex();
                w.write(new JSONObject().put("t", "auth")
                        .put("mac", hmac(token, "app:" + challenge.getString("nonce")))
                        .put("nonce", mine).toString() + "\n");
                w.flush();
                JSONObject reply = new JSONObject(in.readLine());
                byte[] expect = hmac(token, "daemon:" + mine).getBytes(StandardCharsets.UTF_8);
                if (!MessageDigest.isEqual(expect, reply.optString("mac").getBytes(StandardCharsets.UTF_8)))
                    throw new IOException("the daemon did not prove the token");
                // The daemon pings every 30 s; three missed pings means the container is gone.
                s.setSoTimeout(95000);
                socket = s;
                out = w;
                backoff = 2000;
                Log.i(TAG, "connected to omarchy-phone");
                main.post(() -> {
                    Listener l = listener;
                    if (l != null) l.onConnected();
                });
                String line;
                while ((line = in.readLine()) != null) {
                    final JSONObject cmd = new JSONObject(line);
                    main.post(() -> {
                        Listener l = listener;
                        if (l == null) return;
                        try {
                            l.onCommand(cmd);
                        } catch (Exception e) {
                            Log.w(TAG, "command " + cmd.optString("c") + " failed", e);
                        }
                    });
                }
            } catch (Exception e) {
                Log.d(TAG, "link down: " + e);
            } finally {
                if (socket == s) drop();
                try {
                    s.close();
                } catch (IOException ignored) {
                }
            }
            pause(backoff);
            backoff = Math.min(backoff * 2, 15000);
        }
    }

    private static void pause(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException ignored) {
        }
    }

    private static String randomHex() {
        byte[] b = new byte[16];
        new SecureRandom().nextBytes(b);
        return hex(b);
    }

    static String hmac(String key, String msg) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        return hex(mac.doFinal(msg.getBytes(StandardCharsets.UTF_8)));
    }

    private static String hex(byte[] b) {
        StringBuilder sb = new StringBuilder();
        for (byte x : b) sb.append(String.format("%02x", x));
        return sb.toString();
    }
}
