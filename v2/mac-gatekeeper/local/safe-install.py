#!/usr/bin/env python3
"""
Guard Safe-Install (root 权限安全安装助手)
部署位置：/usr/local/libexec/guard-safe-install.py (root:wheel, chmod 755)
配置位置：/etc/guard-gatekeeper/config.json        (root:wheel, chmod 600)

用法（普通账号 YOUR_STANDARD_USER 无需输入 guard 密码）：
  safe-install /Users/YOUR_STANDARD_USER/Downloads/Notion.dmg
  safe-install /Users/YOUR_STANDARD_USER/Downloads/XuetangX.app
  safe-install /Users/YOUR_STANDARD_USER/Downloads/SomeApp.pkg

安全机制：
  1. 先把安装包复制到 root 独占的临时隔离区（防止审核通过后被普通账号掉包 TOCTOU）
  2. 提取客观元数据：SHA-256、Bundle ID、开发者签名、苹果公证状态、Entitlements(查 VPN 权限)、内部可疑内核
  3. 发送给远端不可对话 AI 审核器；如 AI 误判（如学堂在线），可一键推送给朋友手机点击同意
  4. 本地严格校验远端返回的 HMAC-SHA256 一次性加密票据（绑定文件哈希 + 5分钟过期 + 防重放）
  5. 校验通过后由 root 自动安装至 /Applications（只读保护，普通账号无法篡改）
"""

import hashlib
import hmac
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

CONFIG_PATH = Path("/etc/guard-gatekeeper/config.json")
NONCE_DB = Path("/var/db/guard-gatekeeper-nonces.log")
STAGING_ROOT = Path("/var/root/.guard-staging")

SUSPICIOUS_NAMES = (
    "mihomo", "clash", "flclash", "sing-box", "singbox", "xray", "v2ray",
    "hysteria", "shadowsocks", "ss-local", "trojan", "wireguard", "openvpn",
    "tor", "nekoray", "hiddify", "karing", "surge", "stash", "loon", "proxifier"
)


def die(msg: str, code: int = 1):
    print(f"\n❌ [拦截/失败] {msg}", file=sys.stderr)
    sys.exit(code)


def run_cmd(cmd, check=False):
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_app_bundle(app_path: Path) -> str:
    """对整个 .app 目录内的所有文件名与内容做确定性 SHA-256"""
    h = hashlib.sha256()
    for root, dirs, files in os.walk(app_path):
        dirs.sort()
        files.sort()
        for name in files:
            p = Path(root) / name
            if p.is_symlink():
                h.update(f"SYM:{p.relative_to(app_path)}->{os.readlink(p)}".encode())
            elif p.is_file():
                h.update(f"FILE:{p.relative_to(app_path)}:".encode())
                with p.open("rb") as f:
                    for chunk in iter(lambda: f.read(1024 * 1024), b""):
                        h.update(chunk)
    return h.hexdigest()


def inspect_app(app_path: Path) -> dict:
    info_plist = app_path / "Contents" / "Info.plist"
    bundle_id = ""
    app_name = app_path.stem
    if info_plist.exists():
        try:
            with info_plist.open("rb") as f:
                pl = plistlib.load(f)
            bundle_id = str(pl.get("CFBundleIdentifier", ""))
            app_name = str(pl.get("CFBundleDisplayName") or pl.get("CFBundleName") or app_path.stem)
        except Exception:
            pass

    # 1. codesign 开发者签名与 Team ID
    cs = run_cmd(["codesign", "-dv", "--verbose=4", str(app_path)])
    cs_out = cs.stderr + "\n" + cs.stdout
    team_id = ""
    signers = []
    for line in cs_out.splitlines():
        if line.startswith("TeamIdentifier="):
            team_id = line.split("=", 1)[1].strip()
        elif line.startswith("Authority="):
            signers.append(line.split("=", 1)[1].strip())

    # 2. Entitlements 权限提取（重点检测 VPN / NetworkExtension）
    ent_proc = run_cmd(["codesign", "-d", "--entitlements", ":-", str(app_path)])
    entitlements = []
    if ent_proc.returncode == 0 and ent_proc.stdout.strip():
        for line in ent_proc.stdout.splitlines():
            line = line.strip()
            if "<key>" in line and "</key>" in line:
                key = line.replace("<key>", "").replace("</key>", "").strip()
                entitlements.append(key)

    # 3. 苹果公证 (Notarization / Gatekeeper) 检查
    spctl = run_cmd(["spctl", "-a", "-vvv", "-t", "exec", str(app_path)])
    spctl_out = (spctl.stdout + "\n" + spctl.stderr).lower()
    notarized = (spctl.returncode == 0) and ("accepted" in spctl_out)

    # 4. 扫描包内是否夹带代理/VPN 内核可执行文件
    suspicious = []
    for root, _, files in os.walk(app_path):
        for fn in files:
            low = fn.lower()
            for kw in SUSPICIOUS_NAMES:
                if kw in low:
                    suspicious.append(fn)
                    break

    return {
        "app_name": app_name,
        "bundle_id": bundle_id,
        "team_id": team_id,
        "signer": " / ".join(signers[:2]) if signers else "未签名",
        "notarized": notarized,
        "entitlements": entitlements,
        "suspicious_binaries": sorted(set(suspicious))[:30],
    }


