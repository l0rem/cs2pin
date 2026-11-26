# While CS2 runs: shows cs2.exe's affinity. Expected 0x5554 (CPUs 2,4,6,8,10,12,14) when cs2pin is on,
# 0xFFFF when it is off.
Get-Process cs2 -ErrorAction SilentlyContinue | ForEach-Object { '{0}  affinity 0x{1:X}' -f $_.Id, [int64]$_.ProcessorAffinity }
if (-not (Get-Process cs2 -ErrorAction SilentlyContinue)) { 'cs2 is not running' }
