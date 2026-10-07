# ============================================================
#  XiaoAI 开机守护：等待 Docker 引擎就绪，确保 ha / migpt-server 运行
#  由计划任务「XiaoAI-HomeHub」在开机时调用（无需管理员）
# ============================================================
$ErrorActionPreference = "Continue"
$log = "$env:USERPROFILE\migpt-data\autostart.log"
function Log($m) {
  $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m
  try { Add-Content -Path $log -Value $line -Encoding UTF8 } catch {}
}

$DockerExe = "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
if (-not (Test-Path $DockerExe)) { $DockerExe = "docker" }

Log "---- 开机守护启动 ----"

# 1. 拉起 Docker Desktop
$dd = @(
  "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
  "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not (Get-Process "Docker Desktop" -ErrorAction SilentlyContinue) -and $dd) {
  Start-Process $dd
  Log "已启动 Docker Desktop"
}

# 2. 等待引擎就绪（最多 8 分钟）
$ok = $false
for ($i = 1; $i -le 96; $i++) {
  & $DockerExe info *> $null
  if ($LASTEXITCODE -eq 0) { $ok = $true; break }
  Start-Sleep -Seconds 5
}
Log ("Docker 引擎就绪: " + $ok)
if (-not $ok) { Log "引擎未就绪，退出"; exit 1 }

# 3. 确保两个容器运行
foreach ($c in "ha", "migpt-server") {
  $state = & $DockerExe inspect -f "{{.State.Running}}" $c 2>$null
  if ($state -ne "true") {
    & $DockerExe start $c *> $null
    Log ("已启动容器: " + $c + "  (之前状态: " + $state + ")")
  } else {
    Log ("容器已在运行: " + $c)
  }
}

# 4. 等待 MiGPT GUI 就绪，并驱动 MiGPT 启动
#    （mi-gpt 跑在 GUI 的子进程里，容器重启后需要重新触发 /api/default/start）
$migptReady = $false
for ($i = 1; $i -le 30; $i++) {
  try {
    $r = Invoke-WebRequest -Uri "http://localhost:36592/api/default" -TimeoutSec 5 -UseBasicParsing
    if ($r.StatusCode -eq 200) { $migptReady = $true; break }
  } catch {}
  Start-Sleep -Seconds 3
}
Log ("MiGPT GUI 就绪: " + $migptReady)

if ($migptReady) {
  # 用相对本脚本的路径，避免硬编码绝对路径
  $patcher = Join-Path $PSScriptRoot "patch-and-start-migpt.ps1"
  if (Test-Path $patcher) {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $patcher 2>&1 | Out-String
    Log ("patch-and-start-migpt 输出: " + ($out -replace "\s+", " ").Trim())
  } else {
    Log ("找不到 patch-and-start-migpt.ps1: " + $patcher)
  }
}

Log "---- 开机守护完成 ----"
