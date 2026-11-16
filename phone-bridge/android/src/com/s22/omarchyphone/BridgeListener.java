package com.s22.omarchyphone;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.RemoteInput;
import android.content.ComponentName;
import android.content.Intent;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.Icon;
import android.os.Build;
import android.os.Bundle;
import android.os.Parcelable;
import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;
import android.telecom.TelecomManager;
import android.telephony.SmsManager;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.Set;

/**
 * The bridge's anchor: Android keeps a notification listener bound, so this service (and the link
 * to the container it starts) stays up without a notification of its own. It mirrors notifications
 * that would alert on the phone, and carries out the daemon's commands.
 */
public class BridgeListener extends NotificationListenerService implements Link.Listener {
    private PhoneState phone;
    private final Set<String> iconsSent = new HashSet<>();

    @Override
    public void onListenerConnected() {
        if (phone == null) {
            phone = new PhoneState(this);
            phone.start();
        }
        Link.get(this).start(this);
    }

    @Override
    public void onListenerDisconnected() {
        requestRebind(new ComponentName(this, BridgeListener.class));
    }

    private static JSONObject obj(String k, Object v) throws Exception {
        return new JSONObject().put(k, v);
    }

    @Override
    public void onConnected() {
        try {
            iconsSent.clear();
            Link l = Link.get(this);
            l.send(obj("t", "hello").put("version", 1).put("model", Build.MODEL)
                    .put("display", Launcher.targetDisplay(this, null)));
            if (phone != null) phone.sendAll();
            if (CallCompanion.sInstance != null) CallCompanion.report();
            else l.send(CallCompanion.snapshot());
            JSONArray keys = new JSONArray();
            StatusBarNotification[] active = getActiveNotifications();
            if (active != null) for (StatusBarNotification s : active) if (forward(s)) keys.put(s.getKey());
            l.send(obj("t", "notif-active").put("keys", keys));
        } catch (Exception e) {
            android.util.Log.w(Link.TAG, "hello", e);
        }
    }

    private static boolean empty(CharSequence s) {
        return s == null || s.toString().trim().isEmpty();
    }

    private boolean forward(StatusBarNotification sbn) {
        if (sbn.getPackageName().equals(getPackageName())) return false;
        Notification n = sbn.getNotification();
        if ((n.flags & Notification.FLAG_GROUP_SUMMARY) != 0) return false;
        // Calls come through CallCompanion; media players, downloads and services stay on the phone.
        if (sbn.isOngoing() || (n.flags & Notification.FLAG_FOREGROUND_SERVICE) != 0) return false;
        if (Notification.CATEGORY_CALL.equals(n.category)) return false;
        Ranking r = new Ranking();
        if (getCurrentRanking() != null && getCurrentRanking().getRanking(sbn.getKey(), r)) {
            if (r.getImportance() < NotificationManager.IMPORTANCE_DEFAULT || r.isSuspended()) return false;
        }
        return !(empty(title(n)) && empty(text(n)));
    }

