# 小爱同学 × Hermes Agent × Home Assistant

**把「小爱音箱」变成家里设备的总开关 —— 让跑在云端的 AI 真正动手操作你的米家 / 海尔设备。**

这是一份**写给动手的人**的完整教程：不讲概念，从装 Docker 开始，一步步到你对着音箱说"打开台灯"、台灯真的亮。
过程中踩过的坑、每个坑的**根因**和排障命令，都写在对应的章节里 —— 那些才是这份教程最值钱的部分。

---

## 一、先说清楚：这份教程能帮你到什么程度

不想让你照着做完才发现白忙，所以**先讲边界**。

| 环节 | 状态 |
|---|---|
| 云端和家里组成虚拟内网（Tailscale）| ✅ 已验证可用 |
| Home Assistant 接入米家 + 海尔，云端能读能控 | ✅ 已验证可用 |
| AI 能听懂"打开台灯""空调调到 26 度"并真的执行 | ✅ 已验证可用 |
| **对着小爱音箱说话** 触发 AI | ❌ **没打通，已放弃**（原因见下）|

**为什么会卡在最后一步**：云端 Hermes 的 API Server 有一处鉴权 **fail-closed** ——
它拿不到凭据时会判定"一律拒绝"，导致**任何 key 都返回 401**。
排查过程完整记录在 [04 篇 §4.9](docs/04-hermes-api-server.md)，那是一个很值得一看的排障案例。

**所以我给你的实际建议**：

- 你想要的是「**用 AI 控制家里的设备**」→ 教程的 ①~③ 步完全够用，用**飞书**当入口即可，稳定可靠
- 你想要的是「**对着音箱说话**」→ 本教程能让你走到最后一米，但**最后一米需要你自己修**（或等 Hermes 侧修复）
- 你只是**想看看这个坑怎么排** → 直接读 [04 篇 §4.9](docs/04-hermes-api-server.md) 和 [03 篇 §3.4](docs/03-hermes-ha.md)

---

## 二、这套方案长什么样

```
你（小爱音箱语音 / 飞书）
        │
        ▼
小爱音箱 ──(米家云/WiFi)──► MiGPT GUI（家里常开机 :36592）
        │                          │  OpenAI 兼容请求
        │                          ▼
        │              云端 Hermes Agent（24×7，公网可达）
        │                ├─ API Server :8642   ← ❌ 鉴权 401 未通
        │                └─ 原生 HA 工具        ← ✅ 可用
        │                          │
        │        Tailscale 虚拟内网（家里无公网 IP，主动连出去）
        │                          ▼
        └──── 语音播报 ◄── 家里 Home Assistant :8123   ← ✅ 可用
                              ├─ Xiaomi Miot Auto（米家设备）
                              └─ Haier（海尔空调 / 冰箱）
```

每个角色一句话：

- **Hermes Agent**（云端）：大脑。听懂你说什么，决定调哪个设备
- **Home Assistant**（家里）：手脚。真正持有设备控制权的中枢
- **Tailscale**：把云端和家里接进同一个虚拟内网，**不用公网 IP、不开任何端口**
- **MiGPT**（家里）：耳朵和嘴。盯着音箱、把语音转成请求、再把回答播出来

---

## 三、动手前，先花两分钟搞懂这件事

**这是整个方案的地基：为什么不能用端口映射？**

国内家庭宽带（尤其中国移动）**大多是 CGNAT**。你在"查我的 IP"网站上看到的那串地址，
其实是运营商机房的出口，**不是你家这条线**。所以：

> 去路由器后台看 **WAN 口 IP**：
> - 等于那个网站显示的地址 → 你有真公网 IP，端口映射可行
> - **不等于** → CGNAT，端口映射**必然打不通**，必须换方案

本教程的方案是：**让家里主动连出去**（Tailscale 组虚拟内网），
云端就能"看见"家里的设备，全程不暴露任何端口。这也是最安全的一种做法。

**别跳过这一步。** 很多人卡在这里半天，一直在查令牌、查防火墙，其实方向就错了。

