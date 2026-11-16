package com.s22.omarchyphone;

import android.app.ActivityOptions;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.drawable.Drawable;
import android.hardware.display.DisplayManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Base64;
import android.util.Log;
import android.view.Display;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;

/**
 * Starting things on the screen Omarchy is on: Android apps, links (tel:, sms:, ...) and the
 * notifications' own intents. Android lets a background app start an activity only while it has a
 * visible window, so each start briefly shows a 1 px transparent overlay (SYSTEM_ALERT_WINDOW).
 */
final class Launcher {
    private static final Handler main = new Handler(Looper.getMainLooper());
    private static View overlay;
    private static WindowManager overlayWm;
    private static final Runnable removeOverlay = () -> {
        if (overlay != null) {
            try {
                overlayWm.removeView(overlay);
            } catch (Exception ignored) {
            }
            overlay = null;
        }
    };

    /** The display Omarchy is showing on: the daemon says (from the placement daemon), else external if any. */
    static int targetDisplay(Context c, JSONObject cmd) {
        if (cmd != null && cmd.has("display")) return cmd.optInt("display");
        DisplayManager dm = c.getSystemService(DisplayManager.class);
        for (Display d : dm.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION))
            if (d.getDisplayId() != Display.DEFAULT_DISPLAY) return d.getDisplayId();
        return Display.DEFAULT_DISPLAY;
    }

    static Bundle options(Context c, int display) {
        ActivityOptions o = ActivityOptions.makeBasic();
        o.setLaunchDisplayId(display);
        if (display != Display.DEFAULT_DISPLAY) {
            // On the monitor: a window over Omarchy (where the display allows windows), not full screen.
            Display d = c.getSystemService(DisplayManager.class).getDisplay(display);
            if (d != null) {
                Display.Mode m = d.getMode();
                int w = m.getPhysicalWidth(), h = m.getPhysicalHeight();
                int ww = Math.min(w * 2 / 5, 1400), wh = Math.min(h * 5 / 6, 1200);
                o.setLaunchBounds(new Rect((w - ww) / 2, (h - wh) / 2, (w + ww) / 2, (h + wh) / 2));
            }
        }
        o.setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED);
        return o.toBundle();
    }

    static void withVisibleWindow(Context c, Runnable r) {
        if (overlay == null && Settings.canDrawOverlays(c)) {
            try {
                Display d0 = c.getSystemService(DisplayManager.class).getDisplay(Display.DEFAULT_DISPLAY);
                Context wc = c.createWindowContext(d0, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, null);
                WindowManager wm = wc.getSystemService(WindowManager.class);
                WindowManager.LayoutParams lp = new WindowManager.LayoutParams(1, 1,
                        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                        PixelFormat.TRANSLUCENT);
                lp.gravity = Gravity.TOP | Gravity.START;
                View v = new View(wc);
                wm.addView(v, lp);
                overlay = v;
                overlayWm = wm;
            } catch (Exception e) {
                Log.w(Link.TAG, "overlay", e);
            }
        }
        main.postDelayed(() -> {
            try {
                r.run();
            } catch (Exception e) {
                Log.w(Link.TAG, "start failed", e);
            }
        }, overlay != null ? 200 : 0);
        main.removeCallbacks(removeOverlay);
        main.postDelayed(removeOverlay, 3000);
    }

    static void launch(Context c, JSONObject cmd) throws Exception {
        String pkg = cmd.getString("pkg"), act = cmd.optString("activity");
        Intent i = act.isEmpty() ? c.getPackageManager().getLaunchIntentForPackage(pkg)
                : new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setClassName(pkg, act);
        if (i == null) return;
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
        final Bundle opts = options(c, targetDisplay(c, cmd));
        withVisibleWindow(c, () -> c.startActivity(i, opts));
    }

    /** A link: tel:, sms:/smsto: (with "body"), mailto:, geo:, https: ... */
    static void view(Context c, JSONObject cmd) throws Exception {
        Uri uri = Uri.parse(cmd.getString("uri"));
        String scheme = String.valueOf(uri.getScheme()).toLowerCase();
        String action = scheme.equals("tel") ? Intent.ACTION_DIAL
                : scheme.startsWith("sms") || scheme.startsWith("mms") || scheme.equals("mailto") ? Intent.ACTION_SENDTO
                : Intent.ACTION_VIEW;
        Intent i = new Intent(action, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        if (cmd.has("body")) i.putExtra("sms_body", cmd.getString("body"));
        final Bundle opts = options(c, targetDisplay(c, cmd));
        withVisibleWindow(c, () -> c.startActivity(i, opts));
    }

    /** An Android settings page by short name, on Omarchy's screen. */
    static void settings(Context c, JSONObject cmd) {
        String action;
        switch (cmd.optString("page", "wifi")) {
            case "bluetooth": action = Settings.ACTION_BLUETOOTH_SETTINGS; break;
            case "network": action = Settings.ACTION_WIRELESS_SETTINGS; break;
            case "mobile": action = Settings.ACTION_NETWORK_OPERATOR_SETTINGS; break;
            case "battery": action = Intent.ACTION_POWER_USAGE_SUMMARY; break;
            case "sound": action = Settings.ACTION_SOUND_SETTINGS; break;
            case "display": action = Settings.ACTION_DISPLAY_SETTINGS; break;
            case "all": action = Settings.ACTION_SETTINGS; break;
            default: action = Settings.ACTION_WIFI_SETTINGS;
        }
        Intent i = new Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        final Bundle opts = options(c, targetDisplay(c, cmd));
        withVisibleWindow(c, () -> c.startActivity(i, opts));
    }

    static void sendPending(Context c, PendingIntent pi, Intent fillIn, JSONObject cmd) {
        if (pi == null) return;
        final Bundle opts = options(c, targetDisplay(c, cmd));
        withVisibleWindow(c, () -> {
            try {
                pi.send(c, 0, fillIn, null, null, null, opts);
            } catch (PendingIntent.CanceledException e) {
                Log.w(Link.TAG, "intent was cancelled", e);
            }
        });
    }

    static String png(Drawable d, int size) {
        Bitmap b = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
        Canvas cv = new Canvas(b);
        d.setBounds(0, 0, size, size);
        d.draw(cv);
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        b.compress(Bitmap.CompressFormat.PNG, 100, bos);
        return Base64.encodeToString(bos.toByteArray(), Base64.NO_WRAP);
    }

    static String appIcon(Context c, String pkg) {
        try {
            return png(c.getPackageManager().getApplicationIcon(pkg), 128);
        } catch (Exception e) {
            return null;
        }
    }

    static String appLabel(Context c, String pkg) {
        try {
            PackageManager pm = c.getPackageManager();
            return pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString();
        } catch (Exception e) {
            return pkg;
        }
    }

    /** Every launcher entry: package, activity, label and version (icons on request). */
    static void sendApps(Context c) {
        new Thread(() -> {
            try {
                PackageManager pm = c.getPackageManager();
                JSONArray arr = new JSONArray();
                Intent i = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
                for (ResolveInfo ri : pm.queryIntentActivities(i, PackageManager.ResolveInfoFlags.of(0))) {
                    ActivityInfo ai = ri.activityInfo;
                    long ver = 0;
                    try {
                        ver = pm.getPackageInfo(ai.packageName, 0).getLongVersionCode();
                    } catch (Exception ignored) {
                    }
                    arr.put(new JSONObject().put("pkg", ai.packageName).put("activity", ai.name)
                            .put("label", String.valueOf(ri.loadLabel(pm))).put("version", ver));
                }
                Link.get(c).send(new JSONObject().put("t", "apps").put("apps", arr));
            } catch (Exception e) {
                Log.w(Link.TAG, "apps", e);
            }
        }, "omarchy-apps").start();
    }

    static void sendIcons(Context c, JSONArray pkgs) {
        new Thread(() -> {
            for (int k = 0; k < pkgs.length(); k++) {
                try {
                    String pkg = pkgs.getString(k);
                    String png = appIcon(c, pkg);
                    if (png != null) Link.get(c).send(new JSONObject().put("t", "icon").put("pkg", pkg).put("png", png));
                } catch (Exception ignored) {
                }
            }
        }, "omarchy-icons").start();
    }
}
