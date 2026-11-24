package com.bulldog.guard

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.os.UserManager
import android.provider.Settings
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

class MainActivity : Activity() {
    private lateinit var statusTv: TextView
    private lateinit var logTv: TextView
    private lateinit var btnContainer: LinearLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val scroll = ScrollView(this)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 80, 48, 80)
        }

        val title = TextView(this).apply {
            text = "🛡️ Bulldog Guard v2 (三星底盘控制器)"
            textSize = 20f
            setPadding(0, 0, 0, 24)
        }

        statusTv = TextView(this).apply {
            textSize = 14f
            setPadding(0, 0, 0, 24)
        }

        btnContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }

        logTv = TextView(this).apply {
            textSize = 13f
            setPadding(0, 32, 0, 0)
        }

        root.addView(title)
        root.addView(statusTv)
        root.addView(btnContainer)
        root.addView(logTv)
        scroll.addView(root)
        setContentView(scroll)
    }

    override fun onResume() {
        super.onResume()
        refreshUi()
    }

    private fun addBtn(label: String, onClick: () -> Unit) {
        val b = Button(this).apply {
            text = label
            setOnClickListener { onClick() }
        }
        val lp = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = 16 }
        btnContainer.addView(b, lp)
    }

    private fun refreshUi() {
        val dpm = GuardPolicyManager.dpm(this)
        val admin = GuardPolicyManager.adminComponent(this)
        val isOwner = GuardPolicyManager.isDeviceOwner(this)
        val sealed = GuardPolicyManager.isSealed(this)

        val enabledA11y = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: ""
        val selfA11y = enabledA11y.contains(packageName, ignoreCase = true)
        val bulldogA11y = enabledA11y.contains("bulldog", ignoreCase = true)

        val vpnPkg = if (isOwner) try { dpm.getAlwaysOnVpnPackage(admin) } catch (_: Exception) { null } else null
        val restrictions = if (isOwner) try { dpm.getUserRestrictions(admin) } catch (_: Exception) { null } else null
        val appsLocked = restrictions?.getBoolean(UserManager.DISALLOW_APPS_CONTROL) == true
        val vpnLocked = restrictions?.getBoolean(UserManager.DISALLOW_CONFIG_VPN) == true
        val dnsLocked = restrictions?.getBoolean(UserManager.DISALLOW_CONFIG_PRIVATE_DNS) == true
        val usbLocked = restrictions?.getBoolean(UserManager.DISALLOW_DEBUGGING_FEATURES) == true

        statusTv.text = buildString {
            appendLine("• Device Owner 权限：${if (isOwner) "✅ 已激活" else "❌ 未激活"}")
            appendLine("• 运行模式：${if (sealed) "🔒 正式封口模式（解锁需等 2 小时）" else "🧪 测试模式（可随时撤销）"}")
            appendLine("• 唯一常驻 VPN：${vpnPkg ?: "未绑定"} (${if (vpnLocked) "🔒其他VPN已封死" else "未锁"})")
            appendLine("• 禁强行停止/清数据：${if (appsLocked) "✅ 已锁死" else "⚠️ 未开启"}")
            appendLine("• AdGuard 私密 DNS：${if (dnsLocked) "✅ 已锁死 (family.adguard-dns.com)" else "⚠️ 未锁"}")
            appendLine("• USB 调试锁定：${if (usbLocked) "🔒 已锁定" else "🧪 暂未锁（试运行3天后再开）"}")
            appendLine("• 本守护无障碍：${if (selfA11y) "✅ 运行中" else "⚠️ 请点下方按钮开启"}")
            appendLine("• Bulldog 无障碍：${if (bulldogA11y) "✅ 运行中" else "⚠️ 未开启"}")
        }

        btnContainer.removeAllViews()

        addBtn("1️⃣ 一键开启核心防护（锁唯一VPN + 禁强停 + AdGuard DNS + 禁安全模式）") {
            val res = GuardPolicyManager.applyCoreLocks(this, lockUsb = GuardPolicyManager.isUsbLocked(this))
            logTv.text = res.joinToString("\n")
            refreshUi()
        }

        addBtn("2️⃣ 前往开启【Bulldog 精准无障碍守护】开关") {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        }

        if (!sealed) {
            addBtn("🧪 [测试模式] 临时解除全部策略（便于调试）") {
                val res = GuardPolicyManager.clearAllLocks(this)
                logTv.text = res.joinToString("\n")
                refreshUi()
            }
            addBtn("🔒 确认一切正常后：进入【正式封口模式】（2小时延迟解锁）") {
                AlertDialog.Builder(this)
                    .setTitle("确认进入正式封口模式？")
                    .setMessage("进入后，立即撤销按钮将被隐藏。以后如果想解除任何策略，必须先点申请并等待 2 小时冷静期才能生效。")
                    .setPositiveButton("确认封口") { _, _ ->
                        GuardPolicyManager.applyCoreLocks(this, lockUsb = false)
                        GuardPolicyManager.sealOfficially(this)
                        logTv.text = "🔒 已正式封口！核心策略已锁死，解锁需等待 2 小时冷静期。"
                        refreshUi()
                    }
                    .setNegativeButton("再测试一下", null)
                    .show()
            }
        } else {
            if (!usbLocked) {
                addBtn("🔒 [最后一步] 试运行 3 天无问题后：锁死 USB 调试") {
                    AlertDialog.Builder(this)
                        .setTitle("锁死 USB 调试？")
                        .setMessage("开启后电脑将无法通过 ADB 绕过策略（需等 2 小时解锁冷静期后才可重新打开 USB 调试）。确认当前夸克/微信/流量一切正常？")
                        .setPositiveButton("确认锁死 USB") { _, _ ->
                            val res = GuardPolicyManager.applyCoreLocks(this, lockUsb = true)
                            logTv.text = res.joinToString("\n")
                            refreshUi()
                        }
                        .setNegativeButton("取消", null)
                        .show()
                }
            }

            val readyAt = GuardPolicyManager.unlockReadyAt(this)
            val now = System.currentTimeMillis()
            if (readyAt == 0L) {
                addBtn("⏳ 申请解除限制（需等待 2 小时冷静期）") {
                    GuardPolicyManager.requestTimedUnlock(this)
                    logTv.text = "⏳ 已发起解锁倒计时（2 小时后生效）。冲动退潮后随时可以点取消！"
                    refreshUi()
                }
            } else if (now < readyAt) {
                val minsLeft = ((readyAt - now) / 60000L) + 1
                addBtn("🛑 冷静期倒计时中（剩余约 ${minsLeft} 分钟）—— 点此取消解锁申请") {
                    GuardPolicyManager.cancelTimedUnlock(this)
                    logTv.text = "✅ 已取消解锁申请，继续保持防护！"
                    refreshUi()
                }
            } else {
                addBtn("🔓 2 小时冷静期已满 —— 执行解除全部限制") {
                    val res = GuardPolicyManager.clearAllLocks(this)
                    logTv.text = res.joinToString("\n")
                    refreshUi()
                }
            }
        }
    }
}
