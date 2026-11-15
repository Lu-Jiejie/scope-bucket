# Check (and with -Update, bump) manifest versions against upstream releases.
# Usage: .\bin\checkver.ps1 [-Update] [-SkipUpdated] [app...]
if (!$env:SCOOP_HOME) { $env:SCOOP_HOME = Convert-Path (scoop prefix scoop) }
& "$env:SCOOP_HOME/bin/checkver.ps1" -Dir "$PSScriptRoot/../bucket" @Args
