package com.bulldog.guard

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class PolicyCommandReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        val result = when (action) {
            "com.bulldog.guard.ACTION_APPLY_LOCKS" -> {
                GuardPolicyManager.sealOfficially(context)
                GuardPolicyManager.applyCoreLocks(context, lockUsb = false)
            }
            "com.bulldog.guard.ACTION_LOCK_USB" -> {
                GuardPolicyManager.sealOfficially(context)
                GuardPolicyManager.applyCoreLocks(context, lockUsb = true)
            }
            "com.bulldog.guard.ACTION_CLEAR_LOCKS" -> {
                GuardPolicyManager.clearAllLocks(context)
            }
            else -> listOf("Unknown action: $action")
        }
        Log.i("BulldogGuardV2", "Action=$action -> ${result.joinToString(" | ")}")
    }
}
