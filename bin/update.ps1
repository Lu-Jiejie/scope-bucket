<#
.SYNOPSIS
    Bump the versions in bucket/*.json and let you review before committing.

.DESCRIPTION
    Default run edits the manifests, validates them, prints the diff and stops.
    Nothing is committed and nothing is installed unless you pass a flag.

.EXAMPLE
    .\bin\update.ps1              # bump, show the diff, stop
    .\bin\update.ps1 -Preview     # bump and report, then revert the edits
    .\bin\update.ps1 -Commit      # bump, validate, commit
    .\bin\update.ps1 -Push        # bump, commit, push
    .\bin\update.ps1 -Install     # also update the apps on this machine
#>
param(
    [switch] $Commit,
    [switch] $Push,
    [switch] $Install,
    [switch] $Preview,
    [string] $Message = 'chore: bump app versions'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

if (!$env:SCOOP_HOME) {
    $env:SCOOP_HOME = Convert-Path (scoop prefix scoop)
}

$bucketDir = Join-Path $root 'bucket'

function Get-ManifestSnapshot {
    $map = @{}
    foreach ($file in Get-ChildItem $bucketDir -Filter '*.json' -File) {
        $map[$file.Name] = [pscustomobject]@{
            Hash = (Get-FileHash $file.FullName -Algorithm SHA256).Hash
            Text = [System.IO.File]::ReadAllText($file.FullName)
        }
    }
    return $map
}

function Get-VersionOf([string] $text) {
    if (!$text) { return '' }
    return ($text | ConvertFrom-Json).version
}

Push-Location $root
try {
    $before = Get-ManifestSnapshot

    Write-Host 'Checking upstream versions...' -ForegroundColor Cyan
    & "$PSScriptRoot/checkver.ps1" -Update -SkipUpdated
    if ($LASTEXITCODE -ne 0) { throw "checkver failed with exit code $LASTEXITCODE." }

    $after = Get-ManifestSnapshot
    $bumped = @($after.Keys | Where-Object { $before[$_].Hash -ne $after[$_].Hash } |
            ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) } | Sort-Object)

    # Manifests left modified by an earlier run still count, so review-then-commit
    # works. Only modified files (M) - a new untracked manifest is not a version bump.
    $dirty = @(git status --porcelain -- bucket | Where-Object {
            $_.Length -gt 3 -and $_.Substring(0, 2).Contains('M')
        } | ForEach-Object {
            [System.IO.Path]::GetFileNameWithoutExtension($_.Substring(3).Trim())
        }) | Sort-Object -Unique

    $names = @($bumped + $dirty | Sort-Object -Unique)

    if ($names.Count -eq 0) {
        Write-Host 'No upstream changes.' -ForegroundColor Green
        return
    }

    Write-Host ''
    foreach ($name in $names) {
        $file = "$name.json"
        $old = if ($before[$file]) { Get-VersionOf $before[$file].Text } else { '' }
        $new = Get-VersionOf $after[$file].Text
        if ($old -and $new -and $old -ne $new) {
            Write-Host ("  {0,-30} {1} -> {2}" -f $name, $old, $new)
        }
        else {
            Write-Host ("  {0,-30} {1} (uncommitted)" -f $name, $new)
        }
    }

    if ($Preview) {
        foreach ($name in $bumped) {
            [System.IO.File]::WriteAllText((Join-Path $bucketDir "$name.json"), $before["$name.json"].Text)
        }
        Write-Host ''
        Write-Host 'Preview only, edits reverted.' -ForegroundColor Yellow
        return
    }

    Write-Host ''
    & "$PSScriptRoot/validate.ps1"
    if ($LASTEXITCODE -ne 0) { throw 'Validation failed, not committing.' }

    Write-Host ''
    Write-Host 'Changes:' -ForegroundColor Cyan
    git --no-pager diff --stat -- bucket

    if (!$Commit -and !$Push -and !$Install) {
        Write-Host ''
        Write-Host 'Left in the working tree. Review, then re-run with -Commit.' -ForegroundColor Yellow
        return
    }

    git add bucket
    git commit -m ($Message + ': ' + ($names -join ', ')) | Out-Null
    Write-Host ''
    Write-Host "Committed: $($names -join ', ')" -ForegroundColor Green

    if ($Push) {
        $remote = git remote
        if (!$remote) {
            Write-Host 'No git remote configured, cannot push.' -ForegroundColor Red
        }
        else {
            git push | Out-Null
            Write-Host "Pushed to $remote." -ForegroundColor Green
        }
    }

    if ($Install) {
        $clone = Join-Path (Split-Path (Split-Path (Split-Path (scoop prefix scoop)))) 'buckets/lu'
        if (Test-Path (Join-Path $clone '.git')) {
            Write-Host 'Syncing local clone...' -ForegroundColor Cyan
            git -C $clone pull --ff-only | Out-Null
        }
        else {
            Write-Host "No local clone at $clone, skipping." -ForegroundColor Yellow
        }

        Write-Host ''
        foreach ($name in $names) {
            Write-Host "Installing $name..." -ForegroundColor Cyan
            scoop update "lu/$name"
        }
    }
}
finally {
    Pop-Location
}
