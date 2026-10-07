# 05-install-tailscale.ps1 — 安装 Tailscale（让阿里云 Hermes 能访问家里 HA）
# 作用：笔记本和阿里云服务器加入同一虚拟内网，无需公网 IP、无需端口映射。
$ErrorActionPreference = "Stop"

Write-Host "=== 安装 Tailscale ===" -ForegroundColor Cyan
if (Get-Command tailscale -ErrorAction SilentlyContinue) {
  Write-Host "Tailscale 已安装："; tailscale version
} else {
  winget install --id Tailscale.Tailscale --exact --source winget --accept-package-agreements --accept-source-agreements
}

Write-Host "`n=== 启动并登录 ===" -ForegroundColor Cyan
Start-Process "tailscale" -ArgumentList "up" -ErrorAction SilentlyContinue
Write-Host "浏览器会打开登录页，用你的账号登录（阿里云那台机器要用【同一个账号】）。" -ForegroundColor Yellow

Write-Host "`n=== 查看本机 Tailscale IP（形如 100.x.y.z）===" -ForegroundColor Cyan
tailscale ip -4

Write-Host @"

下一步：
1. 在【阿里云服务器】上也装 Tailscale（Linux: curl -fsSL https://tailscale.com/install.sh | sh; sudo tailscale up），登录同一账号。
2. 用上面的 100.x.y.z:8123 作为 HASS_URL 填给 Hermes。
3. 验证： tailscale ping <另一台的IP>
"@ -ForegroundColor Green
