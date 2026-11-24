#!/usr/bin/env python3
"""
一键给 Cloudflare Worker 绑定宜昌朋友的手机推送渠道（Bark / Server酱 / PushPlus）
用法：
  python3 set-friend-push.py --cf-token <CF_TOKEN> --bark "https://api.day.app/你的Key/"
  python3 set-friend-push.py --cf-token <CF_TOKEN> --serverchan "SCTxxxx"
  python3 set-friend-push.py --cf-token <CF_TOKEN> --pushplus "xxxx"
"""
import argparse, json, urllib.request

ACC = "REPLACE_WITH_YOUR_CLOUDFLARE_ACCOUNT_ID"
WORKER = "guard-gatekeeper"

def put_secret(token, name, text):
    url = f"https://api.cloudflare.com/client/v4/accounts/{ACC}/workers/scripts/{WORKER}/secrets"
    req = urllib.request.Request(
        url,
        data=json.dumps({"name": name, "text": text, "type": "secret_text"}).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="PUT",
    )
    with urllib.request.urlopen(req, timeout=20) as r:
        print(name, "->", r.read().decode())

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--cf-token", required=True)
    p.add_argument("--bark")
    p.add_argument("--serverchan")
    p.add_argument("--pushplus")
    a = p.parse_args()
    if a.bark:
        put_secret(a.cf_token, "BARK_PUSH_URL", a.bark)
    if a.serverchan:
        put_secret(a.cf_token, "SERVERCHAN_SENDKEY", a.serverchan)
    if a.pushplus:
        put_secret(a.cf_token, "PUSHPLUS_TOKEN", a.pushplus)

if __name__ == "__main__":
    main()
