# 小爱同学 × Hermes Agent × Home Assistant —— 完整教程（单文件版）

> 本文件由 `scripts/build-full.sh` **自动生成，请勿手工编辑**。
> 要改内容请改 `README.md` 或 `docs/*.md`，再重新执行该脚本。
>
> 分篇版本（链接可互相跳转）见仓库 [README.md](README.md) 与 [docs/](docs/) 目录。
> 本单文件版里的 `相对链接` 不会跳转，请按标题查找对应章节。

## 目录

1. 项目总览与当前状态（README）
1. 00 · 资源与下载链接（`docs/00-resources.md`）
1. 01 · 架构与网络选型（`docs/01-architecture.md`）
1. 02 · 部署 Home Assistant（家庭机）（`docs/02-home-assistant.md`）
1. 03 · 云端 Hermes 接入 Home Assistant（`docs/03-hermes-ha.md`）
1. 04 · 开放 OpenAI 兼容 API Server（供 MiGPT 调用）（`docs/04-hermes-api-server.md`）
1. 05 · MiGPT 语音入口（小爱音箱）（`docs/05-migpt-xiaoai.md`）
1. 06 · 提速：精简 API Server 的工具集（`docs/06-performance.md`）
1. 07 · 会话记忆（按天）与上下文压缩（`docs/07-session-memory.md`）
1. 08 · 踩坑总表（`docs/08-troubleshooting.md`）
1. 09 · 设备实体参考（米家 / 海尔）（`docs/09-entity-reference.md`）
1. 脚本说明（`scripts/README.md`）

---

# 项目总览与当前状态

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


---

# 00 · 资源与下载链接

> 所有需要装的软件、要用的镜像、本教程相关链接，集中在这里。**照着装就行。**

## 0.1 本教程自身的下载

| 用途 | 链接 |
|---|---|
| **整包下载（ZIP）** | `https://github.com/JackMere/hermes-migpt-home-assistant/archive/refs/heads/main.zip` |
| 单篇在线阅读 | `https://github.com/JackMere/hermes-migpt-home-assistant/tree/main/docs` |
| **单文件全本（AI / 离线阅读推荐）** | [`tutorial-full.md`](../tutorial-full.md) |
| AI 索引入口 | [`llms.txt`](../llms.txt) |

> **给 AI 用的建议**：直接把 `tutorial-full.md` 作为单次输入喂给模型；或让模型先读 `llms.txt` 再按需取单篇。

## 0.2 要装的软件

| 组件 | 作用 | 官方下载 / 源码 |
|---|---|---|
| **Hermes Agent** | 云端「大脑」，负责理解指令并调用 HA | 源码 <https://github.com/NousResearch/hermes-agent>　文档 <https://hermes-agent.nousresearch.com/docs> |
| **Tailscale** | 把云端和家庭机组进同一虚拟内网（**关键**，替代端口映射）| <https://tailscale.com/download>　Linux 一键：`curl -fsSL https://tailscale.com/install.sh \| sh` |
| **Docker Desktop**（Windows）| 家庭机跑 HA / MiGPT 的容器运行时 | <https://www.docker.com/products/docker-desktop/> |
| **WSL2** | Docker Desktop 的依赖 | `winget install --id Microsoft.WSL --exact`（见 [02 篇](02-home-assistant.md) 为什么不用 `wsl --install`）|
| **Home Assistant** | 家庭设备中枢 | <https://www.home-assistant.io/>　镜像 `ghcr.io/home-assistant/home-assistant` |
| **Xiaomi Miot Auto** | 把米家设备接进 HA | <https://github.com/al-one/hass-xiaomi-miot> |
| **Haier（海尔）** | 把海尔空调 / 冰箱接进 HA | <https://github.com/banto6/haier> |
| **MiGPT** | 让小爱音箱接入 AI | <https://github.com/idootop/mi-gpt> |
| **MiGPT GUI** | MiGPT 的图形界面（**本教程用的就是这个**）| <https://migptgui.com/>　镜像 `lmk123/migpt-server` |

### Hermes 相关文档（最该先读的两篇）

- **API Server（OpenAI 兼容接口）**：<https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server>
- **Home Assistant 插件**：<https://hermes-agent.nousresearch.com/docs/user-guide/messaging/homeassistant>

## 0.3 容器镜像与国内加速

### 要拉的两个镜像

```bash
# Home Assistant（家庭机）
ghcr.io/home-assistant/home-assistant:2026.9.3

# MiGPT GUI（家庭机）
lmk123/migpt-server
```

### 国内拉取加速（实测，见 [02 篇 §2.2](02-home-assistant.md)）

| 源 | 实测速度 | 用在哪 |
|---|---|---|
| **ghcr.chenby.cn** | **111.8 Mbps** | ghcr 镜像（HA）**首选** |
| **docker.1ms.run** | 43.9 Mbps | Docker Hub 镜像（MiGPT）首选 |
| **docker.m.daocloud.io** | 38.6 Mbps | 备选 |
| docker.1panel.live / dockerproxy.net | — | 备选 |
| ghcr.io 直连 | 1.4 Mbps | ❌ 慢，别用 |

用法很简单 —— **把镜像名前缀换掉**：

```powershell
docker pull ghcr.chenby.cn/home-assistant/home-assistant:2026.9.3
docker pull docker.1ms.run/lmk123/migpt-server:latest
```

### GitHub 下载加速（下集成 ZIP 用）

```
https://gh-proxy.com/<原 GitHub 链接>
```

例：

```
https://gh-proxy.com/https://github.com/al-one/hass-xiaomi-miot/archive/refs/heads/master.zip
```

## 0.4 可能用到的网络与工具

| 工具 | 用途 | 链接 |
|---|---|---|
| frp | Tailscale 的替代方案（云端当 `frps`，家庭机当 `frpc`）| <https://github.com/fatedier/frp> |
| Nginx Proxy Manager | 给 HA 加 HTTPS 反代（本教程未用）| <https://nginxproxymanager.com/> |
| llms.txt 约定 | 让 AI 更好读你的站点 / 仓库 | <https://llmstxt.org/> |

## 0.5 常见问题的官方出处

| 问题 | 出处 |
|---|---|
| 小爱音箱登录风控、设备找不到 | MiGPT issue #326 <https://github.com/idootop/mi-gpt/issues/326> |
| 海尔集成选哪个 | 用 `banto6/haier`（国区）；**别用** `gvigroux/hon`（海外 hOn 平台）|
| HA 长期令牌怎么生成 | HA 界面：用户头像 → 安全 → 长期访问令牌 |
| Tailscale 怎么判断是否直连 | `tailscale ping <对端>` 看是否有 `via DERP` 字样 |

## 0.6 本教程涉及但**未随包提供**的东西

以下内容在本教程里出现，但属于**你自己环境里生成**的，不要期待能下载：

| 项 | 说明 |
|---|---|
| `HA_TOKEN` | 你在自己 HA 里生成，只显示一次 |
| `API_SERVER_KEY` | 你自己用 `openssl rand -hex 32` 生成 |
| 小米 ID / 音箱数字 did | 你自己的小米账号信息 |
| 家庭机的 `deploy/scripts/*.ps1` | 本教程把命令都写在正文里，可直接复制；如需脚本化请自行封装 |

> ⚠️ **反向提醒**：任何教程、issue、聊天记录里如果出现**别人真实的** token / key / ID，都别照抄使用 —— 那些要么已失效，要么属于隐私泄露。


---

# 01 · 架构与网络选型

## 最终架构

```
你：小爱音箱语音「<唤醒词>，打开台灯」
        │
        ▼
小爱音箱 ──(米家云/WiFi)──► MiGPT GUI（家庭机 :36592）
        │                              │  OpenAI 兼容请求
        │                              ▼
        │                 云端 Hermes Agent（24×7）
        │                    (API server :8642)
        │                              │  调用 HA 工具
        │                              ▼
        │                家庭机 Home Assistant :8123
        │                   ├─ Xiaomi Miot（米家设备）
        │                   └─ Haier（海尔空调/冰箱）
        │                              │
        └──────── TTS 播报 ◄───────────┘
                    （全链路走 Tailscale 虚拟内网，无公网暴露）
```

**关键点**：家庭机没有公网 IP，家庭机与云端通过 **Tailscale** 组虚拟内网（`100.64.x.x`），
所以云端能"看见"家里的 HA，家庭端也能访问云端 Hermes。

## 为什么不能用端口映射

国内家庭宽带（尤其中国移动）**大多是 CGNAT**：你在 `ipinfo` 之类网站查到的"公网 IP"其实是运营商出口地址，不是你这条线的地址。

**判断方法**：去路由器后台看 **WAN 口 IP**：

- WAN 口 IP **等于**该网站显示的地址 → 有真公网 IP，端口映射可行
- **不等于** → CGNAT，端口映射**必然不通**，必须用 Tailscale / frp

本记录的实际环境就是第二种（出口 IP 属运营商共享段），所以从一开始就放弃了端口映射。

## 三种打通方式对比

| 方案 | 难度 | 是否暴露公网 | 说明 |
|---|---|---|---|
| **Tailscale / ZeroTier**（推荐）| 低 | 否，最安全 | 两台各装一个、登录同一账号即可，无需固定公网 IP，不开放任何端口 |
| **frp** | 中 | 否（只暴露给云端）| 云端已有公网 IP，天然适合当 `frps`；适合想要「只有云端能访问」的隔离效果 |
| 路由器端口映射 + DDNS | 低 | **是**（HA 直接暴露公网）| 多数家庭宽带没公网 IP；即便有也要自己加固（HTTPS + 强密码 + allowlist）|

推荐 **Tailscale**：免费额度（10 台设备）够用，NAT 穿透自动协商。

### frp 方案要点

- 云端跑 `frps`，开放 `7000`（bind）端口
- 家庭机跑 `frpc`，把本地 `8123` 反代到云端某个端口
- 云端访问 `127.0.0.1:<映射端口>` 即等价于访问家里的 HA

## Tailscale 安装

