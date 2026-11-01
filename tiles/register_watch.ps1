# R2 안전선 감시 예약 작업 등록 — 로그온 시 + 지금 pythonw로 상주(창 없음), 죽으면 1분 뒤 재시작
$py = Join-Path (Split-Path (python -c "import sys;print(sys.executable)")) 'pythonw.exe'
$script = Join-Path $env:USERPROFILE 'Documents\garmin-instinct-map\tiles\r2guard.py'
$set = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1)
$trig = @((New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME), (New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(20)))
$action = New-ScheduledTaskAction -Execute $py -Argument "-I -X utf8 `"$script`" watch 30" -WorkingDirectory $env:USERPROFILE
Register-ScheduledTask -TaskName 'R2 안전선 감시' -Trigger $trig -Action $action -Settings $set -Description 'R2 장부가 안전선(70%)에 닿으면 R2 관련 프로세스 종료·잠금·클로대리 알림' -Force | Out-Null
Get-ScheduledTask -TaskName 'R2 안전선 감시' | Get-ScheduledTaskInfo | Select-Object TaskName, NextRunTime, LastTaskResult
