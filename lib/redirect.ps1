# Redirects places a program hardcodes on C: (usually under %APPDATA%) into the
# app's persist dir, so data the program writes to C: really lands on the Scoop
# root.
#
# Manifest usage:
#   "pre_install":   "& \"$bucketsdir\\$bucket\\lib\\redirect.ps1\" -Setup -Paths \"$env:APPDATA\\Vendor\\App\", \"$env:LOCALAPPDATA\\Vendor\""
#   "pre_uninstall": "& \"$bucketsdir\\$bucket\\lib\\redirect.ps1\" -Teardown"
#
# The path list is written once, in pre_install. Setup records the resolved
# links in "$persist_dir\.redirect.json" and Teardown works from that file, so
# the list never has to be repeated and uninstall still works even if the
# bucket layout changed in between.
#
# Where a link points is derived, never typed: every source is mapped under
# $persist_dir by mirroring its path from the nearest known root, so
# %LOCALAPPDATA%\Foo becomes $persist_dir\AppData\Local\Foo. An explicit
# "source => relative\target" entry overrides that when a program insists on a
# particular layout.
[CmdletBinding()]
param(
    [switch] $Setup,
    [switch] $Teardown,
    [switch] $List,
    [string[]] $Paths,
    # Only for poking at a redirect from a plain shell, where no hook has run and
    # $persist_dir is empty. Inside a hook the app's own persist dir is used.
    [string] $PersistDir
)

$ErrorActionPreference = 'Stop'

if ($PersistDir) { $persist_dir = $PersistDir }

if ((@($Setup, $Teardown, $List) | Where-Object { $_ }).Count -ne 1) {
    throw 'redirect.ps1: pass exactly one of -Setup, -Teardown or -List.'
}
if (!$persist_dir) {
    throw 'redirect.ps1: $persist_dir is empty. Call it from a manifest hook, or pass -PersistDir.'
}