    private static CharSequence title(Notification n) {
        Bundle e = n.extras;
        CharSequence t = e.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE);
        if (empty(t)) t = e.getCharSequence(Notification.EXTRA_TITLE_BIG);
        if (empty(t)) t = e.getCharSequence(Notification.EXTRA_TITLE);
        return t;
    }

    @SuppressWarnings("deprecation")
    private static String text(Notification n) {
        Bundle e = n.extras;
        try {
            Parcelable[] msgs = e.getParcelableArray(Notification.EXTRA_MESSAGES);
            if (msgs != null && msgs.length > 0) {
                StringBuilder sb = new StringBuilder();
                boolean group = e.getBoolean(Notification.EXTRA_IS_GROUP_CONVERSATION);
                for (int i = Math.max(0, msgs.length - 4); i < msgs.length; i++) {
                    if (!(msgs[i] instanceof Bundle)) continue;
                    Bundle m = (Bundle) msgs[i];
                    CharSequence body = m.getCharSequence("text");
                    if (empty(body)) continue;
                    CharSequence sender = m.getCharSequence("sender");
                    android.app.Person p = m.getParcelable("sender_person");
                    if (empty(sender) && p != null) sender = p.getName();
                    if (sb.length() > 0) sb.append('\n');
                    if (group && !empty(sender)) sb.append(sender).append(": ");
                    sb.append(body);
                }
                if (sb.length() > 0) return sb.toString();
            }
        } catch (Exception ignored) {
        }
        CharSequence[] lines = e.getCharSequenceArray(Notification.EXTRA_TEXT_LINES);
        if (lines != null && lines.length > 0) {
            StringBuilder sb = new StringBuilder();
            for (CharSequence l : lines) {
                if (sb.length() > 0) sb.append('\n');
                sb.append(l);
            }
            return sb.toString();
        }
        CharSequence t = e.getCharSequence(Notification.EXTRA_BIG_TEXT);
        if (empty(t)) t = e.getCharSequence(Notification.EXTRA_TEXT);
        return t == null ? "" : t.toString();
    }

    @Override
    public void onNotificationPosted(StatusBarNotification sbn) {
        if (!Link.get(this).connected() || !forward(sbn)) return;
        try {
            Notification n = sbn.getNotification();
            String pkg = sbn.getPackageName();
            JSONObject o = obj("t", "notif").put("key", sbn.getKey()).put("pkg", pkg)
                    .put("app", Launcher.appLabel(this, pkg))
                    .put("title", String.valueOf(title(n) == null ? "" : title(n)))
                    .put("text", text(n)).put("when", n.when)
                    .put("category", n.category == null ? "" : n.category)
                    .put("quiet", (n.flags & Notification.FLAG_ONLY_ALERT_ONCE) != 0);
            JSONArray acts = new JSONArray();
            if (n.actions != null) for (int i = 0; i < n.actions.length; i++) {
                Notification.Action a = n.actions[i];
                if (a == null || a.isContextual() || empty(a.title)) continue;
                boolean reply = false;
                if (a.getRemoteInputs() != null)
                    for (RemoteInput ri : a.getRemoteInputs()) if (ri.getAllowFreeFormInput()) reply = true;
                acts.put(obj("i", i).put("title", a.title.toString()).put("reply", reply));
            }
            o.put("actions", acts);
            if (!iconsSent.contains(pkg)) {
                String icon = Launcher.appIcon(this, pkg);
                if (icon != null) o.put("icon", icon);
                iconsSent.add(pkg);
            }
            Icon large = n.getLargeIcon();
            if (large != null) try {
                Drawable d = large.loadDrawable(this);
                if (d != null) o.put("image", Launcher.png(d, 128));
            } catch (Exception ignored) {
            }
            Link.get(this).send(o);
        } catch (Exception e) {
            android.util.Log.w(Link.TAG, "notification", e);
        }
    }

    @Override
    public void onNotificationRemoved(StatusBarNotification sbn) {
        try {
            Link.get(this).send(obj("t", "notif-removed").put("key", sbn.getKey()));
        } catch (Exception ignored) {
        }
    }

    private StatusBarNotification find(String key) {
        StatusBarNotification[] a = getActiveNotifications(new String[]{key});
        return a != null && a.length > 0 ? a[0] : null;
    }

    @Override
    public void onCommand(JSONObject c) throws Exception {
        switch (c.getString("c")) {
            case "ping":
                Link.get(this).send(obj("t", "pong"));
                break;
            case "state":
                if (phone != null) phone.sendAll();
                Link.get(this).send(CallCompanion.snapshot());
                break;
            case "open": {
                StatusBarNotification s = find(c.getString("key"));
                if (s == null) break;
                Notification n = s.getNotification();
                if (n.contentIntent != null) Launcher.sendPending(this, n.contentIntent, null, c);
                else Launcher.launch(this, new JSONObject(c.toString()).put("pkg", s.getPackageName()));
                if ((n.flags & Notification.FLAG_AUTO_CANCEL) != 0) cancelNotification(s.getKey());
                break;
            }
            case "action": {
                StatusBarNotification s = find(c.getString("key"));
                if (s == null || s.getNotification().actions == null) break;
                Notification.Action a = s.getNotification().actions[c.getInt("index")];
                Intent fill = null;
                if (c.has("text") && a.getRemoteInputs() != null) {
                    fill = new Intent();
                    Bundle b = new Bundle();
                    for (RemoteInput ri : a.getRemoteInputs()) b.putCharSequence(ri.getResultKey(), c.getString("text"));
                    RemoteInput.addResultsToIntent(a.getRemoteInputs(), fill, b);
                }
                Launcher.sendPending(this, a.actionIntent, fill, c);
                break;
            }
            case "dismiss":
                cancelNotification(c.getString("key"));
                break;
            case "apps":
                Launcher.sendApps(this);
                break;
            case "icons":
                Launcher.sendIcons(this, c.getJSONArray("pkgs"));
                break;
            case "launch":
                Launcher.launch(this, c);
                break;
            case "view":
                Launcher.view(this, c);
                break;
            case "settings":
                Launcher.settings(this, c);
                break;
            case "sms": {
                SmsManager sm = getSystemService(SmsManager.class);
                ArrayList<String> parts = sm.divideMessage(c.getString("text"));
                sm.sendMultipartTextMessage(c.getString("number"), null, parts, null, null);
                Link.get(this).send(obj("t", "sms-sent").put("number", c.getString("number")));
                break;
            }
            case "call":
                CallCompanion.command(this, c.getString("op"), c.optString("id"), c);
                break;
            case "incall":
                getSystemService(TelecomManager.class).showInCallScreen(false);
                break;
            case "test-call":
                TestCallService.ring(this, c.optString("number", "+15550100"), c.optString("name", "Test call"));
                break;
        }
    }
}
