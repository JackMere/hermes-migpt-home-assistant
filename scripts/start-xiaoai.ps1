# ============================================================
#  XiaoAI 家庭中枢 —— 一键启动 / 状态查看
#  启动所有服务：Docker 引擎 → Home Assistant → MiGPT GUI
#  用法：
#    powershell -ExecutionPolicy Bypass -File .\start-xiaoai.ps1
#    powershell -ExecutionPolicy Bypass -File .\start-xiaoai.ps1 -Status
# ============================================================
param([switch]$Status)

$ErrorActionPreference = "Continue"
$DockerExe = "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
if (-not (Test-Path $DockerExe)) { $DockerExe = "docker" }
function Dkr { & $DockerExe @args }

function Write-Head($t) {
  Write-Host ""
  Write-Host "============================================" -ForegroundColor DarkCyan
  Write-Host "  $t" -ForegroundColor Cyan
  Write-Host "============================================" -ForegroundColor DarkCyan
}

# ---------- 仅查看状态 ----------
if ($Status) {
  Write-Head "XiaoAI 服务状态"
  & $DockerExe info *> $null
  $engine = "未运行"
  if ($LASTEXITCODE -eq 0) { $engine = "运行中" }
  Write-Host ("Docker 引擎: " + $engine)
  & $DockerExe ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>&1
  foreach ($p in 8123, 36592) {
    $c = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
    $st = "未监听"
    if ($c) { $st = "监听中" }
    Write-Host ("端口 {0}: {1}" -f $p, $st)
  }
  Write-Host "`nHome Assistant: http://localhost:8123"
  Write-Host "MiGPT 控制面板:  http://localhost:36592"
  return
}

# ---------- 1. 确保 Docker Desktop 在运行 ----------
Write-Head "1/3  Docker 引擎"
$dd = @(
  "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
  "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not (Get-Process "Docker Desktop" -ErrorAction SilentlyContinue)) {
  if ($dd) { Write-Host "启动 Docker Desktop..." -ForegroundColor Yellow; Start-Process $dd }
  else { Write-Host "找不到 Docker Desktop.exe" -ForegroundColor Red }
} else {
  Write-Host "Docker Desktop 已在运行"
}

Write-Host "等待 Docker 引擎就绪..." -ForegroundColor Yellow
$ok = $false
for ($i = 1; $i -le 60; $i++) {
  & $DockerExe info *> $null
  if ($LASTEXITCODE -eq 0) { $ok = $true; break }
  Start-Sleep -Seconds 5
}
if (-not $ok) {
  Write-Host "Docker 引擎 5 分钟内未就绪，请手动打开 Docker Desktop 后重试。" -ForegroundColor Red
  exit 1
}
Write-Host "Docker 引擎就绪" -ForegroundColor Green

# ---------- 2. Home Assistant ----------
Write-Head "2/3  Home Assistant"
$haData = "$env:USERPROFILE\ha-data"
if (-not (Test-Path (Join-Path $haData ".storage"))) { New-Item -ItemType Directory -Force -Path $haData | Out-Null }
$exists = & $DockerExe ps -a --filter "name=^/ha$" --format "{{.Names}}"
if ($exists) {
  Write-Host "启动已存在的 ha 容器..."
  & $DockerExe start ha | Out-Null
} else {
  Write-Host "创建并启动 ha 容器..."
  & $DockerExe run -d --name ha --restart unless-stopped -p 8123:8123 -v "${haData}:/config" -e TZ=Asia/Shanghai ghcr.io/home-assistant/home-assistant:2026.9.3 | Out-Null
}

# ---------- 3. MiGPT GUI ----------
Write-Head "3/3  MiGPT GUI"
$mgData = "$env:USERPROFILE\migpt-data"
if (-not (Test-Path $mgData)) { New-Item -ItemType Directory -Force -Path $mgData | Out-Null }
$exists = & $DockerExe ps -a --filter "name=^/migpt-server$" --format "{{.Names}}"
if ($exists) {
  Write-Host "启动已存在的 migpt-server 容器..."
  & $DockerExe start migpt-server | Out-Null
} else {
  Write-Host "创建并启动 migpt-server 容器..."
  & $DockerExe run -d --name migpt-server --restart unless-stopped -p 36592:36592 -v "${mgData}:/root/.migptgui" lmk123/migpt-server | Out-Null
}

# ---------- 汇总 ----------
Write-Head "启动完成"
Start-Sleep -Seconds 8
& $DockerExe ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# ---------- 4. 驱动 MiGPT 子进程启动 ----------
$starter = Join-Path $PSScriptRoot "start-migpt.mjs"
if (Test-Path $starter) {
  Write-Host ""
  Write-Host "驱动 MiGPT 启动..." -ForegroundColor Yellow
  for ($i = 1; $i -le 20; $i++) {
    try { $r = Invoke-WebRequest "http://localhost:36592/api/default" -TimeoutSec 5 -UseBasicParsing; if ($r.StatusCode -eq 200) { break } } catch {}
    Start-Sleep -Seconds 3
  }
  $nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
  if ($nodeExe) {
    & $nodeExe $starter 2>&1 | ForEach-Object { Write-Host ("  " + $_) }
  } else {
    Write-Host "  未找到 node，跳过（可在 MiGPT 面板手动点启动）" -ForegroundColor Yellow
  }
}

Write-Host ""
Write-Host "Home Assistant:  http://localhost:8123" -ForegroundColor Green
Write-Host "MiGPT 控制面板:  http://localhost:36592" -ForegroundColor Green
Write-Host ""
Write-Host "查看状态: powershell -ExecutionPolicy Bypass -File .\start-xiaoai.ps1 -Status" -ForegroundColor DarkGray
