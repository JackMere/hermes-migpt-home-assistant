# retry-migpt.ps1 — 小米授权后自动重试登录
# 每 10 分钟重启一次 MiGPT，直到登录成功或超时（默认 2 小时）
param(
  [int]$MaxMinutes = 120,
  [int]$IntervalMinutes = 10
)
$ErrorActionPreference = "Continue"
$bindir = "$env:ProgramFiles\Docker\Docker\resources\bin"
$docker = "$bindir\docker.exe"
$node = (Get-Command node).Source
# 用相对本脚本的路径，避免硬编码绝对路径（换机器/换目录都能用）
$starter = Join-Path $PSScriptRoot "start-migpt.mjs"
$logfile = "$env:USERPROFILE\migpt-data\login-retry.log"

function Log($m) {
  $line = "{0}  {1}" -f (Get-Date -Format "HH:mm:ss"), $m
  Add-Content -Path $logfile -Value $line -Encoding UTF8
  Write-Host $line
}

Log "==== 开始自动重试（最多 $MaxMinutes 分钟，每 $IntervalMinutes 分钟一次）===="
$deadline = (Get-Date).AddMinutes($MaxMinutes)

while ((Get-Date) -lt $deadline) {
  # 重启 MiGPT
  try { Invoke-RestMethod -Uri "http://localhost:36592/api/default/stop" -Method Post -TimeoutSec 10 | Out-Null } catch {}
  Start-Sleep -Seconds 5
  try { & $node $starter *> $null } catch {}
  Start-Sleep -Seconds 30

  # 看最近 60 秒日志是否登录成功
  $log = & $docker logs migpt-server --since 60s 2>&1 | Out-String

  if ($log -match "初始化 Mi Services 失败" -or $log -match "小米账号登录失败") {
    Log "❌ 仍失败（等待小米同步中）"
  }
  elseif ($log -match "服务已启动|Mi Services.*成功|Speaker.*成功") {
    Log "✅ 登录成功！MiGPT 已就绪"
    Log "==== 重试结束（成功）===="
    exit 0
  }
  else {
    Log "… 状态未知，30 秒内未出现明确失败/成功标志"
  }

  Log "下次重试：$IntervalMinutes 分钟后"
  Start-Sleep -Seconds ($IntervalMinutes * 60)
}

Log "==== 重试结束（超时，建议改用 passToken 方案）===="
exit 1
