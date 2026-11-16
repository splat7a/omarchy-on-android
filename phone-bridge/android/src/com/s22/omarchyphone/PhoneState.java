package com.s22.omarchyphone;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.net.wifi.WifiManager;
import android.telephony.ServiceState;
import android.telephony.SignalStrength;
import android.telephony.TelephonyCallback;
import android.telephony.TelephonyDisplayInfo;
import android.telephony.TelephonyManager;
import android.util.Log;

import org.json.JSONObject;

/**
 * Mobile network and Wi-Fi as the Omarchy Mobile status bar reads them
 * (omamobile-cell-watch's JSON, plus a Wi-Fi line of the same kind).
 */
final class PhoneState {
    private final Context ctx;
    private final TelephonyManager tm;
    private final ConnectivityManager cm;
    private final WifiManager wm;

    private int level = -1;          // 0..4 from SignalStrength, -1 unknown
    private int serviceState = ServiceState.STATE_OUT_OF_SERVICE;
    private boolean roaming;
    private int networkType;         // TelephonyManager.NETWORK_TYPE_*
    private int overrideType;        // TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_*
    private boolean dataUp;

    private boolean wifiUp;
    private boolean wifiValidated;
    private int wifiRssi = Integer.MIN_VALUE;
    private String lastCell, lastWifi;

    PhoneState(Context ctx) {
        this.ctx = ctx;
        tm = ctx.getSystemService(TelephonyManager.class);
        cm = ctx.getSystemService(ConnectivityManager.class);
        wm = ctx.getSystemService(WifiManager.class);
    }

    private final class Cb extends TelephonyCallback implements
            TelephonyCallback.SignalStrengthsListener, TelephonyCallback.ServiceStateListener,
            TelephonyCallback.DisplayInfoListener, TelephonyCallback.DataConnectionStateListener {
        @Override
        public void onSignalStrengthsChanged(SignalStrength s) {
            level = s == null ? -1 : s.getLevel();
            sendCell(false);
        }

        @Override
        public void onServiceStateChanged(ServiceState s) {
            serviceState = s.getState();
            roaming = s.getRoaming();
            sendCell(false);
        }

        @Override
        public void onDisplayInfoChanged(TelephonyDisplayInfo d) {
            networkType = d.getNetworkType();
            overrideType = d.getOverrideNetworkType();
            sendCell(false);
        }

        @Override
        public void onDataConnectionStateChanged(int state, int type) {
            dataUp = state == TelephonyManager.DATA_CONNECTED;
            if (type != TelephonyManager.NETWORK_TYPE_UNKNOWN) networkType = type;
            sendCell(false);
        }
    }

    private final android.os.Handler handler = new android.os.Handler(android.os.Looper.getMainLooper());
    // SIM presence and Wi-Fi level can change without a telephony callback: re-read once a minute
    // (sends only when something changed).
    private final Runnable recheck = new Runnable() {
        @Override
        public void run() {
            sendCell(false);
            sendWifi(false);
            handler.postDelayed(this, 60000);
        }
    };

    // Fallback call state for when Telecom has not bound CallCompanion (it normally reports calls):
    // one synthetic call, with the number when READ_CALL_LOG is granted.
    @SuppressWarnings("deprecation")
    private final android.telephony.PhoneStateListener callListener = new android.telephony.PhoneStateListener() {
        private long started, answered;

        @Override
        public void onCallStateChanged(int state, String number) {
            // Telecom binds CallCompanion as the call is added; give it a moment before standing in.
            handler.postDelayed(() -> fallback(state, number), 800);
        }

        private void fallback(int state, String number) {
            if (CallCompanion.sInstance != null) return;
            try {
                org.json.JSONArray calls = new org.json.JSONArray();
                long now = System.currentTimeMillis();
                if (state == TelephonyManager.CALL_STATE_IDLE) {
                    started = answered = 0;
                } else {
                    if (started == 0) started = now;
                    boolean ringing = state == TelephonyManager.CALL_STATE_RINGING;
                    if (!ringing && answered == 0) answered = now;
                    calls.put(new JSONObject().put("id", "t0").put("number", number == null ? "" : number)
                            .put("name", "").put("direction", "incoming")
                            .put("state", ringing ? "ringing-in" : "active")
                            .put("startedMs", started).put("answeredMs", ringing ? 0 : answered));
                }
                Link.get(ctx).send(new JSONObject().put("t", "calls").put("calls", calls)
                        .put("muted", false).put("route", "earpiece").put("bound", false));
                if (state == TelephonyManager.CALL_STATE_RINGING)
                    Link.get(ctx).send(new JSONObject().put("t", "call-incoming").put("id", "t0"));
            } catch (Exception e) {
                Log.w(Link.TAG, "call state", e);
            }
        }
    };

