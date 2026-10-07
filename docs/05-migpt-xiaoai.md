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
