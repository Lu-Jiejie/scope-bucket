# Re-check hashes of the manifests in this bucket.
# Usage: .\bin\checkhashes.ps1 [-Update] [app...]
if (!$env:SCOOP_HOME) { $env:SCOOP_HOME = Convert-Path (scoop prefix scoop) }
& "$env:SCOOP_HOME/bin/checkhashes.ps1" -Dir "$PSScriptRoot/../bucket" @Args
