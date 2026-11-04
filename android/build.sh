#!/bin/bash
# Flight 钥匙 APK 编译脚本
# 环境已持久化在 ~/Library/Java 与 ~/Library/gradle，重启不丢
# 注意：必须绕开 WorkBuddy 注入的 56679 慢代理，显式走 Clash 7897
set -e
export JAVA_HOME="$HOME/Library/Java/jdk-17.0.21+9/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy

cd "$(dirname "$0")"

"$HOME/Library/gradle/gradle-8.9/bin/gradle" assembleDebug \
  -Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7897 \
  -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7897 \
  -Dorg.gradle.daemon=false \
  "$@"

echo
echo "APK: $(pwd)/app/build/outputs/apk/debug/app-debug.apk"
