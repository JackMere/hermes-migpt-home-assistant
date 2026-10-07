# patch-and-start-migpt.ps1 — 给 MiGPT 打补丁后启动（供开机自启调用）
# 修复 Hermes tool.progress 事件帧导致的流式解析崩溃
$ErrorActionPreference = "Continue"
$bindir = "$env:ProgramFiles\Docker\Docker\resources\bin"
$docker = "$bindir\docker.exe"
$scripts = $PSScriptRoot
$patcher = Join-Path $scripts "apply-migpt-patch.mjs"
$starter = Join-Path $scripts "start-migpt.mjs"

# 1. 确保容器在运行
$state = & $docker inspect -f "{{.State.Running}}" migpt-server 2>$null
if ($state -ne "true") {
  Write-Host "启动 migpt-server 容器..."
  & $docker start migpt-server | Out-Null
  Start-Sleep -Seconds 5
}

# 2. 等待 GUI 就绪
for ($i = 1; $i -le 30; $i++) {
  try { $r = Invoke-WebRequest "http://localhost:36592/api/default" -TimeoutSec 5 -UseBasicParsing; if ($r.StatusCode -eq 200) { break } } catch {}
  Start-Sleep -Seconds 3
}

# 3. 打补丁（把脚本拷进容器执行）
if (Test-Path $patcher) {
  & $docker cp $patcher "migpt-server:/tmp/apply-migpt-patch.mjs" 2>$null | Out-Null
  $patchOut = & $docker exec migpt-server node /tmp/apply-migpt-patch.mjs 2>&1 | Out-String
  Write-Host ("补丁结果: " + $patchOut.Trim())
} else {
  Write-Host "找不到补丁脚本: $patcher"
}

# 4. 启动 MiGPT
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if ($node -and (Test-Path $starter)) {
  $out = & $node $starter 2>&1 | Out-String
  Write-Host ("MiGPT 启动: " + ($out -replace "\s+", " ").Trim())
}
