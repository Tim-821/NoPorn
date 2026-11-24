# 手机端 FlClash 阉割锁定改造清单（施工阶段直接编译）

## 1. 为什么要保留 Android VpnService（系统虚拟网卡），但锁死远端 DNS？
- 在安卓手机上，出门用 4G/5G 流量时，只有通过系统 `VpnService`（FlClash 里的 VPN 通道）才能接管所有 App 流量，否则 4G/5G 根本翻不了墙。
- 决定 DNS 是“本地 AdGuard 解析”还是“机场 VPS 远端解析”的，是配置文件里的 `dns:` 和顶层 `rules:`，而不是开关 `VpnService`！
- 只要使用我们写好的 `clash-config/locked-adguard-clash.yaml`：
  - 国内流量（夸克/微信/支付宝）→ 国内 DNS + 直连（彻底修复上次夸克断网）；
  - 海外流量 → 本地 AdGuard Family DoH + 顶层 30 万+ NSFW `REJECT`（在流量发往机场 VPS 之前就在手机本地直接拦死！）。

## 2. FlClash 源码精准阉割点（基于开源 `chen08209/FlClash`）
施工时我会直接把 FlClash 源码拉到本机，改完以下 5 处后用**全新包名**（如 `com.guard.flclash.locked`）编译出你的专属 APK：

1. **锁定唯一远端配置地址**：
   - 将你的 `locked-adguard-clash.yaml` 托管到你的 GitHub 私有仓库（或 Cloudflare Worker 受保护链接，写权限归朋友）。
   - App 启动时自动拉取并强制应用该配置，支持后台定时更新机场节点（通过 `proxy-providers`）。
2. **阉割配置修改入口**：
   - 隐藏/禁用【添加配置（URL/文件/二维码）】、【编辑配置】、【删除配置】、【覆写 DNS/规则】全部 UI 按钮与路由。
3. **阉割模式绕过入口**：
   - 锁死运行模式为 `Rule（规则模式）`，隐藏 `Global（全局）` 和 `Direct（直连）` 切换按钮（防止切到全局跳过顶层拦截规则）。
4. **保留日常必需的自由度**：
   - ✅ 保留【切换代理节点】（香港/日本/新加坡节点慢了可以随时切，完全不影响方便度）；
   - ✅ 保留【更新订阅节点】（只刷新 `proxy-providers` 节点列表，绝不覆盖锁死的 DNS 和成人规则）。
5. **配合三星 Device Owner 封顶**：
   - 在 OwnDroid / Andoff 里将该专属 APK 设为 **Always-On VPN** + 开启 **`DISALLOW_CONFIG_VPN`**。
   - 结果：全手机照常随便下载正常 App，但其他所有 VPN App 全部无法启动！
