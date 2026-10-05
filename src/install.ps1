param([switch]$Uninstall)

$TaskName   = 'Razer Barracuda X autoswitch'
$InstallDir = "$env:LOCALAPPDATA\razer-barracuda-x-autoswitch"
$Script     = "$InstallDir\audio-switch.ps1"

# Stopping the task kills only conhost, the script itself keeps running
Unregister-ScheduledTask $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" |
    Where-Object CommandLine -match 'audio-switch\.ps1' |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

if ($Uninstall) {
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    'Uninstalled.'
    return
}

New-Item -ItemType Directory -Force $InstallDir | Out-Null
Copy-Item "$PSScriptRoot\audio-switch.ps1" $Script -Force

# conhost --headless: no console window flashing at logon
$action    = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Script`""
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
Register-ScheduledTask $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
Start-ScheduledTask $TaskName
'Installed and running. Turn the headphones on to check.'
