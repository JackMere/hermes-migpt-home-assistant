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
