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
