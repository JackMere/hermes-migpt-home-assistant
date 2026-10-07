# 02-install-docker.ps1 — 安装并启动 Docker Desktop
# 前提：已重启，且 WSL / 虚拟机平台已启用
$ErrorActionPreference = "Stop"

# 自动定位 docker.exe（新会话可能还没刷新 PATH）
$dockerExe = "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
if (-not (Test-Path $dockerExe)) { $dockerExe = "docker" }
function docker { & $dockerExe @args }

Write-Host "=== 安装 Docker Desktop ===" -ForegroundColor Cyan

if (Get-Command docker -ErrorAction SilentlyContinue) {
  Write-Host "Docker 已存在：" -NoNewline; docker --version
} else {
  winget install --id Docker.DockerDesktop --exact --source winget --accept-package-agreements --accept-source-agreements
}

Write-Host "`n=== 启动 Docker Desktop（首次启动较慢）===" -ForegroundColor Cyan
$dd = @(
  "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
  "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $dd) { throw "找不到 Docker Desktop.exe，安装可能未完成。" }
if (-not (Get-Process "Docker Desktop" -ErrorAction SilentlyContinue)) {
  Start-Process $dd
} else {
  Write-Host "Docker Desktop 已在运行"
}

Write-Host "`n等待 Docker 引擎就绪..."
$ok = $false
for ($i = 1; $i -le 60; $i++) {
  docker info *> $null
  if ($LASTEXITCODE -eq 0) { $ok = $true; break }
  Start-Sleep -Seconds 5
  Write-Host ("  等待中... {0}s" -f ($i*5))
}

if ($ok) {
  Write-Host "`nDocker 引擎已就绪 ✅" -ForegroundColor Green
  docker run --rm hello-world
} else {
  Write-Host "`nDocker 引擎仍未就绪。请手动打开 Docker Desktop 并完成初始化（可能需要同意条款 / 登录 WSL），然后重跑本脚本。" -ForegroundColor Yellow
}