def inspect_pkg(pkg_path: Path) -> dict:
    sig = run_cmd(["pkgutil", "--check-signature", str(pkg_path)])
    out = sig.stdout + "\n" + sig.stderr
    notarized = "signed by a developer certificate issued by apple" in out.lower() and "notarization" in out.lower()
    if "status: signed by a developer certificate issued by apple" in out.lower():
        # 部分官方老 pkg 未显示 notarization 字样，借助 spctl 二次判断
        sp = run_cmd(["spctl", "-a", "-vvv", "-t", "install", str(pkg_path)])
        if sp.returncode == 0:
            notarized = True
    signer = ""
    for line in out.splitlines():
        if "1. Developer ID Installer:" in line or "1. Software Update" in line:
            signer = line.strip()
            break
    return {
        "app_name": pkg_path.stem,
        "bundle_id": f"pkg:{pkg_path.name}",
        "team_id": "",
        "signer": signer or "未知安装包签名",
        "notarized": notarized,
        "entitlements": [],
        "suspicious_binaries": [pkg_path.name] if any(k in pkg_path.name.lower() for k in SUSPICIOUS_NAMES) else [],
    }


def api_request(cfg: dict, path: str, method: str = "GET", payload: dict = None) -> dict:
    url = cfg["worker_url"].rstrip("/") + path
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    headers = {
        "Authorization": f"Bearer {cfg['client_auth_token']}",
        "Content-Type": "application/json",
        "User-Agent": "GuardSafeInstall/1.0 (macOS)",
    }
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="ignore")
        die(f"远端审核服务返回错误 HTTP {e.code}: {body}")
    except Exception as e:
        die(f"无法连接远端审核服务（断网或 API 不可用时禁止安装）: {e}")


def verify_ticket(ticket: dict, expected_sha256: str, expected_bundle: str, secret: str):
    if not isinstance(ticket, dict):
        die("无效的授权票据格式")
    t_sha = ticket.get("sha256", "")
    t_bundle = ticket.get("bundle_id", "")
    t_issuer = ticket.get("issuer", "")
    t_exp = int(ticket.get("exp", 0))
    t_nonce = ticket.get("nonce", "")
    t_sig = ticket.get("sig", "")

    if t_sha != expected_sha256:
        die("安全警报：票据文件哈希不匹配！")
    if t_bundle != expected_bundle:
        die("安全警报：票据 Bundle ID 不匹配！")
    if time.time() > t_exp:
        die("授权票据已过期（超过 5 分钟），请重新申请。")

    payload = f"{t_sha}|{t_bundle}|{t_issuer}|{t_exp}|{t_nonce}".encode("utf-8")
    expected_sig = hmac.new(secret.encode("utf-8"), payload, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected_sig, t_sig):
        die("安全警报：票据 HMAC 签名伪造或无效！")

    # 防重放检查
    used = set()
    if NONCE_DB.exists():
        used = set(NONCE_DB.read_text().splitlines())
    if t_nonce in used:
        die("安全警报：该一次性票据已被使用过，拒绝重放！")
    with NONCE_DB.open("a") as f:
        f.write(f"{t_nonce}\n")
    os.chmod(NONCE_DB, 0o600)


