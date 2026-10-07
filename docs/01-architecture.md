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
