# One step of run.ps1, executed inside the signed-in session.
param([string]$Step)
. "$PSScriptRoot\ui.ps1"
$standin = "$env:LOCALAPPDATA\cs2pin-standin\cs2.exe"
switch ($Step) {
  'icon' { "tray icon rect: $([UI]::IconRect())" }
  'standin' {
    New-Item -ItemType Directory -Force (Split-Path $standin) | Out-Null
    Copy-Item C:\Windows\System32\PING.EXE $standin -Force
    $p = Start-Process $standin -ArgumentList '-n 120 127.0.0.1' -WindowStyle Hidden -PassThru
    "started stand-in cs2.exe pid $($p.Id), affinity at start 0x{0:X}" -f [int64]$p.ProcessorAffinity
  }
  'restart' {
    Get-Process cs2 -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 1
    $p = Start-Process $standin -ArgumentList '-n 120 127.0.0.1' -WindowStyle Hidden -PassThru
    "restarted stand-in cs2.exe pid $($p.Id)"
  }
  'open' { [UI]::PostClick() }
  'click' {
    $w = [UI]::MenuWindow(); if ($w -eq [IntPtr]::Zero) { 'menu did not open'; exit 1 }
    $m = [UI]::MenuOf($w); "menu before:"; [UI]::Items($m)
    [UI]::Click($w, $m, 0)
  }
  'shot' {
    Add-Type -AssemblyName System.Drawing, System.Windows.Forms
    $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
    $h = 80; $w = 700
    $bmp = New-Object Drawing.Bitmap $w, $h
    [Drawing.Graphics]::FromImage($bmp).CopyFromScreen($b.Right - $w, $b.Bottom - $h, 0, 0, $bmp.Size)
    $bmp.Save("$PSScriptRoot\tray.png"); "saved tray.png; icon rect $([UI]::IconRect()); screen $($b.Width)x$($b.Height)"
  }
}
