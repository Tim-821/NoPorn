#!/bin/bash
# ==============================================================================
# 三星手机 Device Owner 施工前检测 & ADB 辅助脚本
# 用法：手机开启 USB 调试并连上 Mac 后，运行 bash adb-lock-samsung.sh
# 本脚本默认只做只读诊断，所有写入操作都需要你手动确认，不会误锁手机！
# ==============================================================================
set -euo pipefail

if ! command -v adb >/dev/null 2>&1; then
  echo "❌ 未检测到 adb，请先安装 Android Platform Tools（例如：brew install android-platform-tools）"
  exit 1
fi

echo "=========================================="
echo "1. 检测已连接的三星设备"
echo "=========================================="
adb devices -l

echo ""
echo "=========================================="
echo "2. 读取设备型号与安卓版本"
echo "=========================================="
MODEL=$(adb shell getprop ro.product.model | tr -d '\r')
ANDROID_VER=$(adb shell getprop ro.build.version.release | tr -d '\r')
ONEUI_VER=$(adb shell getprop ro.build.version.oneui | tr -d '\r')
echo "型号: ${MODEL} | Android: ${ANDROID_VER} | One UI: ${ONEUI_VER:-未知}"

echo ""
echo "=========================================="
echo "3. 检查当前是否已有 Device Owner（此设备归贵组织所有）"
echo "=========================================="
adb shell dumpsys device_policy | grep -A 5 -iE "Device Owner|Profile Owner" || echo "（当前无 Device Owner）"

echo ""
echo "=========================================="
echo "4. 检测已安装的 Bulldog / FlClash / OwnDroid / Andoff 包名"
echo "=========================================="
adb shell pm list packages | grep -iE "bulldog|clash|owndroid|andoff|guard" || echo "（暂未检测到上述应用）"

echo ""
echo "=========================================="
echo "5. 施工指令速查（等你确认手机账号状态后逐条执行）"
echo "=========================================="
cat <<'EOF'
【重要提示】在三星上设置新的 Device Owner 前：
  - 如果之前已经挂着旧的 Device Owner（如旧版 TestDPC），需先在旧软件里移除 Device Owner，或备份后恢复出厂设置；
  - 需临时退出手机里的 Google 账号、三星账号、以及关闭“安全文件夹/双开应用（Work Profile）”（设完 Device Owner 后可以全部重新登录回来！）。

【激活 Device Owner（二选一）】
  • 选项 A（推荐 OwnDroid — 策略最全，支持细粒度锁 VPN + 禁强停 + 锁私密DNS）:
      adb shell dpm set-device-owner com.bintianqi.owndroid/.Receiver
  • 选项 B（推荐 Andoff — 自带时间延迟锁 + 一键锁 1 小时防冲动）:
      adb shell dpm set-device-owner one.andoff.andoff/.AdminReceiver

【激活后，在 OwnDroid / Andoff 界面内逐项开启的 5 条核心策略】
  1. 网络 → 始终开启的 VPN (Always-On VPN) → 选择【阉割锁定版 FlClash】
  2. 用户限制 → 开启 DISALLOW_CONFIG_VPN（禁止配置/启用其他任何 VPN，但不影响下载普通 App！）
  3. 用户限制 → 开启 DISALLOW_APPS_CONTROL（灰掉所有 App 的“强行停止 / 清除数据”）
     + 应用管理 → 禁止卸载：勾选 Bulldog、锁定版 FlClash、精准无障碍守护 App
  4. 网络 → 私密 DNS → 指定主机名：family.adguard-dns.com
     + 开启 DISALLOW_CONFIG_PRIVATE_DNS（锁死私密 DNS）
  5. 安全限制 → 开启 DISALLOW_SAFE_BOOT（禁止进安全模式）
     ⚠️ 稳定试运行 3 天确认夸克/微信/流量全正常后，最后再开启 DISALLOW_DEBUGGING_FEATURES（锁 USB 调试）！
EOF
