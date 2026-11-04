#!/bin/bash
# Flight 授权系统部署（以 root 运行）
set -uo pipefail

SRC="/tmp/fsrc20261103"
DB="/var/db/flight"
LOG="/tmp/flight-deploy.log"
exec > "$LOG" 2>&1
echo "=== $(date) ==="

die() { echo "FAIL: $*"; exit 1; }

[[ -f "$SRC/install.py" ]] || die "暂存目录缺失，请先执行暂存步骤"
echo "source dir OK: $SRC"

# ---------- 目录 ----------
mkdir -p /usr/local/bin /usr/local/lib/flight "$DB" || die "建目录失败"
chmod 700 "$DB"

# ---------- 安装执行器（root 所有）----------
cp -f "$SRC/install.py" /usr/local/lib/flight/install.py || die "cp install.py"
chown root:wheel /usr/local/lib/flight/install.py
chmod 755 /usr/local/lib/flight/install.py

cat > /usr/local/bin/flight-install <<'EOS'
#!/bin/bash
exec /usr/bin/python3 /usr/local/lib/flight/install.py "$@"
EOS
chown root:wheel /usr/local/bin/flight-install
chmod 755 /usr/local/bin/flight-install
echo "installer OK"

# ---------- 请求端 ----------
cp -f "$SRC/flight-request" /usr/local/bin/flight-request || die "cp flight-request"
chown root:wheel /usr/local/bin/flight-request
chmod 755 /usr/local/bin/flight-request
echo "request OK"

# ---------- 自愈 ----------
cp -f "$SRC/flight-watchdog" /usr/local/bin/flight-watchdog || die "cp watchdog"
chown root:wheel /usr/local/bin/flight-watchdog
chmod 755 /usr/local/bin/flight-watchdog
echo "watchdog OK"

# ---------- 公钥 ----------
cp -f "$SRC/flight-pub.pem" "$DB/pubkey.pem" || die "cp pubkey"
chown root:wheel "$DB/pubkey.pem"
chmod 644 "$DB/pubkey.pem"
echo "pubkey OK"

# ---------- sudoers：唯一的免密通道 ----------
cat > /etc/sudoers.d/flight-install <<'EOS'
youruser ALL=(root) NOPASSWD: /usr/local/bin/flight-install
EOS
chown root:wheel /etc/sudoers.d/flight-install
chmod 440 /etc/sudoers.d/flight-install
visudo -c -f /etc/sudoers.d/flight-install >/dev/null 2>&1 || die "sudoers 语法错误"
echo "sudoers OK"

# ---------- LaunchDaemon ----------
cat > /Library/LaunchDaemons/com.flight.watchdog.plist <<'EOS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.flight.watchdog</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/local/bin/flight-watchdog</string>
		<string>--once</string>
	</array>
	<key>StartInterval</key>
	<integer>30</integer>
	<key>RunAtLoad</key>
	<true/>
	<key>StandardErrorPath</key>
	<string>/var/db/flight/stderr.log</string>
</dict>
</plist>
EOS
chown root:wheel /Library/LaunchDaemons/com.flight.watchdog.plist
chmod 644 /Library/LaunchDaemons/com.flight.watchdog.plist
echo "plist OK"

# ---------- 日志文件 ----------
: > "$DB/guard.log"; chmod 600 "$DB/guard.log"
: > "$DB/watchdog.log"; chmod 600 "$DB/watchdog.log"

# ---------- 设策略基准 ----------
/usr/local/bin/flight-watchdog --accept && echo "baseline OK"

# ---------- 启动 watchdog ----------
launchctl bootout system/com.flight.watchdog 2>/dev/null
launchctl bootstrap system /Library/LaunchDaemons/com.flight.watchdog.plist 2>&1
launchctl enable system/com.flight.watchdog 2>&1
echo "watchdog loaded"

sleep 2
launchctl print system/com.flight.watchdog 2>&1 | head -5

echo "=== DONE ==="
