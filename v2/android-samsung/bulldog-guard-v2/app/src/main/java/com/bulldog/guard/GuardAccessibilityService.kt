package com.bulldog.guard

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * 精准无障碍守护服务 v2.3（全面封堵三星 One UI 8.5 所有可破坏 Bulldog 的系统设置入口）
 * 覆盖：
 *  1. 辅助功能 -> 已安装的应用程序 -> Bulldog / 守护详情开关页
 *  2. 应用程序 -> Bulldog / FlClash / 守护 应用信息页（强行停止/权限/电池/存储/悬浮窗）
 *  3. 特殊访问权限（使用情况数据访问 / 出现在顶部 / 设备管理应用 / 通知访问）中出现 Bulldog 时
 *  4. 电池 -> 休眠/深度休眠中试图限制 Bulldog 时
 * 放行：
 *  - 三星设置首页、Wi-Fi、蓝牙、声音、显示、其他普通 App（含 Mindful）全部 100% 放行
 *  - Bulldog App 本体（充值会员等）完全不监听、100% 放行
 */
class GuardAccessibilityService : AccessibilityService() {

    companion object {
        private val SETTINGS_PACKAGES = setOf(
            "com.android.settings",
            "com.samsung.android.settings",
            "com.google.android.permissioncontroller",
            "com.android.permissioncontroller"
        )

        private val SETTINGS_HOME_MARKERS = listOf(
            "声音和振动", "壁纸和风格", "锁定屏幕", "连接", "显示",
            "connections", "sounds and vibration", "wallpaper and style", "lock screen"
        )

        // 纯列表浏览页（无开关按钮），允许用户浏览去点其他普通 App
        private val SAFE_LIST_TITLES = listOf(
            "已安装的应用程序", "已安装的应用", "installed apps", "installed services"
        )

        private val PROTECTED_KEYWORDS = listOf(
            "bulldog blocker",
            "斗牛犬拦截器",
            "斗牛犬",
            "bulldog 精准无障碍守护",
            "精准无障碍守护",
            "flclash"
        )

        // 任何包含控制/禁用/撤销/休眠/权限/开关的特征
        private val CONTROL_MARKERS = listOf(
            "快捷方式", "shortcut", "停止使用", "关闭", "停用", "强行停止", "卸载",
            "清除数据", "存储", "权限", "电池", "不受限制", "优化", "受限制",
            "深度休眠", "休眠", "不允许", "拒绝", "取消激活", "设备管理",
            "使用情况数据", "出现在顶部", "悬浮窗", "turn off", "disable", "force stop",
            "uninstall", "permissions", "battery", "allow", "deny", "don't allow"
        )
    }

    private var lastBounceTime = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg !in SETTINGS_PACKAGES) return

        val clsName = event.className?.toString()?.lowercase() ?: ""
        if (clsName.contains("homepage") || clsName.contains("search")) return

        val root = rootInActiveWindow ?: return
        try {
            if (shouldBounce(root)) {
                val now = System.currentTimeMillis()
                if (now - lastBounceTime > 250) {
                    lastBounceTime = now
                    performGlobalAction(GLOBAL_ACTION_HOME)
                }
            }
        } finally {
            @Suppress("DEPRECATION")
            root.recycle()
        }
    }

    private fun shouldBounce(root: AccessibilityNodeInfo): Boolean {
        val allTexts = mutableListOf<String>()
        var hasInteractiveToggle = false
        var hasSearchBox = false

        fun traverse(node: AccessibilityNodeInfo?, depth: Int) {
            if (node == null || depth > 14) return
            val cls = node.className?.toString()?.lowercase() ?: ""
            if (cls.contains("switch") || cls.contains("checkbox") || cls.contains("radiobutton") || node.isCheckable) {
                hasInteractiveToggle = true
            }
            if (cls.contains("edittext") || cls.contains("searchview")) {
                hasSearchBox = true
            }
            node.text?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let { allTexts.add(it.lowercase()) }
            node.contentDescription?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let { allTexts.add(it.lowercase()) }

            for (i in 0 until node.childCount) {
                val child = node.getChild(i)
                traverse(child, depth + 1)
                @Suppress("DEPRECATION")
                child?.recycle()
            }
        }

        traverse(root, 0)
        if (allTexts.isEmpty()) return false

        val joined = allTexts.joinToString(" | ")

        // 0. 设置搜索页绝对放行（防止“最近搜索”历史里有 bulldog 导致无法搜索设置）
        if (hasSearchBox || joined.contains("最近搜索") || joined.contains("recent searches") || joined.contains("搜索设置")) {
            return false
        }

        // 1. 设置首页绝对放行
        if (SETTINGS_HOME_MARKERS.count { joined.contains(it) } >= 2) return false

        // 2. 纯无开关的“已安装的应用程序”列表页放行，方便你点其他 App（如 Mindful）
        if (!hasInteractiveToggle && SAFE_LIST_TITLES.any { joined.contains(it) }) return false

        // 3. 过滤掉“由 Bulldog Guard 管理”系统横幅，防止误伤
        val filtered = allTexts.filterNot {
            it.contains("归贵组织") || it.contains("管理") || it.contains("managed by") || it.contains("organization")
        }

        // 4. 命中受保护 App 名称（Bulldog / 斗牛犬 / 精准无障碍守护 / FlClash）
        val hitsProtected = PROTECTED_KEYWORDS.any { kw ->
            filtered.any { txt -> txt.contains(kw) }
        }
        if (!hitsProtected) return false

        // 5. 只要页面存在开关/单选框，或存在任何控制项（强停/权限/电池/休眠/悬浮窗/使用情况访问），立刻弹回！
        return hasInteractiveToggle || CONTROL_MARKERS.any { joined.contains(it) }
    }

    override fun onInterrupt() {}
}
