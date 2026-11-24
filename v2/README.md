# 🛡️ 个人防破防系统——全套施工总图纸与物料清单

本项目目录：`/Users/YOUR_STANDARD_USER/.gemini/antigravity/scratch/guard-system`

---

## 一、先理清 3 个核心架构决策（已全部打通，零重合）

1. **三星手机端（高方便度 + 强锁死）**
   - **能照常下载普通 App**，但通过 Device Owner 的 **`setAlwaysOnVpnPackage` + `DISALLOW_CONFIG_VPN`** 锁死全手机唯一 VPN 槽位 → 哪怕下 100 个别的 VPN 也全部启动不了。
   - 唯一允许的翻墙客户端 = **阉割锁定版 FlClash**：保留手机 4G/5G 必需的 Android `VpnService`（虚拟网卡），但**锁死本地 AdGuard Family DNS（免费无限流量）+ 顶层 30 万+ NSFW `REJECT` + 夸克/微信国内直连**；阉割“添加/编辑配置”和“切全局”，仅保留“切换节点”与“刷新节点”。
   - **Bulldog 双保险**：Device Owner 开 `DISALLOW_APPS_CONTROL`（彻底灰掉“强行停止/清数据/卸载”） + 自写**精准无障碍守护 App**（只当你点进 Bulldog / 守护 App / FlClash 详情页时 50ms 弹回桌面，**其他 App 的无障碍照常可管**）。
2. **Mac 电脑端（保留 `YOUR_STANDARD_USER` 普通账号 + `guard` 管理员，彻底解决频繁输密码）**
   - **远端不可对话 AI 审核器（Cloudflare Workers，免费零 VPS 费用）**：无聊天框，零忽悠可能。硬规则先拦截所有带 `NetworkExtension`/VPN 权限及代理内核的软件，再交由 AI 严格 JSON 审核；正常软件 **5 秒自动签发一次性 HMAC 加密票据**，本地 `safe-install` 验签后直接以 `root` 装进 `/Applications`，**全程不弹 `guard` 密码框**！
   - **朋友手机一键审批（解决 AI 误判，如“学堂在线”）**：本地回车一键推送给宜昌朋友手机 → 朋友点开网页看到软件名/签名/哈希，点【✅ 同意安装】→ 签发仅限该文件 SHA-256 的 5 分钟一次性票据 → 自动安装！**宜昌朋友全程不需要发任何密码，也不需要知道密码！**
   - **浏览器与 DNS 锁**：安装 `browser-safesearch-lock.mobileconfig` 锁死 Chrome/Edge 安全搜索、禁隐身、禁改 DoH、直连强制走 AdGuard Family。
3. **关于“能否用管理员账号 + MDM 替代降级账号”的定论**
   - 个人设备没有苹果企业级 ABM 硬件监管，**一旦日常账号是管理员，任何本地软件和配置都能被 `sudo` 3 秒拆掉**。
   - 因此**保留 `YOUR_STANDARD_USER` 普通账号 + AI 审核自动安装 + 朋友一键点同意**，是兼顾“铁桶强制力”与“日常无感方便度”的唯一最优解！

---

## 二、已为你准备好的本地物料文件（全部就绪）

| 文件 | 用途 |
| :--- | :--- |
| `clash-config/locked-adguard-clash.yaml` | 锁死版 FlClash/Mihomo 配置（AdGuard Family 免费无限量 + 30 万+ 成人 `REJECT` + 修复夸克浏览器断网 + 仅节点可更新） |
| `mac-gatekeeper/worker/worker.js` & `wrangler.toml` | 免费 Cloudflare Worker 后端（硬规则拦截 + 无对话 AI 审核 + 朋友一键审批网页 + 微信/Bark 推送 + HMAC 票据签发） |
| `mac-gatekeeper/local/safe-install.py` & `setup-mac-gatekeeper.sh` | Mac 本地 `root` 安装助手（防调包隔离区 + 签名/VPN 权限扫描 + 票据验签 + 自动装进 `/Applications`） |
| `mac-gatekeeper/profiles/browser-safesearch-lock.mobileconfig` | Mac 原生 MDM 描述文件（锁 AdGuard Family DoH + 锁 Chrome/Edge 安全搜索与禁改 DoH） |
| `android-samsung/adb-lock-samsung.sh` | 三星手机连线后的一键只读诊断 + Device Owner 激活与策略核对指南 |
| `android-samsung/accessibility-guard/GuardAccessibilityService.kt` | 精准无障碍守护核心源码（仅在进入 Bulldog/守护/FlClash 开关页时弹回桌面，放行其他 App） |
| `android-samsung/flclash-lock-guide.md` | 阉割锁定版 FlClash 安卓编译改造清单 |

---

## 三、施工前你需要提前下载的 App & 核对的信息清单

