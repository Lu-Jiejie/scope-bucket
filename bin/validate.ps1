# Validate every manifest against Scoop's own JSON schema.
# Needs PowerShell 7 (Test-Json) and a Scoop checkout to borrow schema.json from.
# Usage: pwsh -File .\bin\validate.ps1 [-SchemaPath <path to schema.json>]
param(
    [String] $SchemaPath
)

$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
if (!$SchemaPath) {
    if (!$env:SCOOP_HOME) { $env:SCOOP_HOME = Convert-Path (scoop prefix scoop) }
    $SchemaPath = Join-Path $env:SCOOP_HOME 'schema.json'
}
if (!(Test-Path $SchemaPath)) {
    throw "Schema not found at '$SchemaPath'. Pass -SchemaPath explicitly."
}

$schema = Get-Content $SchemaPath -Raw
$bucket = Join-Path $root 'bucket'
$manifests = @(Get-ChildItem $bucket -Filter '*.json' -Recurse -File)
$failed = 0

foreach ($manifest in $manifests) {
    $name = $manifest.BaseName
    try {
        $json = Get-Content $manifest.FullName -Raw | ConvertFrom-Json
    } catch {
        Write-Host "FAIL $name : invalid JSON - $($_.Exception.Message)" -ForegroundColor Red
        $failed++
        continue
    }

    # Test-Json reports only the first violation and throws rather than returning
    # false, so a manifest can pass here and still be rejected by Scoop.
    try {
        $null = Test-Json -Json ($json | ConvertTo-Json -Depth 20) -Schema $schema
    } catch {
        Write-Host "FAIL $name : $($_.Exception.Message)" -ForegroundColor Red
        $failed++
        continue
    }

    Write-Host "OK   $name $($json.version)" -ForegroundColor Green
}

if ($failed -gt 0) {
    Write-Host "`n$failed of $($manifests.Count) manifest(s) failed validation." -ForegroundColor Red
    exit 1
}
Write-Host "`nAll $($manifests.Count) manifest(s) OK." -ForegroundColor Green