```bash
# Linux（云端）
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
# 浏览器会给出登录链接，登录你的账号（两端必须是同一个）

tailscale ip -4          # 记下这台机器的 100.x.y.z
tailscale status         # 应能看到另一台机器
tailscale ping <对端 IP>  # 应见 pong
```

```powershell
# Windows（家庭机）
winget install Tailscale.Tailscale
tailscale up
```

> **国内提示**：`tailscale up` 的登录流程可能需要能访问 Tailscale 的登录页；先确保网络可用再重试。

## 实测延迟参考

家庭机 ↔ 云端 Tailscale 往返约 **30–34ms**（首连可能走 DERP 中继到几百 ms，之后自动升级为直连）。

这个量级说明：**后续如果响应慢，瓶颈一定不在网络上**，去查 token / 工具集（见 [06 提速](06-performance.md)）。

## 安全边界

- 家庭机的 HA（8123）**只走 Tailscale**，不对公网开放 —— 当前即如此
- 云端的 API Server（8642）**只绑 Tailscale 网卡**，云安全组不放行
- HA 与 Hermes 的令牌都只存本机 `.env`，权限 `600`


---

# 02 · 部署 Home Assistant（家庭机）

> 家庭机是一台常开的 Windows 11 笔记本（i7 / 16G 级），7×24 不睡眠。
> 这一篇记录装 Docker、绕 WSL 的坑、拉镜像的实测速度和米家/海尔接入。

## 2.1 前置：WSL2 + Docker Desktop

### 坑：`wsl --install` 报 403

```
wsl --install
# → 403 已禁止
```

**原因**：微软 CDN 被墙。

**解法**：改从 GitHub 拉 MSIX 包，绕开 CDN：

```powershell
# 需要管理员 PowerShell（否则报 0x80073d28）
winget install --id Microsoft.WSL --exact
```

装完**需要重启**才生效。

### 装 Docker Desktop

```powershell
winget install Docker.DockerDesktop     # 约 606MB
```

装完把 Docker 的 bin 加进用户 PATH（新会话才生效）：

```
C:\Program Files\Docker\Docker\resources\bin
```

### 配置镜像加速器（国内必做）

编辑 `C:\Users\<用户名>\.docker\daemon.json`：

```json
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.1ms.run",
    "https://docker.1panel.live",
    "https://dockerproxy.net"
  ]
}
```

改完 `docker desktop restart` 生效，用 `docker info` 看 Mirrors 是否加载。

## 2.2 镜像源实测测速（重点，省得你挨个试）

> 📜 对应的脚本：[`scripts/03-run-ha.ps1`](../scripts/03-run-ha.ps1)（起 HA）、
> [`scripts/01-check.ps1`](../scripts/01-check.ps1)（环境自检）。
> 脚本里 HA 版本是**固定值** `2026.9.3`，**不要**改回 `:stable`（原因见下表下方）。

拉同一个镜像实测下行速度：

| 源 | 实测速度 | 结论 |
|---|---|---|
| **ghcr.chenby.cn**（ghcr 代理）| **111.8 Mbps** | ✅✅ 最快，首选 |
| **docker.1ms.run** | 43.9 Mbps | ✅ 备选 |
| **docker.m.daocloud.io** | 38.6 Mbps | ✅ 备选 |
| 华为 SWR `swr.cn-north-4.myhuaweicloud.com` | 83 Mbps | ✅ 快，但 **HA 的 tag 缓存过旧** |
| 清华 TUNA / npmmirror | 24 / 19 Mbps | 通用下载还行 |
| ghcr.io 直连 | 1.4 Mbps | ❌ 被限速 |
| docker.xuanyuan.me | 0.65 Mbps | ❌ |

**结论**：不是家里宽带慢（国内源能跑到 100+ Mbps），而是 **ghcr.io / Docker Hub 直连线路被限速**。

**推荐拉法**：

```powershell
# ghcr.io 的镜像（Home Assistant 等）
docker pull ghcr.chenby.cn/home-assistant/home-assistant:2026.9.3

# Docker Hub 的镜像（MiGPT 等）
docker pull docker.1ms.run/lmk123/migpt-server:latest
```

> **华为 SWR 的坑**：它的 `stable` 标签缓存停留在 2024.7.1，直接拉 `:stable` 会拿到两年前的版本。
> 要么指定明确版本号，要么换 `ghcr.chenby.cn`。

## 2.3 启动 Home Assistant

```powershell
docker run -d --name ha --restart unless-stopped `
  -p 8123:8123 `
  -v "$env:USERPROFILE\ha-data:/config" `
  -e TZ=Asia/Shanghai `
  ghcr.io/home-assistant/home-assistant:2026.9.3
```

浏览器打开 `http://localhost:8123` 完成初始化向导（创建管理员账号）。

**升级版本**：

```powershell
docker pull ghcr.chenby.cn/home-assistant/home-assistant:<新版本>
docker tag  <拉下来的镜像> ghcr.io/home-assistant/home-assistant:<新版本>
docker rm -f ha
docker run ... <新版本>
```

## 2.4 接入米家（Xiaomi Miot Auto）

1. 下载集成（走 GitHub 加速）：

   ```
   https://gh-proxy.com/https://github.com/al-one/hass-xiaomi-miot/archive/refs/heads/master.zip
   ```

2. 解压后把 `custom_components/xiaomi_miot` 放到 `ha-data\custom_components\`
3. 重启 HA → 设置 → 设备与服务 → 添加集成 → **Xiaomi Miot** → 服务器选**中国大陆（cn）**
4. 填**小米 ID**（不是手机号）+ 密码

> 实测结果：7 台设备、55 个实体接入。

## 2.5 接入海尔（Haier）

1. 下载集成：

   ```
   https://gh-proxy.com/https://github.com/banto6/haier/archive/refs/heads/master.zip
   ```

2. 放到 `ha-data\custom_components\haier`
3. 重启 HA → 添加集成 → **Haier** → 登录海尔智家账号

> ⚠️ **海尔没有官方集成**。别装成 `gvigroux/hon` —— 那是海外 hOn 平台，国内账号登不上。

## 2.6 生成 HA 长期令牌

HA 左下角用户头像 → **安全** → **长期访问令牌** → 创建。

得到一个 `eyJ...` 开头的长字符串，**只显示一次，先存好**。它等同 HA 的完整控制权。

```bash
# 存到只有你能读的地方
chmod 600 ~/.hermes/.env
```

## 2.7 接入后的实测规模

| 项 | 值 |
|---|---|
| HA 版本 | 2026.9.3 |
| 集成 | Xiaomi Miot（米家）+ Haier（海尔）|
| 实体总数 | **169 个**（其中可控约 58 个）|

> **实体多不等于好用**：169 个实体如果被 AI 整表拉下来，会直接把 prompt 撑到 6–7 万 token。
> 详见 [06 提速](06-performance.md)。

## 2.8 让家庭机 7×24 不睡眠

- 电源设置：睡眠 / 休眠 / 硬盘超时 = **永不**（屏幕可以关）
- 容器加 `--restart unless-stopped`
- Docker Desktop 设 `AutoStart=true`（或勾选开机启动）

> Docker Desktop 是**用户级**应用，必须**用户登录后**才能启动；
> 所以"自启"要设计成"登录触发"，而不是"开机（未登录）触发"。


---

# 03 · 云端 Hermes 接入 Home Assistant

> 这一篇是最容易卡住的地方 —— 不是 HA 侧的配置难，而是 **Hermes 装插件会踩一个 5 步凑成的坑**。
> 出问题直接跳到 §3.4。

## 3.1 装插件

```bash
# 注意：本机必须带 PIP_CONFIG_FILE，原因见 §3.4
PIP_CONFIG_FILE=/dev/null hermes plugins install homeassistant
PIP_CONFIG_FILE=/dev/null hermes plugins enable homeassistant
```

> `homeassistant` 是**官方 catalog 插件**，不需要第三方源。

## 3.2 写环境变量

编辑 `~/.hermes/.env`（若不存在则新建）：

```bash
HASS_TOKEN=<HA_TOKEN>
HASS_URL=http://<HOME_TS_IP>:8123
```

> 用 **Tailscale IP**，不要用局域网 IP（跨网络不通），也不要用公网地址（HA 不该暴露公网）。
>
> **不要给值加引号**。改完 `.env` 必须**重启 Hermes 进程**才生效 —— `.env` 只在进程启动时读取。

## 3.3 重启网关并验证

```bash
hermes gateway restart          # ⚠️ 必须在网关进程外的 shell 执行，见 §3.6

