#!/bin/bash
# ==============================================================================
# Mac 端 safe-install 一键部署脚本
# 必须在管理员账号 (guard) 下执行：sudo bash setup-mac-gatekeeper.sh
# ==============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "❌ 请使用管理员账号 guard 执行：sudo bash $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_PY="/usr/local/libexec/guard-safe-install.py"
WRAPPER="/usr/local/bin/safe-install"
CFG_DIR="/etc/guard-gatekeeper"
CFG_FILE="${CFG_DIR}/config.json"
SUDOERS_FILE="/etc/sudoers.d/guard-safe-install"

echo "👉 1. 安装核心脚本至 ${TARGET_PY} (root 只读)"
mkdir -p /usr/local/libexec /usr/local/bin "${CFG_DIR}"
cp "${SCRIPT_DIR}/safe-install.py" "${TARGET_PY}"
chown root:wheel "${TARGET_PY}"
chmod 755 "${TARGET_PY}"

echo "👉 2. 创建普通账号免密启动命令 ${WRAPPER}"
cat > "${WRAPPER}" <<'EOF'
#!/bin/bash
exec sudo -n /usr/local/libexec/guard-safe-install.py "$@"
EOF
chown root:wheel "${WRAPPER}"
chmod 755 "${WRAPPER}"

echo "👉 3. 写入窄权限 sudoers（仅允许 YOUR_STANDARD_USER 免密运行 safe-install，绝不开放其他权限）"
cat > "${SUDOERS_FILE}" <<'EOF'
Defaults!/usr/local/libexec/guard-safe-install.py env_reset
YOUR_STANDARD_USER ALL=(root) NOPASSWD: /usr/local/libexec/guard-safe-install.py *
EOF
chown root:wheel "${SUDOERS_FILE}"
chmod 440 "${SUDOERS_FILE}"
visudo -c -f "${SUDOERS_FILE}"

if [[ -f "${SCRIPT_DIR}/generated-config.json" ]]; then
  echo "👉 4. 迁入已生成的 Worker 密钥配置至 ${CFG_FILE}（仅 root 可读写），并销毁明文临时文件"
  mv "${SCRIPT_DIR}/generated-config.json" "${CFG_FILE}"
  chown root:wheel "${CFG_FILE}"
  chmod 600 "${CFG_FILE}"
elif [[ ! -f "${CFG_FILE}" ]]; then
  echo "👉 4. 生成密钥配置模板 ${CFG_FILE} (仅 root 可读写，YOUR_STANDARD_USER 不可见)"
  cat > "${CFG_FILE}" <<'EOF'
{
  "worker_url": "https://guard-gatekeeper.your-subdomain.workers.dev",
  "client_auth_token": "REPLACE_WITH_RANDOM_64_HEX",
  "ticket_hmac_secret": "REPLACE_WITH_ANOTHER_RANDOM_64_HEX"
}
EOF
  chown root:wheel "${CFG_FILE}"
  chmod 600 "${CFG_FILE}"
  echo "⚠️  请编辑 ${CFG_FILE}，填入与 Cloudflare Worker 一致的 URL 和密钥！"
else
  echo "ℹ️  保留已存在的 ${CFG_FILE}"
fi

echo "👉 5. 安装原生【安装助手.app】和 Mac 极简锁定版【FlClash.app】到 /Applications (归 root 只读)"
DL_DIR="$(cd "${SCRIPT_DIR}/../../downloads" && pwd)"
if [[ -d "${DL_DIR}/安装助手.app" ]]; then
  rm -rf "/Applications/安装助手.app"
  cp -R "${DL_DIR}/安装助手.app" "/Applications/安装助手.app"
  chown -R root:wheel "/Applications/安装助手.app"
  chmod -R go-w "/Applications/安装助手.app"
  echo "   ✅ 已安装 /Applications/安装助手.app（可拖到 Dock 栏随时拖拽安装）"
fi
if [[ -d "${DL_DIR}/FlClash.app" ]]; then
  rm -rf "/Applications/FlClash.app"
  cp -R "${DL_DIR}/FlClash.app" "/Applications/FlClash.app"
  chown -R root:wheel "/Applications/FlClash.app"
  chmod -R go-w "/Applications/FlClash.app"
  echo "   ✅ 已安装 /Applications/FlClash.app（极简锁定版，2 标签速度/纯净）"
fi

echo "✅ Mac 端全部本地组件部署完成！以后在普通账号 YOUR_STANDARD_USER 下把 .dmg/.app/.pkg 拖到【安装助手】图标即可自动审核安装！"
