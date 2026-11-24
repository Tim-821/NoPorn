package com.bulldog.guard

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action == Intent.ACTION_BOOT_COMPLETED || action == Intent.ACTION_LOCKED_BOOT_COMPLETED) {
            if (GuardPolicyManager.isSealed(context)) {
                GuardPolicyManager.applyCoreLocks(context, lockUsb = GuardPolicyManager.isUsbLocked(context))
            }
        }
    }
}
