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
