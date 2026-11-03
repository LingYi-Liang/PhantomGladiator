param([int]$Port=8765,[string]$RuntimeDir='C:\Program Files (x86)\Steam\steamapps\common\PBZ\platform\steam\ue4ss\Mods\PhantomGladiator\Runtime')
$ErrorActionPreference='Stop'
$backendFile=Join-Path $PSScriptRoot 'backend.py'
$runtimeDir=$RuntimeDir
$connections=@(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
$owners=@($connections.OwningProcess | Sort-Object -Unique)
if ($owners.Count -ne 1) { throw '无法确认唯一的面板服务进程，未停止任何程序。' }
$panelPid=[int]$owners[0]
$panelProcess=Get-CimInstance Win32_Process -Filter ('ProcessId={0}' -f $panelPid)
if (-not $panelProcess -or -not $panelProcess.CommandLine.Contains($backendFile) -or $panelProcess.Name -ne 'python.exe') {
    throw '端口进程不是本项目的面板，未停止任何程序。'
}
$status=Invoke-RestMethod -Uri ('http://127.0.0.1:{0}/api/status' -f $Port)
if (@($status.queue | Where-Object {$_.status -in @('queued','pending')}).Count) { throw '还有游戏命令未完成，请稍后重试。' }
$pythonExe=$panelProcess.ExecutablePath
Stop-Process -Id $panelPid
Wait-Process -Id $panelPid -Timeout 10 -ErrorAction SilentlyContinue
$started=Start-Process -FilePath $pythonExe -ArgumentList @('-I',('"{0}"' -f $backendFile),'--runtime-dir',('"{0}"' -f $runtimeDir),'--port',$Port) -WorkingDirectory (Split-Path $PSScriptRoot -Parent) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $PSScriptRoot 'server.stdout.log') -RedirectStandardError (Join-Path $PSScriptRoot 'server.stderr.log') -PassThru
Write-Host ('面板已重新启动：PID {0}，http://127.0.0.1:{1}；未操作游戏进程。' -f $started.Id,$Port)
