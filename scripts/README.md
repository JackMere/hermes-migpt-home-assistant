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
