package com.s22.omarchyphone;

import android.content.ComponentName;
import android.content.Context;
import android.net.Uri;
import android.os.Bundle;
import android.telecom.Connection;
import android.telecom.ConnectionRequest;
import android.telecom.ConnectionService;
import android.telecom.DisconnectCause;
import android.telecom.PhoneAccount;
import android.telecom.PhoneAccountHandle;
import android.telecom.TelecomManager;
import android.util.Log;

/**
 * A pretend incoming call through Android's Telecom (a self-managed account, like a VoIP app's), so
 * the whole call path into Omarchy can be tried without a SIM: Telecom binds CallCompanion, the
 * bridge shows the call, and answering or hanging up from Omarchy comes back here.
 * `omarchy-phone test-call` starts one. No network, no audio, nothing leaves the phone.
 */
public class TestCallService extends ConnectionService {
    private static final String ACCOUNT = "omarchy-test";

    static PhoneAccountHandle handle(Context c) {
        return new PhoneAccountHandle(new ComponentName(c, TestCallService.class), ACCOUNT);
    }

    static void ring(Context c, String number, String name) {
        TelecomManager tm = c.getSystemService(TelecomManager.class);
        tm.registerPhoneAccount(PhoneAccount.builder(handle(c), "Omarchy test calls")
                .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED).build());
        Bundle inner = new Bundle();
        inner.putString("name", name);
        Bundle extras = new Bundle();
        extras.putParcelable(TelecomManager.EXTRA_INCOMING_CALL_ADDRESS, Uri.fromParts("tel", number, null));
        extras.putBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS, inner);
        tm.addNewIncomingCall(handle(c), extras);
    }

    @Override
    public Connection onCreateIncomingConnection(PhoneAccountHandle account, ConnectionRequest request) {
        TestConnection conn = new TestConnection();
        conn.setConnectionProperties(Connection.PROPERTY_SELF_MANAGED);
        conn.setAudioModeIsVoip(true);
        conn.setAddress(request.getAddress(), TelecomManager.PRESENTATION_ALLOWED);
        String name = request.getExtras() == null ? null : request.getExtras().getString("name");
        if (name != null) conn.setCallerDisplayName(name, TelecomManager.PRESENTATION_ALLOWED);
        conn.setRinging();
        return conn;
    }

    @Override
    public void onCreateIncomingConnectionFailed(PhoneAccountHandle account, ConnectionRequest request) {
        Log.w(Link.TAG, "test call refused by Telecom");
    }

    static final class TestConnection extends Connection {
        TestConnection() {
            setConnectionCapabilities(CAPABILITY_MUTE | CAPABILITY_HOLD | CAPABILITY_SUPPORT_HOLD);
        }

        @Override
        public void onAnswer(int videoState) {
            setActive();
        }

        @Override
        public void onAnswer() {
            setActive();
        }

        @Override
        public void onReject() {
            end(DisconnectCause.REJECTED);
        }

        @Override
        public void onDisconnect() {
            end(DisconnectCause.LOCAL);
        }

        @Override
        public void onAbort() {
            end(DisconnectCause.LOCAL);
        }

        @Override
        public void onHold() {
            setOnHold();
        }

        @Override
        public void onUnhold() {
            setActive();
        }

        private void end(int cause) {
            setDisconnected(new DisconnectCause(cause));
            destroy();
        }
    }
}