    @SuppressWarnings("deprecation")
    void start() {
        try {
            tm.registerTelephonyCallback(ctx.getMainExecutor(), new Cb());
            tm.listen(callListener, android.telephony.PhoneStateListener.LISTEN_CALL_STATE);
        } catch (SecurityException e) {
            Log.w(Link.TAG, "no phone state permission", e);
        }
        handler.postDelayed(recheck, 60000);
        NetworkRequest wifi = new NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build();
        cm.registerNetworkCallback(wifi, new ConnectivityManager.NetworkCallback() {
            @Override
            public void onCapabilitiesChanged(Network n, NetworkCapabilities caps) {
                wifiUp = true;
                wifiValidated = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED);
                int s = caps.getSignalStrength();
                wifiRssi = s != NetworkCapabilities.SIGNAL_STRENGTH_UNSPECIFIED ? s : rssiFallback();
                sendWifi(false);
            }

            @Override
            public void onLost(Network n) {
                wifiUp = false;
                wifiValidated = false;
                sendWifi(false);
            }
        });
    }

    @SuppressWarnings("deprecation")
    private int rssiFallback() {
        try {
            return wm.getConnectionInfo().getRssi();
        } catch (Exception e) {
            return Integer.MIN_VALUE;
        }
    }

    void sendAll() {
        sendCell(true);
        sendWifi(true);
    }

    private static String tech(int type, int override) {
        switch (override) {
            case TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_NSA:
            case TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_ADVANCED:
                return "5G";
            case TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_LTE_ADVANCED_PRO:
            case TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_LTE_CA:
                return "LTE+";
        }
        switch (type) {
            case TelephonyManager.NETWORK_TYPE_NR:
                return "5G";
            case TelephonyManager.NETWORK_TYPE_LTE:
            case TelephonyManager.NETWORK_TYPE_IWLAN:
                return "LTE";
            case TelephonyManager.NETWORK_TYPE_HSPAP:
                return "H+";
            case TelephonyManager.NETWORK_TYPE_HSPA:
            case TelephonyManager.NETWORK_TYPE_HSDPA:
            case TelephonyManager.NETWORK_TYPE_HSUPA:
                return "H";
            case TelephonyManager.NETWORK_TYPE_UMTS:
            case TelephonyManager.NETWORK_TYPE_TD_SCDMA:
            case TelephonyManager.NETWORK_TYPE_EVDO_0:
            case TelephonyManager.NETWORK_TYPE_EVDO_A:
            case TelephonyManager.NETWORK_TYPE_EVDO_B:
                return "3G";
            case TelephonyManager.NETWORK_TYPE_EDGE:
                return "E";
            case TelephonyManager.NETWORK_TYPE_GPRS:
                return "G";
            case TelephonyManager.NETWORK_TYPE_GSM:
            case TelephonyManager.NETWORK_TYPE_CDMA:
            case TelephonyManager.NETWORK_TYPE_1xRTT:
                return "2G";
        }
        return "";
    }

    JSONObject cell() throws Exception {
        String state;
        int sim = tm.getSimState();
        if (sim == TelephonyManager.SIM_STATE_ABSENT) state = "no-sim";
        else if (sim == TelephonyManager.SIM_STATE_PIN_REQUIRED || sim == TelephonyManager.SIM_STATE_PUK_REQUIRED
                || sim == TelephonyManager.SIM_STATE_NETWORK_LOCKED) state = "locked";
        else if (serviceState == ServiceState.STATE_POWER_OFF) state = "off";
        else if (serviceState == ServiceState.STATE_IN_SERVICE) state = dataUp ? "connected" : "registered";
        else state = "searching";
        boolean registered = state.equals("registered") || state.equals("connected");
        return new JSONObject().put("t", "cell").put("modem", true).put("state", state)
                .put("strength", registered && level >= 0 ? level * 25 : -1)
                .put("tech", registered ? tech(networkType, overrideType) : "")
                .put("roaming", registered && roaming);
    }

    JSONObject wifi() throws Exception {
        int strength = -1;
        if (wifiUp && wifiRssi != Integer.MIN_VALUE) {
            int max = Math.max(1, wm.getMaxSignalLevel());
            strength = Math.round(100f * wm.calculateSignalLevel(wifiRssi) / max);
        }
        return new JSONObject().put("t", "wifi").put("enabled", wm.isWifiEnabled()).put("connected", wifiUp)
                .put("validated", wifiValidated).put("strength", strength);
    }

    private void sendCell(boolean force) {
        try {
            JSONObject o = cell();
            String s = o.toString();
            if (force || !s.equals(lastCell)) {
                lastCell = s;
                Link.get(ctx).send(o);
            }
        } catch (Exception e) {
            Log.w(Link.TAG, "cell state", e);
        }
    }

    private void sendWifi(boolean force) {
        try {
            JSONObject o = wifi();
            String s = o.toString();
            if (force || !s.equals(lastWifi)) {
                lastWifi = s;
                Link.get(ctx).send(o);
            }
        } catch (Exception e) {
            Log.w(Link.TAG, "wifi state", e);
        }
    }
}
