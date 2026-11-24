package com.bulldog.guard

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.UserManager

object GuardPolicyManager {
    private const val PREF_NAME = "bulldog_guard_v2_prefs"
    private const val KEY_SEALED = "sealed_mode"
    private const val KEY_USB_LOCKED = "usb_locked"
    private const val KEY_UNLOCK_READY_AT = "unlock_ready_at_ms"

    // 正式封口后申请解除需等待的冷静期（2 小时）
    const val UNLOCK_DELAY_MS = 2L * 60L * 60L * 1000L

    const val PKG_BULLDOG = "com.everaccountable.bulldog"
    const val PKG_FLCLASH_LOCKED = "com.guard.flclash.locked"
    const val PKG_FLCLASH_ORIG = "com.follow.clash"
    const val ADGUARD_FAMILY_DOT = "family.adguard-dns.com"

    fun adminComponent(context: Context) = ComponentName(context, AdminReceiver::class.java)

    fun dpm(context: Context) =
        context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

    fun isDeviceOwner(context: Context): Boolean = dpm(context).isDeviceOwnerApp(context.packageName)

    fun prefs(context: Context) = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)

    fun isSealed(context: Context) = prefs(context).getBoolean(KEY_SEALED, false)

    fun isUsbLocked(context: Context) = prefs(context).getBoolean(KEY_USB_LOCKED, false)

    fun unlockReadyAt(context: Context) = prefs(context).getLong(KEY_UNLOCK_READY_AT, 0L)

    fun isPackageInstalled(context: Context, pkg: String): Boolean = try {
        context.packageManager.getPackageInfo(pkg, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    /**
     * 优先锁定定制阉割版 FlClash；如果还没装定制版，则回退检查官方版
     */
    fun targetVpnPackage(context: Context): String? = when {
        isPackageInstalled(context, PKG_FLCLASH_LOCKED) -> PKG_FLCLASH_LOCKED
        isPackageInstalled(context, PKG_FLCLASH_ORIG) -> PKG_FLCLASH_ORIG
        else -> null
    }

    /**
     * 一键施加全部核心底层策略（允许正常安装普通 App，但禁止启动其他任何 VPN！）
     */
    fun applyCoreLocks(context: Context, lockUsb: Boolean = false): List<String> {
        val logs = mutableListOf<String>()
        val dpm = dpm(context)
        val admin = adminComponent(context)
        if (!dpm.isDeviceOwnerApp(context.packageName)) {
            return listOf("❌ 当前不是 Device Owner，无法执行系统策略")
        }

        // 1. 禁止卸载核心三件套
        val protectPkgs = listOfNotNull(
            context.packageName,
            if (isPackageInstalled(context, PKG_BULLDOG)) PKG_BULLDOG else null,
            targetVpnPackage(context)
        )
        for (pkg in protectPkgs) {
            try {
                dpm.setUninstallBlocked(admin, pkg, true)
                logs.add("✅ 防卸载已开启: $pkg")
            } catch (e: Exception) {
                logs.add("⚠️ 防卸载失败($pkg): ${e.message}")
            }
        }

        // 2. 禁止“强行停止 / 清除数据”（彻底堵死 Bulldog 强行停止漏洞）
        try {
            dpm.addUserRestriction(admin, UserManager.DISALLOW_APPS_CONTROL)
            logs.add("✅ 已开启 DISALLOW_APPS_CONTROL（强行停止/清除数据变灰）")
        } catch (e: Exception) {
            logs.add("⚠️ DISALLOW_APPS_CONTROL 失败: ${e.message}")
        }

        // 3. 锁死唯一 VPN 通道 + 禁止其他一切 VPN 启动（仍可正常下载安装普通 App！）
        val vpnPkg = targetVpnPackage(context)
        if (vpnPkg != null) {
            try {
                // lockdownEnabled=false 确保国内流量/切换网络不断网，同时 DISALLOW_CONFIG_VPN 封死一切其他 VPN
                dpm.setAlwaysOnVpnPackage(admin, vpnPkg, false)
                dpm.addUserRestriction(admin, UserManager.DISALLOW_CONFIG_VPN)
                logs.add("✅ 已锁死唯一 VPN 通道: $vpnPkg（其他一切 VPN 无法启动）")
            } catch (e: Exception) {
                logs.add("⚠️ Always-On VPN 设置失败: ${e.message}")
            }
        } else {
            logs.add("⚠️ 未检测到 FlClash，跳过 Always-On VPN 绑定")
        }

        // 4. 锁死系统私密 DNS = AdGuard Family（免费无限量，关代理直连时兜底）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                dpm.setGlobalPrivateDnsModeSpecifiedHost(admin, ADGUARD_FAMILY_DOT)
                dpm.addUserRestriction(admin, UserManager.DISALLOW_CONFIG_PRIVATE_DNS)
                logs.add("✅ 已锁死私密 DNS: $ADGUARD_FAMILY_DOT")
            } catch (e: Exception) {
                logs.add("⚠️ 私密 DNS 锁定失败: ${e.message}")
            }
        }

        // 5. 禁止安全模式
        try {
            dpm.addUserRestriction(admin, UserManager.DISALLOW_SAFE_BOOT)
            logs.add("✅ 已禁用安全模式 (DISALLOW_SAFE_BOOT)")
        } catch (e: Exception) {
            logs.add("⚠️ 禁用安全模式失败: ${e.message}")
        }

        // 6. 最终封口才开启：禁用 USB 调试
        if (lockUsb) {
            try {
                dpm.addUserRestriction(admin, UserManager.DISALLOW_DEBUGGING_FEATURES)
                prefs(context).edit().putBoolean(KEY_USB_LOCKED, true).apply()
                logs.add("🔒 已禁用 USB 调试 (DISALLOW_DEBUGGING_FEATURES)")
            } catch (e: Exception) {
                logs.add("⚠️ 禁用 USB 调试失败: ${e.message}")
            }
        }

        return logs
    }

    /**
     * 解除所有限制（仅测试模式立即可用；正式封口模式需等满 2 小时冷静期）
     */
    fun clearAllLocks(context: Context): List<String> {
        val logs = mutableListOf<String>()
        val dpm = dpm(context)
        val admin = adminComponent(context)
        if (!dpm.isDeviceOwnerApp(context.packageName)) return listOf("非 Device Owner")

        val restrictions = listOf(
            UserManager.DISALLOW_APPS_CONTROL,
            UserManager.DISALLOW_CONFIG_VPN,
            UserManager.DISALLOW_CONFIG_PRIVATE_DNS,
            UserManager.DISALLOW_SAFE_BOOT,
            UserManager.DISALLOW_DEBUGGING_FEATURES
        )
        for (r in restrictions) {
            try {
                dpm.clearUserRestriction(admin, r)
            } catch (_: Exception) {}
        }
        try {
            dpm.setAlwaysOnVpnPackage(admin, null, false)
        } catch (_: Exception) {}
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                dpm.setGlobalPrivateDnsModeOpportunistic(admin)
            } catch (_: Exception) {}
        }
        for (pkg in listOf(context.packageName, PKG_BULLDOG, PKG_FLCLASH_LOCKED, PKG_FLCLASH_ORIG)) {
            try {
                dpm.setUninstallBlocked(admin, pkg, false)
            } catch (_: Exception) {}
        }
        prefs(context).edit()
            .putBoolean(KEY_SEALED, false)
            .putBoolean(KEY_USB_LOCKED, false)
            .putLong(KEY_UNLOCK_READY_AT, 0L)
            .apply()
        logs.add("🔓 已解除全部策略限制（Device Owner 身份仍保留，随时可重新一键上锁）")
        return logs
    }

    fun sealOfficially(context: Context) {
        prefs(context).edit()
            .putBoolean(KEY_SEALED, true)
            .putLong(KEY_UNLOCK_READY_AT, 0L)
            .apply()
    }

    fun requestTimedUnlock(context: Context): Long {
        val readyAt = System.currentTimeMillis() + UNLOCK_DELAY_MS
        prefs(context).edit().putLong(KEY_UNLOCK_READY_AT, readyAt).apply()
        return readyAt
    }

    fun cancelTimedUnlock(context: Context) {
        prefs(context).edit().putLong(KEY_UNLOCK_READY_AT, 0L).apply()
    }
}