三种方案对比见 [01 篇](docs/01-architecture.md)。

---

## 四、你需要准备什么

- 一台**常年开机的家庭电脑**（本教程是 Windows 11 笔记本），装 Home Assistant
  - ⚠️ 必须**不睡眠**（屏幕可以关）—— 睡了整套就断
- 一台**有公网 IP 的服务器**跑云端 Hermes（本教程是阿里云 Linux）
- 家里已接入米家的音箱（本教程是 L15A），以及你想控制的设备
- 一个 Tailscale 账号（免费额度够用）
- 大约半天时间 + 一点折腾的耐心

**不需要**：公网 IP、域名、备案、路由器端口映射。

---

## 五、五步走通

每一步都给你 **目标 → 做什么 → 怎么验证**。做完一步再进下一步。

### ① 家庭机：装 Docker，起 Home Assistant

**目标**：浏览器打开 `http://localhost:8123` 能看到 HA 初始化向导。

```powershell
# 见 scripts/01-check.ps1 / 02-install-docker.ps1 / 03-run-ha.ps1
docker run -d --name ha --restart unless-stopped `
  -p 8123:8123 -v "$env:USERPROFILE\ha-data:/config" `
  -e TZ=Asia/Shanghai ghcr.io/home-assistant/home-assistant:2026.9.3
```

**验证**：`http://localhost:8123` 出现向导 → 创建管理员账号。

**两个必踩的坑**（[02 篇](docs/02-home-assistant.md)）：

- `wsl --install` 报 **403** → 微软 CDN 被墙，改用 `winget install --id Microsoft.WSL --exact`（需管理员）
- 拉镜像极慢 → 配镜像加速器，或把 `ghcr.io` 换成 `ghcr.chenby.cn`（实测 **111.8 Mbps**）

> 📜 脚本：[`scripts/01-check.ps1`](scripts/01-check.ps1)（自检）、[`02-install-docker.ps1`](scripts/02-install-docker.ps1)、[`03-run-ha.ps1`](scripts/03-run-ha.ps1)

### ② 家庭机：把米家和海尔接进 HA

**目标**：HA 里能看见你的设备。

HA 界面 → 设置 → 设备与服务 → 添加集成：

