# List manifests without a checkver block.
if (!$env:SCOOP_HOME) { $env:SCOOP_HOME = Convert-Path (scoop prefix scoop) }
& "$env:SCOOP_HOME/bin/missing-checkver.ps1" -Dir "$PSScriptRoot/../bucket" @Args
