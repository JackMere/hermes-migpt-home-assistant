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