hermes plugins list             # 应看到 homeassistant
hermes tools list               # 应看到 homeassistant 工具集
```

插件提供的 4 个工具：

| 工具 | 作用 |
|---|---|
| `ha_list_entities(domain?, area?)` | 列设备，可按灯 / 空调 / 传感器筛选 |
| `ha_get_state(entity_id)` | 查某设备状态（亮度、温度设定等）|
| `ha_list_services(domain?)` | 看某类设备可执行哪些动作 |
| `ha_call_service(domain, service, entity_id?, data?)` | 执行动作 |

**端到端测试**（在已接入的对话入口里说）：

- 「列出我家所有设备」→ 返回可控设备
- 「打开台灯」→ 真的调用 `light.turn_on`
- 「空调调到 26 度」→ 调用 `climate.set_temperature`

### 两个"看起来像故障"的正常现象

1. **工具"看不见"**：如果开了 *Tool Search*，`ha_*` 会藏在 `tool_search` / `tool_call` 后面，需要先检索再调用。**这是正常的，不是没装好。**
2. **HA 插件自带安全限制**：`shell_command`、`command_line`、`python_script`、`pyscript`、`hassio`、`rest_command` 等危险域被 Hermes 主动屏蔽，AI 无法误触发。**无需配置。**

## 3.4 【最坑】`hermes plugins enable` 报 uv "has no publish time"

### 现象

```
DependencyConflict: Plugin 'homeassistant' conflicts with the dependencies pinned by
Hermes core ... Because resvg-py{python_full_version >= '3.14'}==0.4.0 has no publish
time and hermes-agent depends on ... ==0.4.0 ... requirements are unsatisfiable.
```

### 第一个关键认知

报错里的包（`resvg-py` / `tomli-w` / `pilk` / `huggingface-hub` / `playwright` / `pypinyin`）**全是 Hermes 核心依赖，不是插件依赖**。

→ 换任何插件都会踩同一个坑；修掉一个，uv 立刻换下一个包名继续报。**别以为是插件的问题。**

### 根因链（5 步，每步都合理，凑一起才出事）

1. 核心 `pyproject.toml` 有 `[tool.uv] exclude-newer = "14 days"` —— 供应链新鲜度闸门：只允许 14 天前及更早发布的版本。
2. 执行该闸门**必须知道每个文件的发布时间**（PEP 700 的 `upload-time`）。拿不到就保守地当作"太新"排除。
3. 被排除的是**精确锁定**（`==X.Y.Z`）且是唯一候选 → 不是降级，而是**无解硬失败**。
4. 加插件 → 插件成为 workspace 成员 → 包管理器把全局 cutoff 改写成逐包 `exclude-newer-package` → uv 判定解析输入变更（日志：`Resolving despite existing lockfile due to removal of global exclude newer`）→ **全量重新解析**，不复用 `uv.lock`。
5. 重解析要取所有包的发布时间。而包管理器会把 **`~/.pip/pip.conf` 的 `index-url` 桥接成 `UV_INDEX_URL`**（uv 本身不读 pip 配置）。如果这个源是**阿里云镜像**，它的 simple 索引**完全没有 `upload-time`** → 回到第 2 步引爆。

### 修法（不改任何源码）

```bash
PIP_CONFIG_FILE=/dev/null hermes plugins enable <name>
```

切断 `pip.conf → uv` 的桥接，让 uv 走默认 PyPI 索引（时间戳完整）。

### 国内镜像调研结论（省得你再试一遍）

| 镜像 | PEP 691 JSON | `upload-time` 完整 | 下载速度 | 结论 |
|---|---|---|---|---|
| aliyun | ❌ 只有 HTML | — | 快 | **不可用**（无时间戳）|
| tuna（清华）| ✅ | ❌ 老包缺失（如 `pilk` 0/42）| 快 | 不可用 |
| ustc（中科大）| ✅ | ✅ 完整 | **429 限流** | 不可用 |
| **pypi.org** | ✅ | ✅ 完整 | 慢（跨境）| **本文采用**（全量重解析 + 建 venv 约 10 分钟）|

**检测命令**（换个 `<index-url>` 就能测任何源）：

```bash
curl -s -H 'Accept: application/vnd.pypi.simple.v1+json' <index-url>/simple/<pkg>/ \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(sum(1 for f in d['files'] if f.get('upload-time')), len(d['files']))"
# 输出 "N N" 才可用；"0 N" 表示完全没有时间戳
```

### 试过但无效／方向错的做法（勿重走）

| 做法 | 结果 |
|---|---|
| 改核心 `pyproject.toml` 加豁免 | 有效但属源码编辑，`hermes update` 会覆盖 → 不算"不改代码" |
| 手写 `config.yaml` 的 `plugins.enabled` | 插件加载后被网关复检，**自动禁用**（提示 `the dependency environment no longer builds with it`）|
| 设 `UV_EXCLUDE_NEWER=…` 环境变量 | 无效：包管理器会剥离非白名单的 `UV_*`，且 uv 是从 pyproject 读的 |
| 清 uv 缓存 / 换 uv 版本 | 无效。`uv lock` 单独在项目里跑 1 秒就成功（328 包 0 警告），**问题只在包管理器的调用路径** |
| 怀疑包管理器的 uv 缓存目录 | 无效，直接用该缓存跑也成功 |

**只透传这些 `UV_*` 给 uv**：`UV_INDEX_URL` / `UV_EXTRA_INDEX_URL` / `UV_DEFAULT_INDEX` / `UV_INDEX` / `UV_NO_INDEX` / `UV_FIND_LINKS` / `UV_INDEX_STRATEGY` / `UV_KEYRING_PROVIDER` / `UV_NATIVE_TLS` / `UV_INSECURE_HOST` / `UV_HTTP_TIMEOUT`。
其余一律丢弃 —— 所以设 `UV_CONCURRENT_DOWNLOADS` 之类是没用的。

## 3.5 systemd unit 会被 Hermes 重新生成 → 必须用 drop-in

**现象**：把 `Environment="PIP_CONFIG_FILE=/dev/null"` 直接写进
`~/.config/systemd/user/hermes-gateway.service`，重启后**被静默抹掉**（Hermes 会重新生成自己的 unit 文件）。

**修法**：改用 systemd drop-in（Hermes 不碰 drop-in 目录）：

```bash
mkdir -p ~/.config/systemd/user/hermes-gateway.service.d
cat > ~/.config/systemd/user/hermes-gateway.service.d/override.conf <<'EOF'
[Service]
Environment="PIP_CONFIG_FILE=/dev/null"
EOF
systemctl --user daemon-reload
systemctl --user show hermes-gateway -p Environment --value   # 验证合并结果
```

> ⚠️ drop-in 只对 **systemd 服务**生效。你在 shell 里手工跑 `hermes plugins enable` 时仍要自己带 `PIP_CONFIG_FILE=/dev/null`。

## 3.6 网关无法从内部自我重启

**现象**：在会话里执行 `hermes gateway restart`（即使用 `systemd-run` 延迟调度）会被安全护栏拒绝：

> *Blocked: command or referenced script cannot restart, stop, or uninstall the gateway from inside the gateway process. The gateway would kill this command before it could complete (SIGTERM propagates to child processes). Run `hermes gateway restart` from a separate shell outside the running gateway.*

**结论**：**重启网关必须由人在网关外的 shell 执行**。插件 / 工具的变更会提示 `Takes effect on next session / deferred: tools (next session)`，重启后新会话才加载。

## 3.7 其他环境事实（排障有用）

- 网关通常是**用户级** systemd 服务（`systemctl --user`），单元名 `hermes-gateway.service`；`ActiveEnterTimestamp` 可查上次重启时间
- 插件依赖生成的环境：`~/.hermes/installs/<id>/environments/<hash>/workspace/`（内有生成的 `pyproject.toml` + `uv.lock`）
- 包管理器用的 uv **不是** PATH 上那个，而是 `~/.hermes/tools/uv-<版本>-linux-x64/uv`
- 它的 uv 缓存是 `~/.hermes/cache/uv`（**专属**，不是 `~/.cache/uv`）
- Hermes 自带 Python 在 `~/.hermes/tools/python-<版本>-linux-x64/bin/python3`；**注意别用系统的 `/usr/bin/python3`**（版本通常更老）

## 3.8 `.env` 里的内联注释是安全的

`API_SERVER_HOST=<HERMES_TS_IP> # 关键！默认 127.0.0.1 外部访问不到` 这种写法**没问题**。

Hermes 用 python-dotenv 语义：未加引号的值只截断**前面带空白的** ` #`，而 `foo#bar` 会原样保留。

## 3.9 备份目录规律（容易找错地方的坑）

`hermes config set` / `hermes config edit` 的自动备份落在：

```
~/.hermes/backups/config/config.yaml.bak.<时间戳>
```

**不是** `~/.hermes/` 根目录。只有你手工 `cp` 出来的（例如 `.env.bak.*`）才在根目录。

所以**查备份别只 `ls ~/.hermes/`**，用查找：

```bash
find ~/.hermes -name '*.bak*' -maxdepth 3
```

**回退的正确姿势**：

| 要回退什么 | 怎么做 |
|---|---|
| 插件配置 | `hermes plugins disable <name>` —— **不要手改 `config.yaml`**（会被网关复检并自动禁用）|
| 工具集 | `hermes config unset platform_toolsets.api_server`，或恢复上表备份 |
| `.env` 凭据 | 从 `.env.bak.<时间戳>` 手工恢复，然后重启 |

> **原则**：源码级试验（改 `pyproject.toml` 之类）一律先备份再改，`hermes update` 会覆盖；
> 优先用官方 CLI 命令改配置，而不是直接编辑 YAML。


---

# 04 · 开放 OpenAI 兼容 API Server（供 MiGPT 调用）

> 目的：让家庭端的 MiGPT 把语音问答转发给云端的 Hermes。
> 家庭端与云端已在同一 Tailscale 虚拟内网（实测互通）。

## 4.1 现状与唯一障碍

| 项 | 值 |
|---|---|
| 家庭机 Tailscale IP | `<HOME_TS_IP>` |
| 云端 Tailscale IP | `<HERMES_TS_IP>` |
| 实测互通 | 家庭端 `tailscale ping <HERMES_TS_IP>` → pong ~23ms ✅ |

**唯一障碍**：云端 `<HERMES_TS_IP>:8642` 端口探测连接失败。
原因：**Hermes API server 默认只绑 `127.0.0.1`**，Tailscale 网段访问不到。

## 4.2 配置

编辑 `~/.hermes/.env`：

```bash
API_SERVER_ENABLED=true
API_SERVER_HOST=<HERMES_TS_IP>    # 关键！默认 127.0.0.1 外部访问不到
API_SERVER_PORT=8642
API_SERVER_KEY=<API_SERVER_KEY>   # openssl rand -hex 32
API_SERVER_MODEL_NAME=hermes-agent
```

> **为什么绑 Tailscale IP 而不是 `0.0.0.0`**：公网网卡根本不监听，安全得多。
> 副作用：Tailscale IP 变了会失联，那时改成 `0.0.0.0` 或重设 IP。
>
> **云安全组无需放行 8642**（走 Tailscale 内网即可）。

也支持写进 `config.yaml`（环境变量优先级更高）：

```yaml
gateway:
  api_server:
    enabled: true
    host: <HERMES_TS_IP>
    port: 8642
    key: <API_SERVER_KEY>
    model_name: hermes-agent
```

`gateway.platforms.api_server:` 或顶层 `platforms.api_server:` 也接受。

## 4.3 生效

```bash
# ⚠️ 必须在网关进程外的 shell 执行（原因见 03 篇 §3.6）
hermes gateway restart
```

