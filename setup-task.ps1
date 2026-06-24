# รันด้วย PowerShell Administrator
# ตั้ง Task Scheduler สำหรับ check-printers.ps1 ทุกวัน 08:30 น.

$TaskName = "PrinterChecker-Daily"
$ScriptPath = Join-Path $PSScriptRoot "check-printers.ps1"
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -NoProfile -File `"$ScriptPath`""
$Trigger = New-ScheduledTaskTrigger -Daily -At "08:30AM"
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force

Write-Host "Task '$TaskName' created! Runs daily at 08:30 AM"
