#!/usr/bin/python3
"""Flight 安装执行器 —— 以 root 运行，是 youruser 唯一的提权入口。

只做三件事：验签、查重放、调 installer。
不提供 shell，不接受任意命令。
"""
import base64
import hashlib
import json
import os
import subprocess
import sys
import time

DB = "/var/db/flight"
PUB = os.path.join(DB, "pubkey.pem")
USED = os.path.join(DB, "used")
LOG = os.path.join(DB, "guard.log")
OPENSSL = "/usr/bin/openssl"
MAX_AGE = 1800  # 挑战有效期 30 分钟


def log(msg):
    os.makedirs(DB, exist_ok=True)
    with open(LOG, "a") as f:
        f.write("%s %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg))


def die(msg):
    log("REJECT: " + msg)
    print("拒绝：" + msg, file=sys.stderr)
    sys.exit(1)


def verify(challenge: str, sig_b64: str) -> bool:
    """用公钥验证 ECDSA-SHA256 签名。"""
    sig = base64.b64decode(sig_b64)
    tmp_sig = "/tmp/.flight_sig.%d" % os.getpid()
    tmp_msg = "/tmp/.flight_msg.%d" % os.getpid()
    try:
        with open(tmp_sig, "wb") as f:
            f.write(sig)
        with open(tmp_msg, "wb") as f:
            f.write(challenge.encode())
        r = subprocess.run(
            [OPENSSL, "dgst", "-sha256", "-verify", PUB, "-signature", tmp_sig, tmp_msg],
            capture_output=True,
        )
        return r.returncode == 0
    finally:
        for p in (tmp_sig, tmp_msg):
            try:
                os.unlink(p)
            except OSError:
                pass


def main():
    if os.geteuid() != 0:
        die("必须以 root 运行")
    if len(sys.argv) < 2:
        die("用法：flight-install <请求文件>")

    req_path = sys.argv[1]
    if not os.path.isfile(req_path):
        die("请求文件不存在")

    try:
        with open(req_path) as f:
            req = json.load(f)
        pkg = req["pkg"]
        challenge = req["challenge"]
        sig = req["sig"]
    except Exception as e:
        die("请求文件损坏：%s" % e)

    # 1. 目标必须是 .pkg
    if not pkg.lower().endswith(".pkg"):
        die("只能安装 .pkg 文件")
    if not os.path.isfile(pkg):
        die("安装包不存在")

    # 2. 挑战格式与绑定校验
    parts = challenge.split("|")
    if len(parts) != 4 or parts[0] != "FLIGHT1":
        die("挑战格式错误")

    pkg_hash = hashlib.sha256(open(pkg, "rb").read()).hexdigest()[:16]
    if parts[3] != pkg_hash:
        die("安装包与授权不匹配（签名绑定的不是这个文件）")

    # 3. 时效
    try:
        ts = int(parts[1])
    except ValueError:
        die("时间戳非法")
    age = time.time() - ts
    if age < -60:
        die("时间戳来自未来")
    if age > MAX_AGE:
        die("授权已过期（超过 %d 分钟）" % (MAX_AGE // 60))

    # 4. 一次性
    nonce = parts[2]
    used = set()
    if os.path.isfile(USED):
        used = set(open(USED).read().split())
    if nonce in used:
        die("这个请求码已经用过了")

    # 5. 验签
    if not os.path.isfile(PUB):
        die("公钥缺失")
    if not verify(challenge, sig):
        die("签名无效")

    # 6. 落账（先记账再执行，防止执行中断后重放）
    used.add(nonce)
    with open(USED, "w") as f:
        f.write("\n".join(sorted(used)))
    os.chmod(USED, 0o600)

    log("ALLOW: %s (hash %s, nonce %s)" % (pkg, pkg_hash, nonce))
    print("签名有效，开始安装：%s" % os.path.basename(pkg))

    # 7. 执行安装
    r = subprocess.run(["/usr/sbin/installer", "-pkg", pkg, "-target", "/"])
    if r.returncode != 0:
        log("INSTALL FAILED: %s rc=%d" % (pkg, r.returncode))
        print("安装失败，返回码 %d" % r.returncode, file=sys.stderr)
        sys.exit(r.returncode)

    log("INSTALL OK: %s" % pkg)

    # 8. 装完立刻做一次自愈检查（万一装坏了 Flight）
    wd = "/usr/local/bin/flight-watchdog"
    if os.path.isfile(wd):
        subprocess.run([wd, "--once"], capture_output=True)

    try:
        os.unlink(req_path)
    except OSError:
        pass

    print("完成。")


if __name__ == "__main__":
    main()