期望日志：

```
[API Server] API server listening on http://<HERMES_TS_IP>:8642 (model: hermes-agent)
```

MiGPT 侧把 base URL 填成 `http://<HERMES_TS_IP>:8642/v1`。

## 4.4 端点与鉴权

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/health` | **免鉴权**。返回 `{"status":"ok","platform":"hermes-agent","version":"…"}` |
| GET | `/v1/health` | 同上别名 |
| GET | `/health/detailed` | 需鉴权，带就绪检查 |
| GET | `/v1/models` | 需鉴权。返回模型名 |
| GET | `/v1/capabilities` | 能力自描述 |
| POST | `/v1/chat/completions` | 需鉴权。**带完整工具集** |
| POST | `/v1/responses` | 需鉴权。支持 `previous_response_id` 服务端状态 |
| POST | `/v1/runs`、`GET /v1/runs/{id}`、`/events`、`/stop` | Runs API（SSE 订阅）|
| GET | `/api/sessions` 等 | 会话管理 REST |
| GET | `/v1/skills`、`/v1/toolsets` | 能力枚举 |

鉴权头：`Authorization: Bearer <API_SERVER_KEY>`

> 工具集精简要改这里看到的 `/v1/toolsets`，见 [06 提速](06-performance.md)。

## 4.5 自测三条

```bash
# 1) 本机自测（免鉴权）
curl http://127.0.0.1:8642/health

# 2) 用 Tailscale IP 自测
curl http://<HERMES_TS_IP>:8642/v1/models \
  -H "Authorization: Bearer <API_SERVER_KEY>"

# 3) 模拟 MiGPT 的调用（OpenAI 兼容）
curl http://<HERMES_TS_IP>:8642/v1/chat/completions \
  -H "Authorization: Bearer <API_SERVER_KEY>" -H "Content-Type: application/json" \
  -d '{"model":"hermes-agent","messages":[{"role":"user","content":"列出我家所有设备"}]}'
# 期望：返回 agent 的回答（会真的调用 HA 列出设备）
```

## 4.6 实测校准：4 个容易想当然的地方

| # | 想当然 | 实际 |
|---|---|---|
| 1 | `/health` 返回 `{"status":"ok"}` | 实际是**三个字段**：`status` / `platform` / `version`。脚本里判断请用**包含匹配**，别写严格等值 |
| 2 | 启动日志到 `:8642` 结束 | 末尾还会多一段 `(model: hermes-agent)`。按日志做健康检查时要匹配上 |
| 3 | `hermes gateway` 起服务 | 若本机已有 systemd 服务，应使用 **`hermes gateway restart`**；直接跑 `hermes gateway` 会冲突 |
| 4 | 请求体里的 `"model"` 会切模型 | 该字段**默认被忽略**（裸 `model` 不带 `provider` 时回落到网关默认模型）。要生效需设 `gateway.platforms.api_server.direct_model_requests: true`。**不影响功能** |

两点确认无误：

- **不需要** `API_SERVER_CORS_ORIGINS` —— MiGPT 是服务端调用，不涉浏览器同源 ✅
- `API_SERVER_MODEL_NAME=hermes-agent` 本就是 default 配置档的默认值（写上是冗余但无害）✅

## 4.7 完成标准（DoD）

- [ ] 网关日志显示 API server 监听在 `<HERMES_TS_IP>:8642`
- [ ] `curl http://<HERMES_TS_IP>:8642/health` 返回含 `"status":"ok"`
- [ ] `/v1/models` 带 Key 访问返回包含 `hermes-agent`
- [ ] `/v1/chat/completions` 能正常返回回答

## 4.8 故障排查

| 现象 | 排查 |
|---|---|
| 8642 连不上 | `API_SERVER_HOST` 是否已改成 Tailscale IP 或 `0.0.0.0`；网关是否重启 |
| **401 Unauthorized（任何 key 都 401）** | 见下方 §4.9 —— 这是**鉴权层 fail-closed**，不是 key 填错 |
| `/health` 通但 chat 报错 | 云端 Hermes 未配好模型 provider，或未装 `homeassistant` 插件 |
| 回答里没有设备信息 | `HASS_TOKEN` / `HASS_URL` 没配好，或 Tailscale 到 `<HOME_TS_IP>` 不通 |

## 4.9 ❌ 已知问题：鉴权 401（**这条路实际从未通通过**）

