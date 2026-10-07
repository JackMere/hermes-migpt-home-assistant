# 04-run-migpt.ps1 — 启动 MiGPT GUI（小爱音箱语音入口）
# 镜像：lmk123/migpt-server（不是 mi-gpt-gui！）端口：36592
$ErrorActionPreference = "Stop"

# 自动定位 docker.exe（新会话可能还没刷新 PATH）
$dockerExe = "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
if (-not (Test-Path $dockerExe)) { $dockerExe = "docker" }
function docker { & $dockerExe @args }

$dataDir = Join-Path $env:USERPROFILE "migpt-data"
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

Write-Host ("数据目录: {0}" -f $dataDir) -ForegroundColor Cyan

$exists = docker ps -a --filter "name=^/migpt-server$" --format "{{.Names}}"
if ($exists) {
  Write-Host "发现已存在的 migpt-server 容器，移除并重建（数据不丢）..."
  docker rm -f migpt-server | Out-Null
}

Write-Host "拉取并启动 MiGPT GUI..."
docker run -d --name migpt-server --restart unless-stopped `
  -p 36592:36592 `
  -v "${dataDir}:/root/.migptgui" `
  lmk123/migpt-server

Start-Sleep -Seconds 5
docker ps --filter "name=^/migpt-server$" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
Write-Host "`n打开 http://localhost:36592 进行配置（小米账号 / L15A / AI 接口）。" -ForegroundColor Green
Write-Host "查看日志： docker logs -f migpt-server" -ForegroundColor Yellow