$stateFile = Join-Path $persist_dir '.redirect.json'
$poolPrefix = [System.IO.Path]::GetFullPath($persist_dir).TrimEnd('\') + '\'

# Nested roots (%TEMP% lives inside %LOCALAPPDATA%) resolve most-specific first,
# which is why this list is sorted by path length rather than declared order.
# The drive root is last, so anything else on C: still gets caught instead of
# being rejected.
$profileDir = [Environment]::GetFolderPath('UserProfile')
$knownRoots = @(
    @{ Name = 'AppData\Local'; Path = [Environment]::GetFolderPath('LocalApplicationData') }
    @{ Name = 'AppData\LocalLow'; Path = if ($profileDir) { Join-Path $profileDir 'AppData\LocalLow' } }
    @{ Name = 'AppData\Roaming'; Path = [Environment]::GetFolderPath('ApplicationData') }
    @{ Name = 'ProgramData'; Path = [Environment]::GetFolderPath('CommonApplicationData') }
    @{ Name = 'ProgramFiles'; Path = [Environment]::GetFolderPath('ProgramFiles') }
    @{ Name = 'ProgramFilesX86'; Path = [Environment]::GetFolderPath('ProgramFilesX86') }
    @{ Name = 'UserProfile'; Path = $profileDir }
    @{ Name = 'Temp'; Path = [System.IO.Path]::GetTempPath() }
    @{ Name = 'SystemDrive'; Path = $(if ($env:SystemDrive) { $env:SystemDrive + '\' }) }
) | Where-Object { $_.Path } | ForEach-Object {
    [pscustomobject]@{ Name = $_.Name; Path = [System.IO.Path]::GetFullPath($_.Path).TrimEnd('\') }
} | Where-Object { $_.Path -match '.+' } | Sort-Object { $_.Path.Length } -Descending

function Test-SamePath {
    param([string] $A, [string] $B)
    if (!$A -or !$B) { return $false }
    $na = [System.IO.Path]::GetFullPath($A).TrimEnd('\')
    $nb = [System.IO.Path]::GetFullPath($B).TrimEnd('\')
    return $na.Equals($nb, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-LinkInfo {
    param([string] $Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (!$item -or $item.LinkType -notin @('Junction', 'SymbolicLink', 'HardLink')) { return $null }

    # A hard link carries no target of its own: it is just a second name for the
    # same file, so there is nothing to compare against.
    $target = $null
    if ($item.LinkType -ne 'HardLink') {
        $raw = @($item.Target)[0]
        if (!$raw) { return $null }
        $target = [System.IO.Path]::GetFullPath($raw).TrimEnd('\')
    }
    return [pscustomobject]@{
        Path        = $Path
        LinkType    = $item.LinkType
        Target      = $target
        IsContainer = [bool]$item.PSIsContainer
    }
}

function Test-LinkPointsAt {
    param($Link, [string] $Target)
    if (!$Link) { return $false }
    if ($Link.LinkType -eq 'HardLink') { return $true }
    return (Test-SamePath $Link.Target $Target)
}

function Remove-Link {
    param($Link)
    if (!$Link) { return }
    if ($Link.IsContainer) {
        # Deletes the link itself; the directory behind it is untouched.
        [System.IO.Directory]::Delete($Link.Path, $false)
    } else {
        # For a hard link this drops one name; the data lives on under the other.
        [System.IO.File]::Delete($Link.Path)
    }
}

function Ensure-Directory {
    param([string] $Path)
    if ($Path -and !(Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# Where a path really points once every ancestor link is followed. Without this
# a second pass over "C:\...\App" after its parent is already linked would build
# a link inside the pool pointing back at itself.
function Get-EffectivePath {
    param([string] $Path)

    $ancestor = Split-Path $Path -Parent
    while ($ancestor) {
        $link = Get-LinkInfo $ancestor
        if ($link -and $link.LinkType -ne 'HardLink') {
            $remainder = $Path.Substring($ancestor.Length).TrimStart('\')
            return [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($link.Target, $remainder)).TrimEnd('\')
        }
        $next = Split-Path $ancestor -Parent
        if (!$next -or $next -eq $ancestor) { break }
        $ancestor = $next
    }
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Merge-Into {
    param([string] $From, [string] $To)

    if (!(Test-Path -LiteralPath $To)) {
        Ensure-Directory (Split-Path $To -Parent)
        try {
            Move-Item -LiteralPath $From -Destination $To -Force
        } catch {
            throw "redirect.ps1: cannot move '$From' into '$To'. Close the program first, then retry. ($($_.Exception.Message))"
        }
        return
    }

    # Target already holds data, so fold the leftovers in instead of dropping them.
    if (!(Test-Path -LiteralPath $From -PathType Container)) {
        Move-Item -LiteralPath $From -Destination $To -Force
        return
    }

    foreach ($child in @(Get-ChildItem -LiteralPath $From -Force)) {
        Merge-Into $child.FullName (Join-Path $To $child.Name)
    }
    Remove-Item -LiteralPath $From -Recurse -Force
}

function Expand-Item {
    param([string] $Item)
    $value = [Environment]::ExpandEnvironmentVariables($Item.Trim())
    if ($value -like '~*' -and $profileDir) { $value = $profileDir + $value.Substring(1) }
    return $value
}

function Resolve-Target {
    param([string] $Item)

    # "source => relative" pins the destination explicitly.
    $destination = $null
    $arrow = $Item.IndexOf('=>')
    if ($arrow -ge 0) {
        $destination = $Item.Substring($arrow + 2).Trim()
        $Item = $Item.Substring(0, $arrow)
    }

    $expanded = Expand-Item $Item
    if (!$expanded) { throw 'redirect.ps1: empty entry in -Paths.' }
    if ($expanded -match '^[A-Za-z]:\\?$') {
        throw "redirect.ps1: '$expanded' is a whole drive. Redirect a folder on it instead."
    }
    $full = [System.IO.Path]::GetFullPath($expanded).TrimEnd('\')

    # Linking into the pool itself would recurse forever.
    if ($full.StartsWith($poolPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        (Test-SamePath $full $persist_dir)) {
        throw "redirect.ps1: '$full' is already inside the persist dir."
    }

    if ($destination) {
        if ([System.IO.Path]::IsPathRooted($destination)) {
            throw "redirect.ps1: '$destination' must be relative to the persist dir."
        }
        return [pscustomobject]@{
            Source = $full
            Target = [System.IO.Path]::Combine($persist_dir, $destination)
        }
    }

    foreach ($root in $knownRoots) {
        $isRootItself = Test-SamePath $full $root.Path
        $isInside = $isRootItself -or $full.StartsWith($root.Path + '\', [System.StringComparison]::OrdinalIgnoreCase)
        if (!$isInside) { continue }
        # Refusing a folder root stops a typo from swallowing all of AppData.
        if ($isRootItself) {
            throw "redirect.ps1: '$Item' is the whole $($root.Name) folder. Redirect one of its subfolders."
        }
        return [pscustomobject]@{
            Source = $full
            Target = [System.IO.Path]::Combine($persist_dir, $root.Name, $full.Substring($root.Path.Length + 1))
        }
    }

    throw "redirect.ps1: '$Item' is not on the system drive and is not under any known user folder. Use the 'source => relative\target' form to place it yourself."
}

function New-Link {
    param([string] $Source, [string] $Target)

    if (Test-Path -LiteralPath $Target -PathType Container) {
        New-Item -ItemType Junction -Path $Source -Value $Target | Out-Null
        return
    }

    # A file only links cheaply on the same volume; otherwise fall back to a
    # symlink, which needs an elevated shell or Developer Mode.
    try {
        New-Item -ItemType HardLink -Path $Source -Value $Target | Out-Null
    } catch {
        try {
            New-Item -ItemType SymbolicLink -Path $Source -Value $Target | Out-Null
        } catch {
            throw "redirect.ps1: cannot link file '$Source' to '$Target'. Hard links need both paths on one volume; symbolic links need Administrator or Developer Mode."
        }
    }
}

function Read-State {
    if (!(Test-Path -LiteralPath $stateFile)) { return @() }
    $raw = Get-Content -LiteralPath $stateFile -Raw
    if (!$raw -or !$raw.Trim()) { return @() }
    return @($raw | ConvertFrom-Json | Where-Object { $_ -and $_.Source })
}

function Save-State {
    param([object[]] $Entries)

    $unique = [ordered]@{}
    foreach ($entry in $Entries) {
        if ($entry -and $entry.Source) {
            $unique[$entry.Source.ToLowerInvariant()] = [pscustomobject]@{
                Source = $entry.Source
                Target = $entry.Target
            }
        }
    }
    if ($unique.Count -eq 0) {
        if (Test-Path -LiteralPath $stateFile) { Remove-Item -LiteralPath $stateFile -Force }
        return
    }
    ConvertTo-Json -InputObject @($unique.Values) -Depth 4 | Set-Content -LiteralPath $stateFile -Encoding utf8
}

if ($List) {
    $recorded = Read-State
    if ($recorded.Count -eq 0) {
        Write-Host "No redirects recorded in '$stateFile'."
        return
    }
    foreach ($entry in $recorded) {
        $link = Get-LinkInfo $entry.Source
        $state = if (!$link) { 'MISSING' }
        elseif ($link.LinkType -eq 'HardLink') { 'OK' }
        elseif (Test-SamePath $link.Target $entry.Target) { 'OK' }
        else { "MOVED -> $($link.Target)" }
        Write-Host ("{0,-24} {1}  =>  {2}" -f $state, $entry.Source, $entry.Target)
    }
    return
}

if ($Teardown) {
    $recorded = Read-State
    if ($recorded.Count -eq 0) { return }

    $left = @()
    # Deepest first, so a parent link is still in place while children are cut.
    foreach ($entry in ($recorded | Sort-Object { $_.Source.Length } -Descending)) {
        $link = Get-LinkInfo $entry.Source
        if (!$link) { continue }

        # Only drop a link this script made; leave anyone else's alone.
        if (!(Test-LinkPointsAt $link $entry.Target)) {
            Write-Host "Leaving '$($entry.Source)' alone: it points at '$($link.Target)', not at '$($entry.Target)'."
            $left += $entry
            continue
        }

        Remove-Link $link
        Write-Host "Unlinked '$($entry.Source)'"
    }

    # Anything still linked stays recorded; everything cut drops out of the file.
    Save-State $left
    return
}

if (!$Paths) {
    throw 'redirect.ps1: -Setup needs -Paths.'
}

Ensure-Directory $persist_dir

$record = @(Read-State)
# Shallow paths first, so a parent link exists before a child sits inside it.
foreach ($item in ($Paths | Where-Object { $_ -and $_.Trim() } | Sort-Object { $_.Length })) {
    $resolved = Resolve-Target $item
    $source = $resolved.Source
    $target = $resolved.Target

    $link = Get-LinkInfo $source

    if ($link -and (Test-LinkPointsAt $link $target)) {
        Write-Host "Already redirected '$source'"
        $record = @($record | Where-Object { !(Test-SamePath $_.Source $source) }) +
                  [pscustomobject]@{ Source = $source; Target = $target }
        continue
    }

    # A link further up may already send this path into the pool. Linking again
    # there would nest a link inside its own target, and moving the data would
    # mean moving a folder onto itself, so stop and say so.
    $effective = Get-EffectivePath $source
    if ($effective.StartsWith($poolPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "Skipped '$source': a link above it already sends this path to '$effective'."
        continue
    }

    if ($link) {
        # Points elsewhere: bring that data over before relinking.
        if ($link.LinkType -ne 'HardLink' -and (Test-Path -LiteralPath $link.Target)) {
            Merge-Into $link.Target $target
        }
        Remove-Link $link
    } elseif (Test-Path -LiteralPath $source) {
        Merge-Into $source $target
    }

    Ensure-Directory $target
    Ensure-Directory (Split-Path $source -Parent)

    New-Link -Source $source -Target $target

    $made = Get-LinkInfo $source
    if (!$made) {
        throw "redirect.ps1: linking '$source' to '$target' did not produce a link."
    }

    Write-Host "Redirecting '$source' -> '$target' ($($made.LinkType))"
    $record = @($record | Where-Object { !(Test-SamePath $_.Source $source) }) +
              [pscustomobject]@{ Source = $source; Target = $target }
}

Save-State $record
