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