def main():
    if os.geteuid() != 0:
        die("此脚本必须通过 safe-install (root 权限) 运行。")

    if len(sys.argv) != 2:
        print("用法：safe-install <安装包路径 (.dmg / .app / .pkg)>")
        sys.exit(1)

    if not CONFIG_PATH.exists():
        die(f"未找到配置文件 {CONFIG_PATH}，请先由管理员完成初始化。")

    cfg = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    src = Path(sys.argv[1]).resolve()
    if not src.exists():
        die(f"找不到文件：{src}")

    suffix = src.suffix.lower()
    if suffix not in (".dmg", ".app", ".pkg"):
        die("仅支持安装 .dmg / .app / .pkg 格式软件。")

    # 1. 建立 root 独占隔离区，防止审核过程中被调包
    STAGING_ROOT.mkdir(parents=True, exist_ok=True)
    os.chmod(STAGING_ROOT, 0o700)
    work_dir = STAGING_ROOT / uuid.uuid4().hex
    work_dir.mkdir(mode=0o700)

    mount_point = None
    try:
        print(f"📦 [1/4] 正在隔离并提取软件信息：{src.name} ...")
        staged_target = work_dir / src.name
        if src.is_dir():
            shutil.copytree(src, staged_target, symlinks=True)
        else:
            shutil.copy2(src, staged_target)

        install_kind = None
        install_obj = None

        if suffix == ".dmg":
            mount_point = Path(tempfile.mkdtemp(prefix="guard_dmg_", dir=str(work_dir)))
            res = run_cmd([
                "hdiutil", "attach", str(staged_target),
                "-nobrowse", "-readonly", "-mountpoint", str(mount_point)
            ])
            if res.returncode != 0:
                die(f"挂载 DMG 失败：{res.stderr}")
            apps = list(mount_point.glob("*.app"))
            pkgs = list(mount_point.glob("*.pkg"))
            if apps:
                # 将 .app 复制到 root 隔离区，再卸载 DMG，彻底防篡改
                copied_app = work_dir / apps[0].name
                shutil.copytree(apps[0], copied_app, symlinks=True)
                install_kind = "app"
                install_obj = copied_app
            elif pkgs:
                copied_pkg = work_dir / pkgs[0].name
                shutil.copy2(pkgs[0], copied_pkg)
                install_kind = "pkg"
                install_obj = copied_pkg
            else:
                die("DMG 中未发现 .app 或 .pkg 文件。")
            run_cmd(["hdiutil", "detach", str(mount_point), "-force"])
            mount_point = None
        elif suffix == ".app":
            install_kind = "app"
            install_obj = staged_target
        else:
            install_kind = "pkg"
            install_obj = staged_target

        if install_kind == "app":
            meta = inspect_app(install_obj)
            file_hash = sha256_app_bundle(install_obj)
        else:
            meta = inspect_pkg(install_obj)
            file_hash = sha256_file(install_obj)

        meta["sha256"] = file_hash
        meta["filename"] = src.name

        print(f"   • 软件名：{meta['app_name']}")
        print(f"   • Bundle：{meta['bundle_id']}")
        print(f"   • 签名者：{meta['signer']}")
        print(f"   • 公证状态：{'✅ 已通过苹果公证' if meta['notarized'] else '⚠️ 未公证'}")
        print(f"   • SHA-256：{file_hash[:16]}...")

        # 2. 发送至远端无对话 AI 审核
        print("\n🤖 [2/4] 正在提交远端无对话 AI 审核（无聊天通道）...")
        review = api_request(cfg, "/api/review", method="POST", payload=meta)

        ticket = None
        if review.get("allow") is True:
            print(f"✅ AI 审核通过：{review.get('reason')}")
            ticket = review.get("ticket")
        else:
            print(f"🚫 AI 审核未放行：{review.get('reason')}")
            if not review.get("can_ask_friend"):
                die("该软件被永久禁止安装。")

            ans = input("\n👉 如果是误判（如网课/学校软件），是否推送给朋友手机一键审批？[y/N]: ").strip().lower()
            if ans != "y":
                die("已取消安装。", code=0)

            note = input("📝 给朋友留一句简短说明（例如：学校网课软件学堂在线）: ").strip()[:100]
            req_resp = api_request(cfg, "/api/request-friend", method="POST", payload={
                **meta,
                "ai_reason": review.get("reason", ""),
                "user_note": note,
            })
            req_id = req_resp["reqId"]
            print(f"\n📨 {req_resp.get('message')}")
            print("⏳ 正在等待朋友在手机上点击【同意】（最长等待 15 分钟，按 Ctrl+C 取消）...")

            deadline = time.time() + 900
            while time.time() < deadline:
                time.sleep(3)
                st = api_request(cfg, f"/api/status/{req_id}", method="GET")
                status = st.get("status")
                if status == "approved":
                    print("✅ 朋友已在手机上点击同意！")
                    ticket = st.get("ticket")
                    break
                elif status == "denied":
                    die("朋友拒绝了本次安装申请。")
                elif status == "expired":
                    die("审批请求已过期。")
            if not ticket:
                die("等待审批超时。")

        # 3. 本地 root 验签（严格防伪造、防调包、防重放）
        print("\n🔐 [3/4] 正在本地校验加密授权票据...")
        verify_ticket(ticket, file_hash, meta["bundle_id"], cfg["ticket_hmac_secret"])
        print("   • HMAC-SHA256 签名校验通过！")

        # 4. 正式安装到 /Applications（归 root:wheel 所有，普通账号只读）
        print("\n🚀 [4/4] 正在以 root 权限安装软件...")
        if install_kind == "app":
            dest = Path("/Applications") / install_obj.name
            if dest.exists():
                print(f"   • 检测到旧版本 {dest.name}，正在替换为新版本...")
                shutil.rmtree(dest)
            shutil.copytree(install_obj, dest, symlinks=True)
            run_cmd(["chown", "-R", "root:wheel", str(dest)])
            run_cmd(["chmod", "-R", "go-w", str(dest)])
            print(f"\n🎉 安装成功！已安全安装至 {dest}")
        else:
            res = run_cmd(["installer", "-pkg", str(install_obj), "-target", "/"])
            if res.returncode != 0:
                die(f"PKG 安装失败：{res.stderr}")
            print(f"\n🎉 PKG 安装包安装成功：{install_obj.name}")

    finally:
        if mount_point and mount_point.exists():
            run_cmd(["hdiutil", "detach", str(mount_point), "-force"])
        shutil.rmtree(work_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
