> **🚀 v2 全新升级版已上线！** 查看 [`v2/README.md`](v2/README.md) 与 [`v2/朋友监督者操作SOP.md`](v2/朋友监督者操作SOP.md)：
> - **Android（三星免格式化无损升级）**：纯隐形 `Bulldog Guard v2`（`DISALLOW_APPS_CONTROL` 禁强停/防卸载 + `setAlwaysOnVpnPackage` 锁唯一 VPN 但保留正常下载 App + 精准全设置弹回 + AdGuard Family 无限量私密 DNS）+ 最小化阉割版 `FlClash`（自由换机场自动净化 + `速度`/`纯净` 2 标签极简分类）
> - **macOS**：免费 Cloudflare Workers 无对话 AI 软件审核器（大厂签名 0.1s 白名单秒过 + DeepSeek 审核 + 朋友手机一键点同意免传密码）+ 苹果原生磨砂玻璃拖拽器 `安装助手.app` + Google Santa + 原生 MDM 描述文件

---

# NoPorn

> A layered, self-healing content firewall for macOS + Android — built by someone who could not trust himself.

一个给自己造的、会自我修复的成人内容防线。**不追求"不可绕过"，只追求"绕过的代价高于当时的冲动"。**

本仓库只包含**机制**，不含任何代理/机场配置、不含任何密钥。

---

## 为什么会有这个东西

我不是安全研究员。我 20 岁，问题很具体：夜里想看点东西，意志力顶不住。

试过的路，按时间排列：

| 尝试 | 结果 | 为什么死 |
|---|---|---|
| 屏幕监控 / 图像识别 | 失败 | 只看得见"已经发生了"，拦不住 |
| 浏览器扩展屏蔽 | 失败 | 换个浏览器、无痕窗口，5 秒 |
| 关键词 / URL 黑名单 | 失败 | 域名天天换，追不上 |
| 定时断网（Cold Turkey 之类） | 失败 | 能卸载、能改系统时间、能安全模式 |
| 纯 DNS 过滤 | 失败 | 见下面"四个坑" |
| 问责类 App | 保留 | 有效，但那是"事后"，不是"当场" |

最后收敛到的判断只有一句：**在这台机器上，任何"我有权限关掉"的东西都不算防线。**

于是设计目标从"禁止"变成三件事：

1. **随手能关掉的，全部拿掉**（降权、去掉一切开关）
2. **关掉之后会被自动装回来**（自愈）
3. **想装新工具，必须经过我拿不到的那把钥匙**（签名授权）

---

## 架构：四层

```
L0   内容层   Flight.app（Clash Verge 源码改造）+ TUN + AdGuard Family DoH + 哨兵 IP 熔断
L0.5 自愈层   双守护互保（watchdog 30s / sentinel 45s）+ root 金库
L1   授权层   ECDSA P-256 签名 → 免密提权装 pkg
L2   管理员层  唯一管理员账号由他人持有
```

### L0 · 内容层

- 全部流量走 TUN，DNS 走 DoH（AdGuard Family），**不留明文 53 兜底**
- `hosts` 里把 DoH 域名钉死 IP，防止解析 DoH 域名本身时被污染
- `proxy-server-nameserver` 单独指定国内 DNS —— 否则 DoH 与节点解析互相等待，形成死锁
- 熔断规则（关键）：
  ```yaml
  - IP-CIDR,94.140.14.35/32,REJECT   # AdGuard 的哨兵 IP，被拦域名会解析到这里
  - IP-CIDR,0.0.0.0/32,REJECT
  - GEOSITE,category-porn,REJECT     # 只做兜底，防浏览器自带 DoH
  ```
- **关键词规则全部删除**。`DOMAIN-KEYWORD` 会误伤带相关字样的正常站点，且维护成本极高。

> 踩过的四个坑，任何一个都会让整套 DNS 方案"看起来在跑，实际全裸"：
> ① `nameserver` 里留了明文 UDP 53 兜底 → 被抢答；
> ② 只认 `0.0.0.0` 作为拦截标志 → AdGuard 实际返回 `94.140.14.35`；
> ③ 备用节点用了普通解析器（`94.140.15.15`）而不是 Family 版 → 过滤被绕过；
> ④ 缺 `proxy-server-nameserver` → DoH 与节点解析死锁，表现为"没网"。