> 这是本仓库最重要的"坑"之一 —— 排查过程比结论更有参考价值。
> **结论：未修复，该入口已放弃**（原因见 [README](../README.md#为什么放弃小爱migpt-入口)）。

### 现象

`/health`（免鉴权）正常返回 200，但所有需鉴权的端点全部 401：

```
GET  /v1/models            → 401
GET  /v1/toolsets          → 401
POST /v1/chat/completions  → 401
GET  /health               → 200  ✅
```

### 决定性探针实验

用**四种完全不同的 key** 去打同一个端点：

```
真实 key      → 401
全零假 key    → 401
截断 63 位    → 401
大写化        → 401
```

四种返回**一模一样** → 可以排除"key 值不对"。

> 推理：如果 key 值真的参与了比较，至少有一种会得到不同结果。
> 全部一致 ⇒ **比较根本没走到"值比较"这一步**。

### 根因：凭据 scope 解析 fail-closed，`expected_key` 变成空串

Hermes 读环境变量的入口是 `gateway/config.py` 的 `_getenv`，它的 docstring 写得很清楚：

```python
def _getenv(name, default=None):
    """Read env vars through the active profile secret scope when present.

    load_gateway_config() runs in many contexts, including multiplexed
    profile startup where _profile_runtime_scope installs per-profile
    secrets. In that scope we must prefer the scoped value; outside it we
    keep legacy os.getenv behavior for single-profile callers and unscoped
    gateway reads.
    """
    if current_secret_scope() is not None:
        scope_val = _get_secret(name, None)          # ← 请求路径上走这里
        return scope_val if scope_val is not None else default
    env_val = os.environ.get(name)
    if env_val is not None:
        return env_val
    return default
```

对应的鉴权侧（`gateway/platforms/api_server.py`）：

```python
def _expected_api_key(self) -> str:
    """Return the API key authorized for the URL-selected profile."""
    profile = _api_request_profile.get()
    if not profile or profile == "default":
        return self._api_key                       # ← 构造期从 .env 读到的正确 key

    key = get_secret("API_SERVER_KEY", "") or ""
    if not has_usable_secret(key, min_length=16):
        return ""                                   # ← fail-closed：返回空串
    return key
```

于是链条是：

1. `self._api_key` 在**适配器构造时**从 `.env` 算出来 —— 值是正确的，所以能通过 `min_length=16` 启动守卫，**服务正常监听**（日志里能看到 `API server listening on …`，不是启动失败）
2. 但**请求进来后**走的是 `_expected_api_key()`，当请求被路由到**命名 profile** 时，改从 `get_secret("API_SERVER_KEY")` 读 —— 而那份 scope 的 mapping 里**没有 `API_SERVER_KEY`**
3. `has_usable_secret` 判定不可用 → 返回 **空串**
4. `_check_auth` 里 `expected_key` 为空且 `is_named_profile=True` → **fail-closed，直接 401**
5. 因为短路发生了，**任何 Bearer 都到不了值比较** → 四种 key 结果一致

> 设计意图是好的：注释里写着 "per-profile secrets must win"，并且多处显式 `UnscopedSecretError`，
> 属于**有意的 fail-closed**，不是 bug 式的手滑。只是对"单 profile + 只配 `.env`"这种朴素用法不友好。

**时间线佐证**：网关两次启动都有正常的 `API server listening on … (model: hermes-agent)` 日志（**非启动失败**）；
最早的 401 来自家庭端 IP → 说明 **MiGPT/小爱侧从未真正成功调用过**。

### 候选修法（本次未验证，需重启才能确认）

把 key 也写进 `config.yaml` 的 `gateway.api_server.key`，走 `extra["key"]` 这条**构造期就确定**的路径，绕开请求时的 scope 解析：

```yaml
gateway:
  api_server:
    key: <API_SERVER_KEY>
```

> ⚠️ 代价：这把 key 会**明文落进 `config.yaml`**。`config.yaml` 权限虽也是 `600`，但它的"使用面"比 `.env` 更宽
> （会被 `hermes config show` / 备份 / 各种工具读到），安全性需要自己权衡。
>
> **更干净的方向**：先查清 **为什么 API server 的请求路径上 secret scope 非空**（这本该是空的多 profile 才有）。
> 如果确实是多 profile 路由导致的，让请求落在 default profile 也是等效修法。

### 为什么没继续修

- 修它要动凭据 scope 解析路径（或把 key 明文落到 `config.yaml`），**性价比不高**
- 该入口的收益（"对音箱说话"）可以用**飞书**替代，且飞书侧完全不受影响
- 故：**记录留档，放弃该入口**。若日后重启此方案，先修 401，再处理小爱侧的短期记忆字段

### 给后来者的两个提醒

1. **看到"启动日志正常 + 所有请求 401"**，先怀疑权限链路上的**空值 fail-closed**，而不是反复试 key。
   做法就是上面的探针：拿 3–4 个差异极大的 key 打一次，**若结果完全一致，问题一定不在 key 值上**。
2. **精简工具集是独立于 401 的**，两者互不影响（见 [06 篇](06-performance.md)）。


---

# 05 · MiGPT 语音入口（小爱音箱）

> 目的：本地跑 MiGPT GUI，监听小爱音箱的语音，命中唤醒词后把问题转发给云端 Hermes。

> ## ❌ 状态：这一环**从未真正打通**，已决定放弃
>
> MiGPT 侧本身配好了（能登录、能找到设备、能发出请求），但云端 API Server 的**鉴权 401 未解决**
> （见 [04 篇 §4.9](04-hermes-api-server.md)），所以请求到不了 Hermes。
>
> 本页仍然有参考价值：**MiGPT 本身的坑**（镜像名、端口、数字 did、passToken、事件帧崩溃、子进程不恢复）
> 都是真实踩过的，且与 401 无关 —— 将来若修好 401，这些经验直接可用。
>
> 日常控家改走**飞书**入口。

## 5.1 先修正两个网上文章里的错

| 网上文章写的 | 实际 |
|---|---|
| MiGPT 镜像 `lmk123/mi-gpt-gui:latest` | 该镜像/名字**不存在**。真实项目是 **`lmk123/migpt-server`**（MiGPT GUI）|
| MiGPT 端口 `3210` | 实际默认端口 **`36592`** |
| 需要自己写 HA REST 工具 | Hermes **原生内置** Home Assistant 工具，配 `HASS_TOKEN` 即自动启用 4 个 `ha_*` 工具 |
| 让云端直接访问家里 HA（端口映射）| 国内家宽多为 CGNAT，**拿不到公网 IP，映射不通** → 用 Tailscale |

## 5.2 启动容器

> 📜 对应的脚本：[`scripts/04-run-migpt.ps1`](../scripts/04-run-migpt.ps1)（起容器）、
> [`scripts/start-xiaoai.ps1`](../scripts/start-xiaoai.ps1)（一键启动全部）、
> [`scripts/autostart-xiaoai.ps1`](../scripts/autostart-xiaoai.ps1)（开机守护）。
> 脚本清单与说明见 [`scripts/README.md`](../scripts/README.md)。

```powershell
docker run -d --name migpt-server --restart unless-stopped `
  -p 36592:36592 `
  -v "$env:USERPROFILE\migpt-data:/root/.migptgui" `
  lmk123/migpt-server
```

访问 `http://localhost:36592`。

> 国内拉取慢的话用镜像加速：`docker pull docker.1ms.run/lmk123/migpt-server:latest`

## 5.3 GUI 里要填的

### 小米账号 / 设备

| 项 | 值 |
|---|---|
| 小米账号 ID | 「个人信息」里的**小米 ID**（不是手机号 / 邮箱）|
| 密码 | 小米账号密码（**异地登录可能触发风控**，见 §5.6）|
| 设备 | 型号选 L15A；设备填**数字 did**（见 §5.7）|

### 接入 Hermes（AI 配置）

| 项 | 值 |
|---|---|
| AI 类型 | **OpenAI 兼容** |
| API Base | `http://<HERMES_TS_IP>:8642/v1`（走 Tailscale，无需开放公网 8642）|
| API Key | `<API_SERVER_KEY>` |
| Model | `hermes-agent` |

### 唤醒词

示例：`["请", "你", "<唤醒词>"]`

- 「小爱同学，请打开台灯」
- 「小爱同学，<唤醒词>…」

> 唤醒词建议选**日常不常说**的词，否则会被误触发。

## 5.4 L15A 设备参数（已对官方兼容性表核实 ✅）

```js
ttsCommand:      [7, 3],
wakeUpCommand:   [7, 1],
playingCommand:  [3, 1, 1],
streamResponse:  false,   // 建议先关，见下方说明
```

**关于 `streamResponse`**：

- 官方兼容性表标注 L15A 支持 `true`（连续对话）
- 但实测**流式反而更慢**（36s vs 23s），且会触发 MiGPT 解析崩溃（见 [06 提速](06-performance.md)）
- 建议先用 `false` 跑稳，需要连续对话再开

## 5.5 测试

1. 看日志：`docker logs -f migpt-server`
2. 对音箱说：`<唤醒词>，请打开台灯`
3. 期望：音箱先「叮」提示，稍后播报 Hermes 的回答；台灯真实点亮

## 5.6 坑一：小米账号异地登录风控

**现象**：MiGPT 日志报

```
🔥 触发小米账号异地登录安全验证机制
初始化 Mi Services 失败
```

**原因**：小米对异地登录做风控（容器 IP 与你手机不在同一地）。

**解法：用 passToken 绕过**

1. 浏览器登录 `https://account.xiaomi.com`
2. F12 → Application → Cookies → 复制 `passToken` 的值
3. 写入 `migpt-data\default\.mi.json`：

   ```json
   {"mina":{"pass":{"passToken":"V1:..."}},"miiot":{"pass":{"passToken":"V1:..."}}}
   ```

4. 重启容器

**成功后日志**：`Speaker ✅ 服务已启动...`

> passToken 等同你小米账号的登录凭据，**不要外传**。

## 5.7 坑二：「找不到设备」→ 必须用数字 did

**现象**：填米家 App 里显示的设备名（如 `MI AI Speaker (2nd Gen)`）会报「找不到设备」。

**原因**：Mina 与 MIoT 两个子系统看到的设备名可能不一致。

**解法**：改用**数字 did**（官方 FAQ 的建议）。设备名去米家复制没用，得用数字 ID。

> 本机实测：填数字 did 后成功；填设备名失败。

## 5.8 坑三：Hermes 事件帧导致 MiGPT 崩溃

**现象**：Hermes 触发工具调用时会发 `event: hermes.tool.progress` 事件帧（**没有 `choices` 字段**），
MiGPT 直接读 `chunk.choices[0]` 抛 `TypeError`，服务崩溃。

**修复**：把 `chunk.choices[0]` 改成可选链 `chunk.choices?.[0]`，安全跳过非标准帧。

> 这个补丁需要打进 MiGPT 的代码。做法：写一个补丁脚本，在容器启动后自动改文件再拉起服务，
> 并接到开机守护里，保证容器重建后自动重打。

## 5.9 坑四：MiGPT 跑在 GUI 的子进程里，容器重启后不恢复

**现象**：Docker / 容器重启后，MiGPT 的 AI 服务**不会自动恢复** —— 它跑在 GUI 的子进程里。

**解法**：守护脚本在容器就绪后，调用 GUI 的 `POST /api/default/start` 重新触发启动。

```bash
# 示例（Node 脚本，内部就是 POST 一下）
node start-migpt.mjs
```

**开机守护要点**：

| 项 | 做法 |
|---|---|
| Docker Desktop 自启 | `AutoStart=true` + 注册表 Run 项（用户级应用，需**登录后**触发）|
| 计划任务 | 登录时运行守护脚本，等引擎就绪 → 拉起容器 → 触发 MiGPT 子进程 |
| 容器重启策略 | `--restart unless-stopped` |
| 电源 | 睡眠 / 休眠 / 硬盘超时 = 永不 |

## 5.10 数据目录与配置位置

| 项 | 路径 |
|---|---|
| 数据目录（宿主）| `%USERPROFILE%\migpt-data`（绑定到容器 `/root/.migptgui`）|
| MiGPT 配置 | `%USERPROFILE%\migpt-data\default\migptgui.json` |
| 小米凭据 | `%USERPROFILE%\migpt-data\default\.mi.json` |
| 守护日志 | `%USERPROFILE%\migpt-data\autostart.log` |

## 5.11 常见问题速查

| 现象 | 原因 / 处理 |
|---|---|
| 报「找不到设备」| 设备名与米家不一致 → **改用数字 did** |
| 登录报风控 | 异地登录风控 → 用 **passToken**（§5.6）|
| 登录报 `70016` | 小米 ID 填错了（填成手机号/邮箱）|
| 说几个字就说「我说完了」| `streamResponse` 改 `false`；或该型号不支持连续对话 |
| 完全没反应 | `docker logs -f migpt-server`；确认唤醒词、API Base、Key 都对 |
| 笔记本睡眠就断 | 关睡眠（屏幕可关）；容器加 `--restart unless-stopped` |
| Hermes 调工具时 MiGPT 崩溃 | 打可选链补丁（§5.8）|
| 响应很慢 | 精简 Hermes 工具集（[06 篇](06-performance.md)）|
| 同一会话越聊越慢 | 开启 Hermes 上下文压缩（[07 篇](07-session-memory.md)）|


---

# 06 · 提速：精简 API Server 的工具集

> 场景：小爱音箱 → MiGPT → 云端 Hermes → Home Assistant 控设备。
> 症状：响应很慢（查一次设备 **23–36 秒**）。

> ## ⚠️ 关于本文的实测数据
>
> 下表数据来自当时的实测记录，但**后来发现 API Server 存在鉴权 401（[04 篇 §4.9](04-hermes-api-server.md)）**，
> 所以这批测量的**具体通道存疑** —— 它们可能并非通过 API Server 取得。
>
> **不过结论本身是独立成立的**：`/v1/toolsets` 能枚举出 38–42 个工具、
> 基础提示词 1.4 万 token 是**可直接观测的静态事实**，与走哪条通道无关。
> 工具集过大导致模型输入膨胀，这个因果链是确定的。

## 6.1 先定位：不是网络，也不是模型

家庭端实测（非流式）：

| 请求 | 耗时 | prompt token |
|---|---|---|
| 「1+1」 | 4.8s | 14,521 |
| 「今天天气不错」 | 9.8s | 29,257 |
| 「客厅台灯开着吗」 | **23.5s** | **60,041 – 74,868** |

对照：家庭端 → 云端 Tailscale 往返仅 **34ms**。

→ **慢全在 Hermes 服务端**，而且是 **prompt 太大**（模型光读输入就十几秒），
不是网络、也不是模型选型（已用轻量模型 + 关推理）。

## 6.2 根因：API server 默认挂了 42 个工具

Hermes 的 API server 默认使用平台工具集 `hermes-api-server`，它保留**几乎所有工具**（仅去掉 clarify / tts / computer_use / kanban）。

用 `GET /v1/toolsets` 实测到 **29 个工具集、42 个工具**：

```
web(2) browser(18) terminal(2) file(4) code_execution(1) vision(1)
image_gen(1) skills(3) todo(1) memory(1) session_search(1) connections(1)
delegation(1) cronjob(1) homeassistant(4) ...
```

每次请求都要把这些工具的**完整 JSON schema** 放进模型输入：

- 基础请求就要 **1.4 万 token**
- 一旦涉及工具调用，叠加 HA 的 **169 个实体列表**，冲到 **6–7 万 token**
- **模型读这些就花掉十几秒**

> 这是"工具越多越慢"的典型代价：核心工具是**每次 API 调用都要付费**的（prompt 前缀）。

## 6.3 方案 A（最有效）：把 api_server 的工具集精简到「只留控家必需」

**不要手改 YAML**，用结构化命令写（避免格式被写坏）：

```bash
hermes config set platform_toolsets.api_server '["homeassistant", "memory", "web"]'
hermes config get --json platform_toolsets.api_server     # 核对
```

留这三个就够：

| toolset | 工具数 | 用途 |
|---|---|---|
| `homeassistant` | 4 | 查设备 / 控设备（核心）|
| `web` | 2 | `web_search` + `web_extract` ——「今天天气如何」必须靠它 |
| `memory` | 1 | 跨会话长期事实记忆 |

**38 个工具 → 7 个**，砍掉 31 个。

> ⚠️ **不要加 `terminal`。** API Server 是网络可达的，网关启动日志里明确警告：
> *Agent work dispatched through this endpoint runs as the host user with full terminal/file access*。
> 控家场景完全不需要它。

**验证**：

```bash
curl -s http://<HERMES_TS_IP>:8642/v1/toolsets \
  -H "Authorization: Bearer <API_SERVER_KEY>" | python3 -m json.tool
# 期望：只剩 homeassistant / web / memory，工具数大幅减少
# （⚠️ 本次因鉴权 401 取不到，需先修 04 篇 §4.9）
```

### 回退

```bash
hermes config unset platform_toolsets.api_server
# 或恢复备份：~/.hermes/backups/config/config.yaml.bak.<时间戳>.pre-toolset-trim
```

### 两个"为什么没出事"的说明

1. **为什么这次重启没踩 uv 坑**（[03 篇 §3.4](03-hermes-ha.md)）：
   `homeassistant` 插件是 `kind: platform`（平台插件），**不走 workspace，不触发 uv 依赖重解**。
   只有 **workspace 类插件**才会踩那个坑。
2. **为什么插件工具集不会因启动时序问题丢**：
   `get_plugin_toolset_keys_nowait()` 有**持久化注册表** —— 即使后台的插件发现线程还在跑，
   也能用上一次的结果，不会出现"插件工具集时有时无"。

## 6.4 方案 B：开启 Tool Search（渐进式披露）

若必须保留较多工具，开启 Tool Search，让非核心工具按需加载：

```yaml
tools:
  tool_search:
    enabled: on
    defer:
      - browser
      - kanban
      - image_generate
      - spotify
      - delegation
      - code_execution
      - session_search
```

> 代价：会多一次「查工具 → 加载 schema」的往返。
> 对**纯控家**场景，方案 A 更直接；工具确实多才用 B。

## 6.5 方案 C：精简系统提示 / 记忆

基础请求就有 1.4 万 token，除了工具 schema，还可能来自：

- 过长的 `SOUL.md` / 人格设定
- 大量 `MEMORY.md` 记忆条目
- 启用的 skills

```bash
hermes skills list       # 看加载了多少技能
ls ~/.hermes/ | head     # 看有哪些配置文件
```

建议：把与「控家」无关的技能 / 记忆精简掉，**或为语音场景单独建一个精简 profile**。

## 6.6 方案 D：家庭端侧的配合优化

1. **关闭流式响应**：`streamResponse: false`
   - 实测流式反而更慢（36s vs 23s），且会触发 MiGPT 解析崩溃
2. **强制简短回答**：在角色提示词里要求「一次工具调用后立即回答，不超过 20 字」，减少 completion token 与工具往返
   - 后来放宽为「中文口语化、自然简洁，两句话以内」，兼顾体验
3. **避免列举全部设备**：让 Hermes 需要时**只查目标设备**，不要 `ha_list_entities` 拉全部 169 个实体

## 6.7 方案 E：模型侧

- 用**轻量快速**模型承担语音问答（本机用的是 flash 级小模型）
- **关闭推理（reasoning）** —— 语音场景不需要长思考，开了只会更慢
- 确认所选 provider 到国内网络稳定，不稳定就换国内可达的节点

## 6.8 完成标准

- [ ] `/v1/toolsets` 显示 api_server 平台工具数大幅减少（目标 ≤ 8）
- [ ] 「客厅台灯开着吗」耗时降到 **≤ 10s**
- [ ] 家庭端小爱音箱实测响应明显变快


---

# 07 · 会话记忆（按天）与上下文压缩

这一篇解决两个问题：

1. MiGPT 默认**没有历史**，无法上下文指代 → 用会话头做「当天记忆」
2. 同一会话历史**无限累积**、越聊越慢 → 开 Hermes 的上下文压缩

## 7.0 先分清：「记忆」有两层含义，别混

| 你想要的效果 | 靠什么 | 谁来实现 |
|---|---|---|
| **跨会话长期事实**（如「我记得你偏好 26 度」）| `memory` 工具 + `MEMORY.md` / `USER.md` | ✅ **Hermes 侧**，已启用（`memory_enabled: true`，有字符上限）|
| **短期上下文**（刚问过温度，接着问「那湿度呢」）| 请求里带 `session_id` / `previous_response_id` | ❌ **客户端侧**，Hermes 无法单方面实现 |

**关键结论**：第二层**必须由客户端**（MiGPT / 小爱侧）每次都带上这些字段。

Hermes 侧已有的服务端机制：

- `POST /v1/responses` 支持 `previous_response_id` —— 服务端留存**完整会话链**（含工具调用与结果）
- `X-Hermes-Session-Key` —— 供多用户前端传一个**稳定的长期记忆 scope**

> **前提是客户端每次都带这些字段**。所以"为什么 AI 不记得上一句"这类问题，
> 在改 Hermes 之前先确认客户端到底发了什么。

## 7.1 问题一：MiGPT 原版每个请求只有当前一句

MiGPT 原版把语音转成一次性的 OpenAI 请求，**不携带任何历史**，所以：

- 无法上下文指代（「那个也关掉」→ 不知道"那个"是什么）
- 每轮都是全新对话

### 解法：给请求加固定会话头，按天轮转

在 MiGPT 的 OpenAI 客户端上添加默认请求头：

```js
defaultHeaders: { "X-Hermes-Session-Id": "xiaoai-YYYYMMDD" }
```

Hermes 服务端据此维护**该会话的历史与记忆**。

**要点**：

- 按**东八区日期**轮转 —— 当天共享记忆，跨天自动开新会话
- 可用环境变量覆盖（例：`XIAOAI_SESSION_ID`），便于临时隔离或调试

**实测**：

```
轮1：「记住看书就把台灯调到最亮」
轮2：「我待会要看书」        → 正确把台灯调亮 ✅
```

> 这个改动同样是**打进 MiGPT 代码的补丁**，做法与 [05 篇 §5.8](05-migpt-xiaoai.md) 的可选链补丁一致，
> 建议合并成一个补丁脚本，容器重建后自动重打。

## 7.2 问题二：同一会话内历史无限累积

家庭端实测（同一会话连续问）：

| 同一会话内轮次 | prompt token | 耗时 |
|---|---|---|
| 第 1 轮 | 4,356 | 6.7s |
| 第 2 轮 | 33,066 | 26.2s |
| 稍后再问 | 40,497 | 14.9s |

历史越长 → 模型输入越大 → 越慢。**开压缩后，历史超过阈值会被自动总结精简，速度恢复稳定。**

## 7.3 解法：开启并调优上下文压缩

编辑 `~/.hermes/config.yaml`，调整 `compression` 段（Hermes 默认已 `enabled: true`，重点是调参数）：

```yaml
compression:
  enabled: true
  threshold: 0.35                  # 达到上下文窗口 35% 就压缩（默认 0.50，调低更积极）
  protect_last_n: 12               # 至少保留最近 12 条不压缩（默认 20，控家场景可小些）
  in_place: true                   # 原地压缩，不轮换 session id（保住"当天记忆"连续性）
  idle_compact_after_seconds: 900  # 闲置 15 分钟后自动压缩一次（默认 0=关）
  proactive_prune_tokens: 48000    # 无 LLM 的确定性裁剪：历史超 48k 时裁掉旧工具结果（默认 0=关）
```

**参数怎么理解**：

- `threshold` 调低 → 更早压缩，响应更平稳
- `proactive_prune_tokens` 对**"工具结果很多"**的控家场景特别有效
  （HA 的实体列表 / 状态查询是主要膨胀源）
- `in_place: true` 保证压缩不换 session id，家庭端"当天记忆"不会断

### 可选：用更便宜的模型做压缩

```yaml
auxiliary:
  compression:
    model: ""        # 留空 = 用主模型；可填一个更小更快的模型
```

## 7.4 生效方式

```bash
hermes config edit       # 编辑保存
hermes gateway restart   # 保险起见重启（见 03 篇 §3.6：必须从网关外的 shell 执行）
```

> **官方说明**：编辑 `compression.*` 或 `model.context_length`，**运行中的 gateway 下一条消息即可生效，无需重启**。
> 只有 **API key 与工具配置**才需要重启。

## 7.5 验证：观察 prompt_tokens 是否还在线性增长

```bash
SID="xiaoai-$(date +%Y%m%d)"

curl -s http://<HERMES_TS_IP>:8642/v1/chat/completions \
  -H "Authorization: Bearer <API_SERVER_KEY>" -H "Content-Type: application/json" \
  -H "X-Hermes-Session-Id: $SID" \
  -d '{"model":"hermes-agent","messages":[{"role":"user","content":"你好，记住我偏好26度"}]}' \
  | python3 -c "import sys,json; print('prompt tokens:', json.load(sys.stdin).get('usage',{}).get('prompt_tokens'))"
```

连续问几次，看 `prompt_tokens`：

- **开压缩前**：线性增长
- **开压缩后**：稳定在某个上限附近

## 7.6 完成标准

- [ ] `config.yaml` 里 `compression.enabled: true` 且调低于默认的 `threshold`
- [ ] 同一会话连续问 5 次，prompt token **不再无限增长**（稳定在阈值附近）
- [ ] 家庭端小爱音箱同一会话内连续对话，**速度保持稳定**
- [ ] 当天对话**仍有记忆**（压缩是"总结"，不是"清空"）


---

# 08 · 踩坑总表

> 症状 → 原因 → 解法。**出问题先扫这一页**，再跳对应文档。

## 8.1 家庭机环境（Docker / WSL）

| 症状 | 原因 | 解法 |
|---|---|---|
| `wsl --install` 报 **403 已禁止** | 微软 CDN 被墙 | `winget install --id Microsoft.WSL --exact`（从 GitHub 拉 MSIX，绕开 CDN），**需管理员** |
| `winget` 报 **0x80073d28** | 权限不足 | 用**管理员** PowerShell 跑 |
| 新会话里 `docker` 命令找不到 | PATH 未刷新 | 把 `C:\Program Files\Docker\Docker\resources\bin` 加进用户 PATH |
| 拉镜像超时 / 极慢 | ghcr.io / Docker Hub 直连被限速 | 配 `daemon.json` 镜像加速器；拉取用 `ghcr.chenby.cn` 或 `docker.1ms.run`（见 [02 篇](02-home-assistant.md)）|
| 拉到的 HA 是两年前的版本 | 某些国内镜像的 `stable` 标签缓存过旧 | 指定明确版本号，或用 `ghcr.chenby.cn` |
| `api.github.com` 403 但 `github.com` 200 | 正常现象 | 不影响下载 release 文件 |

## 8.2 Home Assistant / 设备接入

| 症状 | 原因 | 解法 |
|---|---|---|
| HA 连不上小米云 | 多数不是网络问题 | 检查集成版本是否过旧 / 是否装了 Xiaomi Miot Auto |
| 海尔集成登录失败 | 装错了集成 | 别用 `gvigroux/hon`（海外 hOn 平台）；国内用 `banto6/haier` |
| 问「多少度」数值明显不对 | 温湿度计原始单位是**华氏度** | 换算 `°C = (°F − 32) × 5/9`；或直接取属性里的摄氏值 |
| 找不到冰箱总开关 | 冰箱本来就没有总电源开关 | 看 temperature 传感器；`switch.bing_xiang_*_su_dong/su_leng/zhi_neng/jia_ri` 是速冻/速冷/智能/假日等**子功能** |
| 开了插座但设备没通电 | 开的是**子开关**不是主开关 | 主开关是 `switch.<设备>_switch`；`_on_2/_on_3/_on_4`、`_physical_control_locked`、`_switch_status` 都是子功能/状态位 |
| 想控空调找不到合适开关 | 海尔挂式空调有约 30 个子功能开关 | 控空调请用 `climate.gua_shi_kong_diao_climate`（climate 域），不要用那一堆 switch |

## 8.3 云端 Hermes

| 症状 | 原因 | 解法 |
|---|---|---|
| `plugins enable` 报 uv **"has no publish time"** | 报错包全是**核心依赖**；根因是国内 pip 镜像**无 `upload-time`**，被 14 天供应链闸门判为"太新"→ 无解 | `PIP_CONFIG_FILE=/dev/null hermes plugins enable <name>`。**换任何插件都会踩同一个坑**。详见 [03 篇 §3.4](03-hermes-ha.md) |
| 手写 `config.yaml` 的 `plugins.enabled` 后插件被自动禁用 | 插件加载后被网关复检（`the dependency environment no longer builds with it`）| 不要手改，用 `hermes plugins enable` |
| 写进 systemd unit 的 `Environment=` 被抹掉 | Hermes 会重新生成自己的 unit 文件 | 改用 **drop-in**：`~/.config/systemd/user/hermes-gateway.service.d/override.conf` |
| 会话里执行 `hermes gateway restart` 被拒 | 安全护栏：网关内重启会 SIGTERM 掉自己 | **必须由人在网关外的 shell 执行**；`systemd-run` 延迟调度也会被拦 |
| `.env` 改完不生效 | `.env` 只在进程启动时读取 | 重启 Hermes / 网关 |
| `hermes tools list` 里看不到 `ha_*` | 开了 Tool Search，工具被延后加载 | **正常现象**，先 `tool_search` 检索再 `tool_call` |
| 8642 端口连不上 | API server 默认只绑 `127.0.0.1` | `API_SERVER_HOST` 改成 Tailscale IP（或 `0.0.0.0`）后重启，见 [04 篇](04-hermes-api-server.md) |
| **任何 key 都 401**（含假 key/截断/大写）| **鉴权层 fail-closed**：请求落到命名 profile 后 `API_SERVER_KEY` 从另一份不含该键的 mapping 读 → 取不到就返回空串 → 所有 Bearer 都过不了 | 见 [04 篇 §4.9](04-hermes-api-server.md)。判断口诀：**不同 key 返回一模一样的 401 ⇒ 问题不在 key 值** |
| `/health` 正常但其他端点 401 | 同上：`/health` 免鉴权，不经过这条路径 | 同上 |
| `/health` 严格等值判断失败 | 实际返回**三个**字段：`status`/`platform`/`version` | 用**包含匹配**，别写严格等于 |
| 请求体里的 `"model"` 不生效 | 裸 `model` 无 `provider` 时被忽略，回落网关默认模型 | 需设 `gateway.platforms.api_server.direct_model_requests: true`（不影响功能）|
| 响应 23–36 秒 | api_server 默认挂 **42 个工具**，prompt 1.4 万起步、查设备冲到 6–7 万 token | 精简工具集到 7 个，见 [06 篇](06-performance.md) |
| 同一会话越聊越慢 | 会话历史无限累积 | 开上下文压缩，见 [07 篇](07-session-memory.md) |

## 8.4 MiGPT / 小爱音箱

| 症状 | 原因 | 解法 |
|---|---|---|
| 镜像拉不到 / 容器起不来 | 网上文章写的 `lmk123/mi-gpt-gui` 和端口 `3210` **不存在** | 真实镜像 **`lmk123/migpt-server`**、端口 **36592** |
| 报「找不到设备」 | 填的是米家里的设备名，Mina/MIoT 看到的名称可能不一致 | **改填数字 did**（去米家复制设备名没用）|
| 登录报 **70016** | 小米 ID 填错了（填成手机号 / 邮箱）| 填「个人信息」里的**小米 ID** |
| 日志报「触发小米账号异地登录安全验证机制」→ `初始化 Mi Services 失败` | 小米对容器 IP 异地登录做风控 | 用 **passToken** 写入 `.mi.json` 绕过，见 [05 篇 §5.6](05-migpt-xiaoai.md) |
| 说几个字就播报「我说完了」 | 该型号不支持连续对话 / 或流式导致的解析问题 | `streamResponse` 改 `false` |
| Hermes 调工具时 MiGPT **崩溃** | Hermes 发 `event: hermes.tool.progress` 事件帧（无 `choices` 字段），MiGPT 读 `chunk.choices[0]` 抛 `TypeError` | 打补丁改成 `chunk.choices?.[0]`（可选链）|
| 容器重启后 AI 服务不说话 | MiGPT 跑在 GUI 的**子进程**里，容器重启不自动恢复 | 守护脚本调 `POST /api/default/start` 重新拉起，见 [05 篇 §5.9](05-migpt-xiaoai.md) |
| 每轮都不记得上一句 | MiGPT 原版不带历史 | 加 `X-Hermes-Session-Id` 请求头，见 [07 篇](07-session-memory.md) |
| 笔记本一睡眠就断连 | 系统睡眠导致容器停 | 睡眠 / 休眠 / 硬盘超时设为**永不**（屏幕可关）|

## 8.5 一句话总结

按"最坑"排序：

1. **`plugins enable` 的 uv 报错与插件无关** —— 是国内 pip 镜像没有 `upload-time` 撞上供应链新鲜度闸门。一行 `PIP_CONFIG_FILE=/dev/null` 解决。
2. **API Server "所有 key 都 401" 不是 key 的问题** —— 是鉴权层拿不到凭据就 **fail-closed**。
   判断口诀：拿 3–4 个差异极大的 key 打一次，**结果完全一致就说明比较没走到值比较**。
3. **小爱音箱要填数字 did，不是设备名**；异地登录要用 passToken。
4. **慢的根源是工具集太大**（38→7），不是网络也不是模型。**别给 API Server 开 `terminal`。**
5. **网关重启必须从网关外执行**（护栏会拦住自己重启自己）。
6. **家庭机不能睡**，且 MiGPT 子进程重启后要脚本重新拉起。
7. **`hermes config set` 的备份在 `~/.hermes/backups/config/`**，不在根目录 —— 找备份要 `find`。


---

# 09 · 设备实体参考（米家 / 海尔）

> 用 HA 时最容易踩的不是命令，而是**实体 ID 猜错**。这一页给结构，不给具体值 ——
> 你机器上的 4 位哈希不同，请用 `ha_list_entities` 拉自己的列表。

## 9.1 怎么拿自己的实体列表

```bash
# 方式一：走 Hermes 工具
hermes tools list                      # 确认 homeassistant 工具集在
# 然后在对话里说「列出我家所有设备」，或直接调：
#   ha_list_entities(domain="light")
#   ha_list_entities(domain="climate")

# 方式二：直连 HA REST
curl -s -H "Authorization: Bearer <HA_TOKEN>" \
  http://<HOME_TS_IP>:8123/api/states \
  | python3 -c "import sys,json;[print(s['entity_id']) for s in json.load(sys.stdin)]"
```

## 9.2 实体 ID 的构成规律

米家 / 海尔接入后，实体 ID 一般是：

```
<domain>.<品牌或型号>_<4位设备哈希>_<功能>
```

- `domain`：`light` / `switch` / `climate` / `sensor` / `media_player` …
- `4位设备哈希`：**每台设备不同**，由设备标识推导，无法猜
- 同一个物理设备的**指示灯**和**主开关**是两个不同实体

常见形态举例：

| 中文名 | domain | entity_id 结构 |
|---|---|---|
| Philips 米家台灯 | light | `light.philips_sread1_<hash>_light` |
| 米家显示器挂灯 2 | light | `light.xiaomi_bar2_<hash>_light` |
| 米家空调（插座型）| climate | `climate.lumi_mcn02_<hash>_air_conditioner` |
| 海尔挂式空调 | climate | `climate.gua_shi_kong_diao_climate` |
| 小爱音箱（L15A 类）| media_player | `media_player.xiaomi_l15a_<hash>_play_control` |
| 电脑插座（主开关）| switch | `switch.cuco_v3_<hash>_switch` |
| 热水器插座（主开关）| switch | `switch.cuco_cp1d_<hash>_switch` |
| 温湿度计-温度 | sensor | `sensor.miaomiaoce_t2_<hash>_temperature` |
| 温湿度计-湿度 | sensor | `sensor.miaomiaoce_t2_<hash>_relative_humidity` |
| 温湿度计-电量 | sensor | `sensor.miaomiaoce_t2_<hash>_battery_level` |
| 海尔冰箱-冷藏/冷冻 | sensor | `sensor.bing_xiang_<型号>_leng_cang_...` / `..._leng_dong_...` |

> `gua_shi_kong_diao`（拼音"挂式空调"）、`bing_xiang`（拼音"冰箱"）这类**中文拼音域名**来自集成作者的中文命名映射，不含设备哈希。

## 9.3 三个必须记住的陷阱

### ① 温度传感器的原始单位可能是华氏度

部分米家温湿度计上报 `°F`。用户问「多少度」时直接播报会错得离谱。

```
°C = (°F − 32) × 5/9        例：81.5 °F → 27.5 °C
```

**省事做法**：该实体的属性里通常自带摄氏值（形如 `temperature-2-1: 27.5`），可直接取。

**让 AI 记住**：在角色提示词里明确写「温湿度计温度是华氏度，回答前换算成摄氏度」。

### ② 冰箱没有总电源开关

`switch.bing_xiang_*_su_dong`（速冻）`_su_leng`（速冷）`_zhi_neng`（智能）`_jia_ri`（假日）`_ren_gong_zhi_neng`（人工智）等**都是子功能**，不是总开关。

**看冰箱状态请走 temperature 传感器**，别指望开关。

### ③ 插座设备的子开关 ≠ 主开关

以某插座为例：

- ✅ **主开关**：`switch.cuco_v3_<hash>_switch`
- ❌ 子功能 / 状态位：`_on_2`、`_on_3`、`_on_4`、`_physical_control_locked`（童锁）、`_switch_status`
- 另外可能还有一个 `light.cuco_v3_<hash>_indicator_light`（**指示灯**，不是通电开关）

**症状**：你说"打开电脑插座"，AI 开了 `_on_2`，设备其实没通电。

**同理**：海尔挂式空调有约 **30 个子功能开关**（自清洁 / 新风 / PM2.5 / 除菌 / 语音 / 电子锁…）。
**控制空调请用 `climate.gua_shi_kong_diao_climate`（climate 域）**，不要用那一堆 switch。

## 9.4 建议：把常用实体写进角色提示词

169 个实体不要全塞给模型（会把 prompt 撑爆，见 [06 篇](06-performance.md)）。
建议在 Hermes 的角色提示词 / 记忆里，只写清**常用的十来个**「中文名 → entity_id」映射，
并明确"**需要时只查目标设备，不要列全部**"。

示例片段：

```text
家里的常用设备（entity_id 已核对）：
- 台灯：light.philips_sread1_<hash>_light
- 电脑插座（主开关）：switch.cuco_v3_<hash>_switch
- 海尔挂式空调：climate.gua_shi_kong_diao_climate
- 温湿度计：sensor.miaomiaoce_t2_<hash>_temperature（华氏度，回答前换算）

规则：
1. 温湿度计温度是华氏度，先换算成摄氏度再回答
2. 冰箱只看温度传感器，没有总开关
3. 插座请用 _switch 主开关，不要用 _on_2 / _indicator_light
4. 只查目标设备，不要调用 ha_list_entities 列全部设备
5. 中文口语化，两句话以内
```


---

# scripts · 脚本说明

> Windows 侧（家庭机）的部署与守护脚本，以及一个仓库维护脚本。

## ⚠️ 先读这段

1. **这些脚本来自一套真实的部署环境，但只在那台机器上验证过**（Windows 11 + PowerShell 5.1 + Docker Desktop）。
   换机器可能因为 Docker Desktop 安装路径、`node` 是否在 PATH、中文编码等差异需要微调。
   **请先读一遍再执行**，不要盲目双击。
2. **MiGPT 相关脚本（04 起）属于一条「未打通并已放弃」的路线** ——
   MiGPT 侧能跑起来，但云端 Hermes 的 API Server 存在未解决的鉴权 401，
   请求到不了 Hermes。详见 [docs/05-migpt-xiaoai.md](../docs/05-migpt-xiaoai.md) 与 [docs/04-hermes-api-server.md](../docs/04-hermes-api-server.md)。
   **HA 与 Tailscale 相关脚本（01/02/03/05）是已验证可用的部分。**
3. 脚本里没有写任何凭据：passToken / API Key / 令牌都靠**命令行参数**或你在 GUI 里填。
   请**不要**把自己的凭据写进这些脚本再提交到公开仓库。

## 执行方式

```powershell
# 建议：先放开执行策略（只对当前会话生效）
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 按顺序执行
.\01-check.ps1              # 环境自检
.\02-install-docker.ps1     # 装并启动 Docker Desktop
.\03-run-ha.ps1             # 起 Home Assistant
.\05-install-tailscale.ps1  # 装 Tailscale
.\04-run-migpt.ps1          # 起 MiGPT GUI（属于已放弃路线）
```

> 若提示脚本被禁止运行，用：
> `powershell -ExecutionPolicy Bypass -File .\01-check.ps1`

## 脚本清单

### 部署（顺序执行）

| 脚本 | 作用 | 关键点 |
|---|---|---|
| `01-check.ps1` | 环境自检：系统 / 重启待处理 / WSL / Docker / 端口占用 | 只读，不改任何东西 |
| `02-install-docker.ps1` | 安装并启动 Docker Desktop，等引擎就绪（最多 5 分钟）| 装完会跑 `hello-world` 验证 |
| `03-run-ha.ps1` | 起 Home Assistant 容器（数据在 `%USERPROFILE%\ha-data`）| **固定版本号**，不用 `:stable`（见下方说明）|
| `04-run-migpt.ps1` | 起 MiGPT GUI 容器（数据在 `%USERPROFILE%\migpt-data`）| 镜像 `lmk123/migpt-server`、端口 **36592** |
| `05-install-tailscale.ps1` | 装 Tailscale 并登录，打印本机 100.x IP | 云端要用**同一账号** |

### MiGPT 运行期辅助（属于已放弃路线，留作参考）

| 脚本 | 作用 |
|---|---|
| `start-xiaoai.ps1` | **一键启动**：Docker → HA → MiGPT；`-Status` 只看状态 |
| `autostart-xiaoai.ps1` | **开机守护**：等引擎就绪 → 确保容器运行 → 驱动 MiGPT 子进程 |
| `patch-and-start-migpt.ps1` | 给容器内 MiGPT 打补丁后启动（供守护脚本调用）|
| `apply-migpt-patch.mjs` | **补丁本体**（幂等，可重复执行）：① 流式解析容错 ② 会话记忆按天轮转 |
| `start-migpt.mjs` | 触发 MiGPT 子进程启动（容器重启后不会自动恢复，必须重新触发）|
| `retry-migpt.ps1` | 小米授权后自动重试登录（默认最多 2 小时、每 10 分钟一次）|
| `set-migpt-passtoken.ps1` | 用 passToken 绕过小米异地登录风控 |

### 仓库维护

| 脚本 | 作用 |
|---|---|
| `build-full.sh` | 把 `README.md` + `docs/*.md` 合并成单文件全本 `tutorial-full.md` |

## 两个设计细节（值得抄的点）

### 1. 自动定位 `docker.exe`

新装的 Docker Desktop 常常"这个命令窗口里 `docker` 还找不到"（PATH 未刷新）。
所以每个脚本都这么写：

```powershell
$dockerExe = "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
if (-not (Test-Path $dockerExe)) { $dockerExe = "docker" }
function docker { & $dockerExe @args }
```

### 2. 用 `$PSScriptRoot` 而不是绝对路径

脚本之间互相调用时，**不要硬编码** `C:\Users\<你>\Desktop\...`，
用 `$PSScriptRoot` 定位同目录的同伴脚本：

```powershell
$starter = Join-Path $PSScriptRoot "start-migpt.mjs"
```

这样换目录、换机器都能用，也不会把自己的用户名泄露出去。

## 关于 `03-run-ha.ps1` 的版本号

脚本里写的是**固定版本**：

```powershell
$haTag = "2026.9.3"
$haImage = "ghcr.io/home-assistant/home-assistant:$haTag"
```

**别改回 `:stable`** —— 部分国内镜像的 `stable` 标签缓存停留在 2024.7.1，
拉 `:stable` 会拿到两年前的版本。要升级就改 `$haTag`。

国内拉取慢的话，把 `ghcr.io` 换成 `ghcr.chenby.cn`（实测 **111.8 Mbps**，见 [docs/02](../docs/02-home-assistant.md)）。

## MiGPT 补丁到底改了什么

`apply-migpt-patch.mjs` 对容器内的
`/usr/local/lib/node_modules/migpt-server/node_modules/mi-gpt/dist/index.js`
做两处幂等替换：

1. **流式解析容错**：`chunk.choices[0]` → `chunk.choices?.[0]`
   Hermes 触发工具调用时会发 `event: hermes.tool.progress` 事件帧（**没有 `choices` 字段**），
   MiGPT 直接取下标会抛 `TypeError` 并崩溃。可选链让它安全跳过非标准帧。
2. **会话记忆（按天轮转）**：给 OpenAI 客户端加
   `defaultHeaders: { "X-Hermes-Session-Id": "xiaoai-YYYYMMDD" }`
   让 Hermes 服务端按会话维护历史。按**东八区日期**轮转 —— 当天共享记忆，跨天自动开新会话，
   避免历史无限累积越聊越慢。可用环境变量 `XIAOAI_SESSION_ID` 覆盖。

首次执行会备份原文件为 `index.js.bak`。

