# End-to-end test on a real Windows desktop. Run elevated (ssh works too); it starts the session-1 steps as one-shot
# scheduled tasks: non-elevated ones (like Steam/cs2 and Explorer) and elevated ones (to click the elevated menu).
# Uses a stand-in cs2.exe (a copy of ping.exe), never the real game. Leaves cs2pin enabled.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
function InSession([string]$step, [string]$level) {
  $out = "$here\out-$step.txt"; Remove-Item $out -ErrorAction SilentlyContinue
  $a = New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"& '$here\step.ps1' $step *> '$out'`""
  $p = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel $level
  Register-ScheduledTask -TaskName "cs2pin-test-$step" -Action $a -Principal $p -Force | Out-Null
  Start-ScheduledTask "cs2pin-test-$step"
  for ($i = 0; $i -lt 60 -and (Get-ScheduledTask "cs2pin-test-$step").State -eq 'Running'; $i++) { Start-Sleep -Milliseconds 250 }
  Start-Sleep -Milliseconds 300
  Unregister-ScheduledTask "cs2pin-test-$step" -Confirm:$false
  if (Test-Path $out) { Get-Content $out | % { "  [$step] $_" } } else { "  [$step] no output" }
}
function Aff { $p = Get-Process cs2 -ErrorAction SilentlyContinue; if ($p) { '0x{0:X}' -f [int64]$p[0].ProcessorAffinity } else { 'no cs2' } }
function Enabled { (Get-ItemProperty HKCU:\Software\cs2pin -Name Enabled -ErrorAction SilentlyContinue).Enabled }
# Open the menu like Explorer would (non-elevated, tests the message filter), click the toggle (elevated).
# A posted click doesn't hand cs2pin the foreground like a real click does, so allow a few tries.
function Toggle { $before = Enabled
  for ($try = 1; $try -le 4; $try++) {
    InSession open Limited | Out-Null; InSession click Highest | ? { $_ -match 'did not open' }
    Start-Sleep 1; if ((Enabled) -ne $before) { "  toggled on try $try"; return } }
  "  toggle FAILED after 4 tries" }

if (Get-Process cs2 -ErrorAction SilentlyContinue | ? { $_.Path -notlike "$env:LOCALAPPDATA\cs2pin-standin*" }) { 'real cs2 is running: not testing'; exit 1 }
$app = Get-Process cs2pin -ErrorAction Stop
"cs2pin pid $($app.Id) session $($app.SessionId), registry Enabled=$(Enabled)"
if ((Enabled) -eq 0) { 'cs2pin is off, turning it on first'; Toggle }
InSession icon Limited
InSession standin Limited
Start-Sleep 2
"stand-in cs2 affinity after 2 s: $(Aff)   (want 0x5554)"
foreach ($round in 'off', 'on') {
  Toggle
  Start-Sleep 1
  "after toggling $round : cs2 affinity $(Aff), registry Enabled=$(Enabled)"
}
InSession restart Limited
Start-Sleep 3
"after a new stand-in cs2 started: $(Aff)   (want 0x5554)"
InSession shot Limited
Get-Process cs2 -ErrorAction SilentlyContinue | ? { $_.Path -like "$env:LOCALAPPDATA\cs2pin-standin*" } | Stop-Process -Force
"cs2pin still running: $([bool](Get-Process cs2pin -ErrorAction SilentlyContinue)), CPU time $([math]::Round((Get-Process cs2pin).TotalProcessorTime.TotalMilliseconds)) ms, working set $([math]::Round((Get-Process cs2pin).WorkingSet64/1MB,1)) MB"