### L0.5 · 自愈层

两个守护进程互相看着对方，任何一方被删、被改、被卸载，另一方在 30–45 秒内装回来。

- 原件放在 root 私有金库，守护只从金库取，不从用户目录取
- 功能探针：连续两次解析异常才触发重装，避免网络抖动导致误判
- 破坏性测试结果：删策略 14s / 篡改 8s / 删主守护 38s / 删副守护 30s / 杀内核 2s

### L1 · 授权层

装任何 `.pkg` 都必须拿到签名响应码。

```
Mac 生成：FLIGHT1|时间戳|nonce|pkg哈希前16位
手机签名：ECDSA P-256 + SHA-256
Mac 验签：公钥在 /var/db/flight/pubkey.pem，nonce 记入已用库，重放即拒
```

- 私钥在手机的安全芯片里（Android Keystore，硬件级，连 App 自己都导不出）
- 私钥**从生成起就没有离开过那台设备**，电脑上不存在副本
- 唯一的提权入口是 `/usr/local/bin/flight-install`，`sudoers` 里只放开这一条

### L2 · 管理员层

日常账户被移出 `admin` 组。唯一的管理员账号密码由另一个人掌握。

这一层不是防黑客，是防"将来的我"。

---

## 部署

### 前置

- macOS（Apple Silicon 验证过）
- 一个能用的代理（本仓库不含节点，需自备）
- Android 手机（用于保管签名私钥）
- JDK 17 + Android SDK 34（只有编译 APK 时需要）

### 步骤

```bash
# 1. 内容层：把 config/policy.yaml 放进 Flight.app 的配置目录
#    DNS 段、熔断规则按你实际使用的 DoH 服务调整

# 2. 自愈层
sudo cp mac/flight-watchdog mac/flight-sentinel /usr/local/bin/
sudo chmod 755 /usr/local/bin/flight-*
# 按 mac/deploy.sh 里的 plist 模板注册 LaunchDaemon

# 3. 授权层
sudo mkdir -p /var/db/flight
# 手机端 Key App 生成密钥 → 导出公钥 → 写入 /var/db/flight/pubkey.pem
sudo cp mac/install.py /usr/local/lib/flight/
sudo cp mac/flight-request /usr/local/bin/

# 4. 降权
sudo dseditgroup -o edit -d youruser -t user admin
```

安卓端源码在 `android/`，`build.sh` 一键编译。

---

## 已知边界

这部分我写得很直白，因为**把所有限制都藏起来的方案，最后会被人当成骗局。**

- **不防御物理接触**：任何能开机、且拥有解锁凭据的人，都可以在系统恢复环境里取得完整控制权。本方案的工作范围是"日常使用中的随手绕过"，不是"对抗有备而来的攻击者"。
- **不防御硬件层**：拆盘、取证、外接设备不在范围内。
- **依赖第三方 DNS**（AdGuard Family）。DNS 供应商的策略变化会直接影响效果。
- **不覆盖自建 DNS / 私有协议的应用**：如果某个 App 自己内置解析器并硬编码 IP，DNS 层拦不住。
- **不含任何节点、订阅、密钥**。作者不提供、不推荐、不分发。
- **只针对 macOS + Android**，其他平台未验证。

---

## 设计原则（如果你要抄，抄这几条）

1. **不要给自己留开关。** 任何"设置里能关"的拦截，等于没有。
2. **拦截要做在必经之路上。** DNS 比黑名单可靠，TUN 比 DNS 可靠。
3. **不要拦"排解"，只拦"内容"。** 把整块网络断掉，人只会想办法把整套东西卸了。
4. **让关掉它的成本 > 当时那点冲动。** 这是唯一真实的目标函数。
5. **自愈比加固更重要。** 一个会自动恢复的简单方案，胜过一个需要人维护的复杂方案。

---

## License

MIT。随便用，出事别找我。
