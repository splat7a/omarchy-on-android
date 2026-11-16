package com.s22.omarchyphone;

import android.net.Uri;
import android.telecom.Call;
import android.telecom.CallAudioState;
import android.telecom.InCallService;
import android.telecom.TelecomManager;
import android.telecom.VideoProfile;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * A non-UI in-call service: Telecom binds it for every call (MANAGE_ONGOING_CALLS app-op), so it
 * sees each call's number, contact name and state, and can answer, decline, hang up, mute and
 * switch between earpiece and speaker. The Phone app keeps its own call screen.
 */
public class CallCompanion extends InCallService {
    static CallCompanion sInstance;
    private static final Map<String, Call> calls = new LinkedHashMap<>();
    private static int seq;

    private final Call.Callback callback = new Call.Callback() {
        @Override
        public void onStateChanged(Call call, int state) {
            report();
        }

        @Override
        public void onDetailsChanged(Call call, Call.Details details) {
            report();
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        sInstance = this;
    }

    @Override
    public void onDestroy() {
        if (sInstance == this) sInstance = null;
        calls.clear();
        report();
        super.onDestroy();
    }

    @Override
    public void onCallAdded(Call call) {
        sInstance = this;
        String id = "c" + (++seq);
        calls.put(id, call);
        call.registerCallback(callback);
        report();
        if (call.getDetails().getState() == Call.STATE_RINGING) {
            try {
                Link.get(this).send(new JSONObject().put("t", "call-incoming").put("id", id));
            } catch (Exception ignored) {
            }
        }
    }

    @Override
    public void onCallRemoved(Call call) {
        call.unregisterCallback(callback);
        calls.values().remove(call);
        report();
    }

    @Override
    public void onCallAudioStateChanged(CallAudioState audioState) {
        report();
    }

    private static String state(Call call, boolean otherLive) {
        switch (call.getDetails().getState()) {
            case Call.STATE_RINGING:
            case Call.STATE_SIMULATED_RINGING:
                return otherLive ? "waiting" : "ringing-in";
            case Call.STATE_ACTIVE:
            case Call.STATE_AUDIO_PROCESSING:
                return "active";
            case Call.STATE_HOLDING:
                return "held";
            case Call.STATE_DISCONNECTING:
            case Call.STATE_DISCONNECTED:
                return "ended";
            default:
                return "dialing";
        }
    }

    /** The whole call state, as org.omamobile.Phone1 serves it in the container. */
    static JSONObject snapshot() throws Exception {
        JSONArray list = new JSONArray();
        boolean live = false;
        for (Call c : calls.values()) {
            int s = c.getDetails().getState();
            if (s == Call.STATE_ACTIVE || s == Call.STATE_HOLDING || s == Call.STATE_DIALING || s == Call.STATE_CONNECTING)
                live = true;
        }
        for (Map.Entry<String, Call> e : calls.entrySet()) {
            Call.Details d = e.getValue().getDetails();
            String st = state(e.getValue(), live);
            if (st.equals("ended")) continue;
            Uri handle = d.getHandle();
            String name = d.getContactDisplayName();
            if (name == null || name.isEmpty()) name = d.getCallerDisplayName();
            list.put(new JSONObject().put("id", e.getKey())
                    .put("number", handle == null ? "" : handle.getSchemeSpecificPart())
                    .put("name", name == null ? "" : name)
                    .put("direction", d.getCallDirection() == Call.Details.DIRECTION_OUTGOING ? "outgoing" : "incoming")
                    .put("state", st)
                    .put("startedMs", d.getCreationTimeMillis())
                    .put("answeredMs", d.getConnectTimeMillis()));
        }
        boolean muted = false;
        String route = "earpiece";
        CallCompanion self = sInstance;
        if (self != null) {
            @SuppressWarnings("deprecation") CallAudioState a = self.getCallAudioState();
            if (a != null) {
                muted = a.isMuted();
                switch (a.getRoute()) {
                    case CallAudioState.ROUTE_SPEAKER: route = "speaker"; break;
                    case CallAudioState.ROUTE_BLUETOOTH: route = "bluetooth"; break;
                    case CallAudioState.ROUTE_WIRED_HEADSET: route = "headset"; break;
                    default: route = "earpiece";
                }
            }
        }
        return new JSONObject().put("t", "calls").put("calls", list).put("muted", muted).put("route", route)
                .put("bound", self != null);
    }

    static void report() {
        CallCompanion self = sInstance;
        if (self == null) return;
        try {
            Link.get(self).send(snapshot());
        } catch (Exception e) {
            Log.w(Link.TAG, "call state", e);
        }
    }

    /** answer | decline | hangup | mute | route; falls back to TelecomManager when not bound. */
    @SuppressWarnings({"deprecation", "MissingPermission"})
    static void command(android.content.Context ctx, String op, String id, JSONObject cmd) {
        CallCompanion self = sInstance;
        Call call = id == null || id.isEmpty() ? null : calls.get(id);
        if (call == null && !calls.isEmpty() && !op.equals("mute") && !op.equals("route")) {
            // "Hangup" with no id: the live call; others: the ringing one.
            for (Call c : calls.values()) {
                int s = c.getDetails().getState();
                if (op.equals("hangup") ? s != Call.STATE_RINGING : s == Call.STATE_RINGING) call = c;
            }
        }
        TelecomManager telecom = ctx.getSystemService(TelecomManager.class);
        switch (op) {
            case "answer":
                if (call != null) call.answer(VideoProfile.STATE_AUDIO_ONLY);
                else telecom.acceptRingingCall();
                break;
            case "decline":
                if (call != null) call.reject(false, null);
                else telecom.endCall();
                break;
            case "hangup":
                if (call != null) call.disconnect();
                else telecom.endCall();
                break;
            case "mute":
                if (self != null) self.setMuted(cmd.optBoolean("on"));
                break;
            case "route":
                if (self != null) self.setAudioRoute("speaker".equals(cmd.optString("route"))
                        ? CallAudioState.ROUTE_SPEAKER : CallAudioState.ROUTE_WIRED_OR_EARPIECE);
                break;
        }
    }
}
