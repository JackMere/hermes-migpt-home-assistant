# 01-check.ps1 — 环境自检：Docker / WSL / 系统 / 端口
$ErrorActionPreference = "SilentlyContinue"

# 自动定位 docker.exe（新会话可能还没刷新 PATH）
$dockerExe = "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
if (-not (Test-Path $dockerExe)) { $dockerExe = "docker" }
function docker { & $dockerExe @args }

function Section($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

Section "系统"
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor
Write-Host ("OS: {0} ({1})" -f $os.Caption, $os.OSArchitecture)
Write-Host ("内存: {0} GB 可用 / {1} GB 总" -f [math]::Round($os.FreePhysicalMemory/1MB,1), [math]::Round($os.TotalVisibleMemorySize/1MB,1))
Write-Host ("CPU: {0} ({1} 核)" -f $cpu.Name, $cpu.NumberOfLogicalProcessors)
Write-Host ("HypervisorPresent: {0}" -f (Get-CimInstance Win32_ComputerSystem).HypervisorPresent)

Section "重启是否待处理"
$pending = (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") -or (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired")
Write-Host ("RebootPending: {0}" -f $pending) -ForegroundColor ($(if ($pending) {"Yellow"} else {"Green"}))

Section "WSL"
wsl --status 2>&1 | Out-Host
wsl -l -v 2>&1 | Out-Host

Section "Docker"
if (Get-Command docker -ErrorAction SilentlyContinue) {
  docker --version 2>&1 | Out-Host
  docker info --format "Server: {{.ServerVersion}} | 容器数: {{.Containers}}" 2>&1 | Out-Host
  Write-Host "当前容器:"
  docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>&1 | Out-Host
} else {
  Write-Host "未安装 Docker（重启后用 02-install-docker.ps1 安装）" -ForegroundColor Yellow
}

Section "端口占用 (8123=HA, 36592=MiGPT)"
foreach ($p in 8123, 36592) {
  $c = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
  if ($c) { Write-Host ("{0}: 已被占用" -f $p) -ForegroundColor Yellow }
  else { Write-Host ("{0}: 空闲" -f $p) -ForegroundColor Green }
}
