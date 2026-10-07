# 03-run-ha.ps1 — 启动 Home Assistant
# 数据目录：%USERPROFILE%\ha-data
$ErrorActionPreference = "Stop"

# 自动定位 docker.exe（新会话可能还没刷新 PATH）
$dockerExe = "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
if (-not (Test-Path $dockerExe)) { $dockerExe = "docker" }
function docker { & $dockerExe @args }

$dataDir = Join-Path $env:USERPROFILE "ha-data"
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

Write-Host ("数据目录: {0}" -f $dataDir) -ForegroundColor Cyan

# 已存在则先移除旧容器（数据保留在磁盘上）
$exists = docker ps -a --filter "name=^/ha$" --format "{{.Names}}"
if ($exists) {
  Write-Host "发现已存在的 ha 容器，移除并重建（数据不丢）..."
  docker rm -f ha | Out-Null
}

# 固定版本号：不要用 :stable —— 部分国内镜像的 stable 标签缓存过旧（实测停在 2024.7.1）
$haTag = "2026.9.3"
# 国内加速：把 ghcr.io 换成 ghcr.chenby.cn（实测 111.8 Mbps，见 docs/02-home-assistant.md）
$haImage = "ghcr.io/home-assistant/home-assistant:$haTag"

Write-Host "拉取并启动 Home Assistant ($haImage)..."
docker run -d --name ha --restart unless-stopped `
  -p 8123:8123 `
  -v "${dataDir}:/config" `
  -e TZ=Asia/Shanghai `
  $haImage

Start-Sleep -Seconds 5
docker ps --filter "name=^/ha$" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
Write-Host "`n打开 http://localhost:8123 完成初始化向导。" -ForegroundColor Green
Write-Host "若拉取镜像很慢，可先配置 Docker 镜像加速器（设置 → Docker Engine）。" -ForegroundColor Yellow
