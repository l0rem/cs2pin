# Installs cs2pin for the signed-in user: copies cs2pin.exe next to this script to C:\Program Files\cs2pin
# and adds a logon task that starts it elevated (no UAC prompt). The task runs elevated, so the exe must sit
# where only admins can write; a user-writable folder would let any program swap it and get admin rights.
# Run from an elevated PowerShell: powershell -ExecutionPolicy Bypass -File install.ps1
$ErrorActionPreference = 'Stop'
$admin = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  'Run this from PowerShell opened as administrator.'; exit 1
}
$dir = "$env:ProgramFiles\cs2pin"
$exe = "$dir\cs2pin.exe"

Get-Process cs2pin -ErrorAction SilentlyContinue | Stop-Process -Force
New-Item -ItemType Directory -Force $dir | Out-Null
Copy-Item "$PSScriptRoot\cs2pin.exe" $exe -Force
Unblock-File $exe   # drop the downloaded-from-the-internet mark

$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute $exe
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
# No time limit (default is 72 h), keep running on battery, normal priority.
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries -Priority 5 -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName cs2pin -Action $action -Trigger $trigger -Principal $principal `
  -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName cs2pin

# Show the icon on the taskbar instead of the hidden-icons overflow (Settings > Taskbar > Other system tray
# icons). Explorer creates the entry the first time the icon appears.
# It stores Program Files paths as {FOLDERID_ProgramFilesX64}\...
$kfPath = '{6D809377-6AF0-444B-8957-A3773F02200E}\cs2pin\cs2pin.exe'
for ($i = 0; $i -lt 20; $i++) {
  Start-Sleep -Milliseconds 500
  $k = Get-ChildItem 'HKCU:\Control Panel\NotifyIconSettings' -ErrorAction SilentlyContinue |
    Where-Object { (Get-ItemProperty $_.PSPath).ExecutablePath -in $exe, $kfPath }
  if ($k) { Set-ItemProperty $k[0].PSPath -Name IsPromoted -Value 1 -Type DWord; 'tray icon: always shown'; break }
}
Get-Process cs2pin | Select-Object Id, Path | Format-List
(Get-FileHash $exe).Hash
