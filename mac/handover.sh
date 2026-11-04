#!/bin/bash
# Flight 易主程序 —— 12 月朋友来时跑这个（需要管理员密码）
# 作用：把私钥从这台 Mac 上彻底抹掉，只留公钥。抹掉之后，你自己再也签不出授权码。

set -uo pipefail
LOG=/tmp/flight-handover.log
exec > >(tee -a "$LOG") 2>&1
echo "=== Flight 易主 $(date) ==="

D="$HOME/Desktop/Flight授权"
KEY_OK=1

echo "--- 1. 校验公私钥配对 ---"
if [ -f "$D/flight-priv.pem" ] && [ -f "$D/flight-pub.pem" ]; then
  A=$(openssl ec -in "$D/flight-priv.pem" -pubout 2>/dev/null | shasum -a 256 | awk '{print $1}')
  B=$(shasum -a 256 "$D/flight-pub.pem" | awk '{print $1}')
  if [ "$A" != "$B" ]; then echo "!! 公私钥不匹配，中止"; exit 1; fi
  echo "配对正常"
else
  echo "!! 找不到密钥文件"
  KEY_OK=0
fi

echo "--- 2. 确认私钥已安全转移到朋友设备 ---"
echo "（这一步需要你手动确认：朋友手机上已经打开签名器并成功签出过一次响应码）"
read -r -p "确认已转移？输入 YES 继续: " ans </dev/tty
if [ "$ans" != "YES" ]; then echo "已中止，什么都没删。"; exit 1; fi

echo "--- 3. 抹掉本机所有私钥痕迹 ---"
# 桌面目录
if [ "$KEY_OK" = "1" ]; then
  rm -f "$D/flight-priv.pem" && echo "已删 桌面的私钥"
fi
# 常见散落位置
for p in ~/Desktop ~/Downloads ~/Documents ~/bin /tmp; do
  find "$p" -maxdepth 2 -name "flight-priv*" -type f 2>/dev/null | while read -r f; do
    rm -f "$f" && echo "已删 $f"
  done
done
# 废纸篓
find ~/.Trash -maxdepth 2 -name "flight-priv*" 2>/dev/null | while read -r f; do
  rm -f "$f" && echo "已删废纸篓里的 $f"
done
# 打开过的历史记录
rm -f ~/Library/Preferences/com.apple.finder.plist.bak 2>/dev/null
# 清 shell 历史里的相关行
for h in ~/.zsh_history ~/.bash_history; do
  [ -f "$h" ] && sed -i '' '/flight-priv/d' "$h" 2>/dev/null && echo "已清 $(basename "$h")"
done

echo "--- 4. 校验结果 ---"
LEFT=$(find ~ -name "flight-priv*" -not -path "*/Library/*" 2>/dev/null | wc -l | tr -d ' ')
echo "本机残留私钥文件数: $LEFT"
echo "系统里的公钥: $(ls -l /var/db/flight/pubkey.pem 2>/dev/null || echo 未找到)"

echo "--- 5. 最后一步：让 youruser 无法自己加回管理员（可选）---"
echo "现在 youruser 已经不是管理员。guard 是唯一管理员。"
echo "guard 的密码请朋友当场改成一个只有他知道的值："
echo "   系统设置 → 用户与群组 → guard → 更改密码"

echo "=== DONE ==="
echo
echo "接下来把 FlightSigner.html 和私钥拷到朋友手机上，用浏览器打开，导入私钥，"
echo "签一个测试码确认能用。之后每次你要装 pkg，就用「Flight安装」发起请求。"
