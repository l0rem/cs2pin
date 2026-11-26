# Removes cs2pin: stops it, deletes the logon task, the exe and its one registry value.
# Run from an elevated PowerShell. A running cs2 keeps its current affinity until it restarts.
$ErrorActionPreference = 'Continue'
Get-Process cs2pin -ErrorAction SilentlyContinue | Stop-Process -Force
Unregister-ScheduledTask -TaskName cs2pin -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item "$env:ProgramFiles\cs2pin" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item HKCU:\Software\cs2pin -Recurse -Force -ErrorAction SilentlyContinue
'cs2pin removed'
