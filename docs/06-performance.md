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