### A. 提前准备的账号/信息（打勾核对）
- [ ] **机场订阅链接 1 条**：用于填入 `locked-adguard-clash.yaml` 的 `proxy-providers`（施工时只放你自己的远端托管链接，不要公开）。
- [ ] **免费 Cloudflare 账号 1 个**（https://dash.cloudflare.com ）：用于免费部署 AI 审核器 + 朋友一键审批网页（**上线测试通过后，账号密码交给宜昌朋友改掉**）。
- [ ] **极便宜的大模型 API Key 1 个**（推荐 DeepSeek / 硅基流动 / Gemini Flash，充 5 块钱能审一万次软件）。
- [ ] **给宜昌朋友的手机推送通道（三选一，免费）**：
  - 朋友用 iPhone → 装 **Bark**（App Store 免费，最稳最快，复制推送 URL 即可）；
  - 朋友用安卓/微信 → 注册 **Server酱** 或 **PushPlus**（微信直接收审批卡片）。
- [ ] **确认 Mac 管理员账号 `guard` 当前密码可用**（施工阶段需要用 `guard` 部署脚本，全部测通稳定后，再由宜昌朋友通过远程盲敲改掉 `guard` 密码）。

### B. 手机端提前下载的 App（三星手机）
- [ ] **Bulldog Blocker**（你原本喜欢的 AI 识图拦截器，保留继续用）
- [ ] **Device Owner 管理器（二选一，建议施工时一起定）**：
  - **OwnDroid**（GitHub 开源免费：`https://github.com/BinTianqi/OwnDroid/releases`）—— 策略最全，支持一键配 `Always-On VPN` + `DISALLOW_CONFIG_VPN` + `DISALLOW_APPS_CONTROL` + `Private DNS`；
  - **Andoff**（`https://andoff.one`）—— 自带时间延迟锁 + “一键锁 1 小时防冲动”（如果既要策略全又要延迟，优先 OwnDroid 锁死 + 朋友保管解锁密码/或 Andoff 主控）。
- [ ] **数据线 1 根**（能传数据的 USB-C 线，连接三星手机与 Mac）

### C. Mac 电脑端施工依赖（连上电脑开满权限后我来帮你检查/安装）
- [ ] `adb`（Android Platform Tools，连手机用）
- [ ] `node` / `npx wrangler`（部署免费 Cloudflare Worker 用）
- [ ] **Google Santa**（开源免费：`https://github.com/northpolesec/santa/releases`，用于最终阶段封死 `YOUR_STANDARD_USER` 运行 `/Applications` 以外新下载的陌生 VPN/Clash）
- [ ] 若本机编译阉割版 FlClash APK & 精准无障碍守护 APK：需要 Flutter SDK + Android SDK（或者直接用 GitHub Actions 免费云端自动编译出 APK，**不占你 Mac 一点硬盘！强烈推荐云端编译！**）

---

## 四、正式施工顺序（等你准备好后，严格按这 4 步推进，确保绝不误锁变砖）

1. **阶段 1：云端部署与网络测试（约 15 分钟）**
   - 部署 `worker.js` 到 Cloudflare Workers，配置 API Key 和朋友推送；
   - 托管 `locked-adguard-clash.yaml`，在手机/电脑先试跑：**验证夸克浏览器、微信、Google、YouTube 全流畅，同时色情站与 Google 图片色情搜索 100% 拦截**。
2. **阶段 2：Mac 电脑端实装与试运行（约 20 分钟）**
   - 用 `guard` 跑 `setup-mac-gatekeeper.sh`，双击安装 `browser-safesearch-lock.mobileconfig`；
   - 实测用 `YOUR_STANDARD_USER` 运行 `safe-install` 安装一个正常软件（测 AI 5 秒过审）+ 模拟安装“学堂在线”或未公证软件（测宜昌朋友手机一键点同意）+ 模拟安装一个 Clash（测硬规则秒杀）；
   - 安装 Google Santa 限制运行 `/Applications` 外程序。
3. **阶段 3：三星手机端实装与试运行（约 30 分钟）**
   - 云端/本地编译出你的**专属阉割锁定版 FlClash APK** 和 **精准无障碍守护 APK**；
   - 手机连 Mac 跑 `adb-lock-samsung.sh` 检查旧 Device Owner 状态 → 激活新 Device Owner → 开启 5 条核心策略（**暂不锁 USB 调试，留 3 天观察期**）；
   - 实测：夸克流畅、4G/5G 翻墙流畅、装其他 VPN 无法启动、装普通 App 正常、Bulldog 点不动强行停止、进 Bulldog 无障碍秒弹回桌面、进其他 App 无障碍照常可管！
4. **阶段 4：终极封口（稳定试运行 3 天零故障后执行）**
   - 三星 Device Owner 锁死 USB 调试；
   - 宜昌朋友接管 Cloudflare 账号密码 + 远程盲敲修改 Mac `guard` 密码。
   - **完工毕业！**
