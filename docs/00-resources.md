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
