# set-migpt-passtoken.ps1 — 用 passToken 绕过小米异地登录验证（终极方案）
# 用法：powershell -ExecutionPolicy Bypass -File set-migpt-passtoken.ps1 -PassToken "V1:xxxxx..."
param(
  [Parameter(Mandatory=$true)][string]$PassToken
)
$ErrorActionPreference = "Stop"

# 写入宿主机挂载目录（容器内对应 /root/.migptgui/default/.mi.json）
$target = "$env:USERPROFILE\migpt-data\default\.mi.json"
$json = @{
  mina  = @{ pass = @{ passToken = $PassToken } }
  miiot = @{ pass = @{ passToken = $PassToken } }
} | ConvertTo-Json -Depth 5

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($target, $json, $utf8)
Write-Output ("已写入: " + $target)

# 重启 MiGPT 生效
$bindir = "$env:ProgramFiles\Docker\Docker\resources\bin"
$docker = "$bindir\docker.exe"
$node = (Get-Command node).Source
# 用相对本脚本的路径，避免硬编码绝对路径
$starter = Join-Path $PSScriptRoot "start-migpt.mjs"

try { Invoke-RestMethod -Uri "http://localhost:36592/api/default/stop" -Method Post -TimeoutSec 10 | Out-Null } catch {}
Start-Sleep -Seconds 5
& $node $starter 2>&1
Start-Sleep -Seconds 25
Write-Output "`n=== 最近日志 ==="
& $docker logs migpt-server --since 40s 2>&1 | Select-String -Pattern "登录|验证|Speaker|Mi Services|服务已启动|失败|成功|初始化" | Select-Object -Last 12