- **Xiaomi Miot Auto**（[下载](https://github.com/al-one/hass-xiaomi-miot)）→ 服务器选**中国大陆(cn)** → 填**小米 ID**（不是手机号）
- **Haier**（[下载](https://github.com/banto6/haier)）→ 登录海尔智家账号
  - ⚠️ 海尔**没有官方集成**，别装成 `gvigroux/hon`（那是海外平台，国内登不上）

**验证**：HA 里出现你的实体。实测规模是 **169 个实体，其中可控 58 个**。

> ⚠️ 顺手记住三件事（[09 篇](docs/09-entity-reference.md) 有详解）：
> 温湿度计的原始温度是**华氏度**、冰箱**没有总开关**、插座设备的**子开关 ≠ 主开关**。

### ③ 两台机器：装 Tailscale，接进同一个虚拟内网

**目标**：两台机器互相 `ping` 得通。

```bash
# 云端（Linux）
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up          # 登录你的账号

tailscale ip -4            # 记下本机 100.x.y.z
tailscale status           # 应能看到家里那台
tailscale ping <家里那台IP> # 应见 pong
```

**验证**：`pong`。实测往返约 30ms 量级。

> 记下这个延迟 —— 以后如果觉得"慢"，**可以先排除网络**，去查 token 和工具集（[06 篇](docs/06-performance.md)）。
>
> 📜 脚本：家里那台用 [`scripts/05-install-tailscale.ps1`](scripts/05-install-tailscale.ps1)

### ④ 云端：让 Hermes 接上家里的 HA

**目标**：对着 Hermes 说"打开台灯"，台灯真的亮。

```bash
PIP_CONFIG_FILE=/dev/null hermes plugins install homeassistant
```

在 `~/.hermes/.env` 里写两行（用**家里的 Tailscale IP**）：

```bash
HASS_TOKEN=<你在 HA 里生成的长期令牌>
HASS_URL=http://<HOME_TS_IP>:8123
```

```bash
hermes gateway restart     # ⚠️ 必须在网关进程外的 shell 执行
```

**验证**：`hermes tools list` 应看到 `homeassistant` 工具集，然后说"打开台灯"。

> 🔥 **这一步有个大坑，先看再动手**：[03 篇 §3.4](docs/03-hermes-ha.md)。
> 装插件会报 uv 的 `has no publish time` 错误，而**报错里的包全是 Hermes 自己的核心依赖，跟插件无关** ——
> 换任何插件都会踩。根因是**国内 pip 镜像没有 `upload-time` 时间戳**。
> 修法就一行：命令前加 `PIP_CONFIG_FILE=/dev/null`。

### ⑤ 想让音箱也能说话 → 开放 API Server（⚠️ 这一步没打通）

**目标**：让家庭机上的 MiGPT 把语音转发给云端 Hermes。

配置本身很简单（[04 篇](docs/04-hermes-api-server.md)），但**这一步会撞上未解决的鉴权 401**：

```bash
# ~/.hermes/.env
API_SERVER_ENABLED=true
API_SERVER_HOST=<HERMES_TS_IP>   # 只监听 Tailscale 网卡，不碰公网
API_SERVER_PORT=8642
API_SERVER_KEY=<openssl rand -hex 32>
```

**症状**：服务启动正常（日志显示 `API server listening on …`），
`/health` 返回 200，但**所有需要鉴权的端点都 401 —— 而且用任何 key 都一样**。

**特征口诀**：拿 3~4 个差异极大的 key（真 key / 全零 / 截断 / 大写）打一次，
**如果返回完全一致，问题就一定不在 key 值上**，而是权限链表某一环拿到了空值后 fail-closed。

完整根因、源码定位、候选修法 → [04 篇 §4.9](docs/04-hermes-api-server.md)。
MiGPT 侧的配置与坑（数字 did、passToken、崩溃补丁）→ [05 篇](docs/05-migpt-xiaoai.md)。

---

## 六、四条最值钱的经验

如果你只有五分钟，读这四条：

**1. 装插件报 uv 错，别去查插件，去查 pip 镜像。**
报错里的包全是 Hermes 核心依赖。国内 pip 镜像（阿里云 / 清华等）没有 `upload-time` 时间戳，
被 uv 的"供应链新鲜度闸门"判成"太新"→ 无解硬失败。加 `PIP_CONFIG_FILE=/dev/null` 即可。
→ [03 篇 §3.4](docs/03-hermes-ha.md)

**2. "所有 key 都 401"不是 key 的问题，是权限链上的空值 fail-closed。**
判断方法就是上面那个探针实验。→ [04 篇 §4.9](docs/04-hermes-api-server.md)

**3. 小爱音箱要填数字 did，不是米家显示的设备名。**
填设备名会报"找不到设备"。异地登录风控要用 **passToken** 绕。→ [05 篇](docs/05-migpt-xiaoai.md)

**4. 觉得慢，先量 token 再查网络。**
Tailscale 往返才 30ms 级；真正的膨胀源是 **API Server 默认挂了 38~42 个工具**，
基础提示词就 1.4 万 token，查一次设备冲到 6~7 万。砍到 7 个工具即可。
**并且别给 API Server 开 `terminal`**（它等同把服务器 shell 权限挂到网上）。→ [06 篇](docs/06-performance.md)

---

## 七、遇到问题怎么办

**直接翻 [08 踩坑总表](docs/08-troubleshooting.md)** —— 按「症状 → 原因 → 解法」编排，扫一眼就能定位。

配设备时对照 [09 设备实体参考](docs/09-entity-reference.md)（实体 ID 规律 + 三个必记陷阱）。

---

## 八、深入学习（文档索引）

教程按主题拆成 10 篇，每篇都自包含，可以跳读：

| 文档 | 讲什么 |
|---|---|
| [00 资源与下载](docs/00-resources.md) | 要装的软件、官方链接、国内镜像加速实测、本仓库下载方式 |
| [01 架构与网络选型](docs/01-architecture.md) | 拓扑、Tailscale / frp / 端口映射怎么选、CGNAT 判断 |
| [02 部署 Home Assistant](docs/02-home-assistant.md) | WSL2 403 绕过、Docker 镜像源测速、米家 + 海尔接入 |
| [03 云端 Hermes 接入 HA](docs/03-hermes-ha.md) | 插件、`.env`、`ha_*` 工具、**uv 报错根因链**、备份目录规律 |
| [04 开放 API Server](docs/04-hermes-api-server.md) | 端点表、自测、**§4.9 鉴权 401 完整排障** |
| [05 MiGPT 语音入口](docs/05-migpt-xiaoai.md) | 镜像/端口纠错、数字 did、passToken、崩溃补丁 |
| [06 提速：精简工具集](docs/06-performance.md) | token/耗时实测、38→7 个工具、Tool Search 方案 |
| [07 会话记忆与压缩](docs/07-session-memory.md) | 两种"记忆"的区别、按天会话、`compression` 参数 |
| [08 踩坑总表](docs/08-troubleshooting.md) | 症状 → 原因 → 解法（汇总全部坑）|
| [09 设备实体参考](docs/09-entity-reference.md) | 米家/海尔实体 ID 规律、三个必记陷阱 |
| [scripts/ 脚本说明](scripts/README.md) | Windows 侧部署与守护脚本（PowerShell + Node）|

---

## 九、下载

| 用途 | 链接 |
|---|---|
| 整包 ZIP | `https://github.com/JackMere/hermes-migpt-home-assistant/archive/refs/heads/main.zip` |
| 单文件全本（推荐喂给 AI）| [`tutorial-full.md`](tutorial-full.md) |
| 软件清单与下载链接 | [00 资源与下载](docs/00-resources.md) |
| Windows 部署脚本 | [`scripts/`](scripts/) |

### 让 AI 帮你读

- **通读**：把 [`tutorial-full.md`](tutorial-full.md) 整个喂给模型
- **按需**：先给 [`llms.txt`](llms.txt)（索引），再让它取需要的单篇
- **引用**：用**纯文本 / Markdown**，别截图 —— 表格和代码块要保留原样

> 这套文档刻意用「语义化标题 + 症状/原因/解法三段式」写，就是为了让模型能准确定位问题。

---

## 十、关于这份教程

**脱敏**：所有真实值都换成了占位符，请自行替换 ——

`<HERMES_PUBLIC_IP>` `<HERMES_TS_IP>` `<HOME_TS_IP>` `<TAILNET>` `<HA_TOKEN>`
`<API_SERVER_KEY>` `<小米ID>` `<数字did>` `<用户名>` `<家庭内网IP>` `<网关IP>`
`<宽带出口IP>` `<hash>`（实体 ID 里的 4 位设备哈希）`<唤醒词>`

**免责**：`scripts/` 里的脚本只在原始环境（Windows 11 + PowerShell 5.1 + Docker Desktop）验证过，
换机器可能需要微调；**请先读一遍再执行**。其中 MiGPT 相关脚本属于"未打通并已放弃"的路线。

**版本**：Hermes Agent `0.21.5` · Home Assistant `2026.9.3` · Docker `29.8.2` · MiGPT GUI `lmk123/migpt-server`

Hermes 迭代较快，文档里的**行号 / 内部函数名**会变；**行为描述**比行号可靠。

**安全**（重要，别跳过）：

- **`API_SERVER_KEY` 等同服务器 shell 权限** —— 官方文档原文：*full access to hermes-agent's toolset, **including terminal commands***
- **`HASS_TOKEN` 等同 HA 完整控制权**
- 云安全组**千万不要**放行 8642 到公网；HA 的 8123 也不要暴露公网，只走 Tailscale
- 精简 API Server 工具集时**不要加 `terminal`**
- 所有密钥用强随机值：`openssl rand -hex 32`；统一放 `~/.hermes/.env`（权限 `600`）

**许可**：MIT
