# scope-bucket

Personal Scoop bucket. Flat layout, short app names, versions bumped by CI.

```
bucket/          manifests, flat (bucket/<app>.json)
deprecated/      Scoop's native tombstone dir
bin/             thin wrappers over scoop's own bin/ plus a schema validator
lib/             hook scripts manifests can call (redirect.ps1)
.github/         CI: schema validation on push, checkver every 2 hours
```

## Layout

Flat manifests are enough: Scoop finds them with a recursive
`Get-ChildItem -Recurse` under the bucket dir (`lib/manifest.ps1:1-3`), so
nesting by publisher only buys a longer path at this size.

## Adding an app

1. Drop `bucket/<app>.json` — copy the shape of `bucket/zoxide.json`.
2. `.\bin\checkhashes.ps1 <app> -Update` to fill or fix hashes.
3. `.\bin\checkver.ps1 <app>` to confirm version detection.

## Updating

`.github/workflows/update.yml` runs `checkver -Update -SkipUpdated` every two
hours and commits only when a manifest actually changed. `checkver` writes the
new `hash` itself for GitHub-hosted releases: it reads the `digest` field of the
release asset (`lib/autoupdate.ps1:307-310`), so manifests don't need a
`autoupdate.hash` block.

## Retiring an app

Move the manifest to `deprecated/`. Scoop falls back to that directory when the
manifest disappears from `bucket/`, and `scoop status` reports the app as
deprecated (`lib/manifest.ps1:55-74`, `lib/core.ps1:578-581`). No sentinel
version and no custom `renamed` field needed.

## Keeping data off C:

`persist` covers apps that accept a data directory. `env_set` can point them at
`$persist_dir` because Scoop expands the value where `$persist_dir` is a live
local (`lib/install.ps1:331-342`, called at `lib/install.ps1:63`), which is how
`bucket/zoxide.json` keeps `_ZO_DATA_DIR` inside `persist\zoxide\data`.

A variable alone is not airtight: it is read once at process start, so anything
launched by Explorer, a service, or a shell that was already open when the
variable was set writes to the default path instead — and does so silently, into
a fresh empty store. So `bucket/zoxide.json` also links
`%LOCALAPPDATA%\zoxide` at the same directory. The variable keeps the fast,
relocatable path; the link catches whatever misses it. Both must name the same
directory, or the data splits in two.

`persist` is not part of that pair for this kind of app. It only moves files the
app writes *inside its install directory*, and zoxide never writes there — the
`apps\zoxide\current\data` junction it would create is decoration.

One variable often replaces several links. `atuin` normally scatters itself over
`~\.config\atuin`, `~\.atuin` and `~\.local\share\atuin`; `ATUIN_HOME` collapses
all three into one directory (`config.toml` at the root, databases under
`data\`). That is the primary mechanism; the three dotfolders are still linked
into that same tree as a fallback, because an `atuin` built before 18.24 does
not know `ATUIN_HOME` at all and an older one already on the machine would
otherwise keep writing to the old places. Prefer the variable whenever the app
documents one — a link pins one absolute path, a variable moves with the install.

Apps that hardcode a path and read no environment variable need a link instead.
`lib/redirect.ps1` builds one:

```json
"pre_install": [
    "& \"$bucketsdir\\$bucket\\lib\\redirect.ps1\" -Setup -Paths \"$env:APPDATA\\Vendor\\App\", \"$env:LOCALAPPDATA\\Vendor\\App\""
],
"pre_uninstall": [
    "& \"$bucketsdir\\$bucket\\lib\\redirect.ps1\" -Teardown"
]
```

The path list appears once, in `pre_install`; `Setup` records what it linked in
`$persist_dir\.redirect.json` and `Teardown` reads that file, so uninstall does
not repeat the list and keeps working if the bucket layout moved since. Data
already sitting in the real folder is moved into `persist` first, so turning
this on for an app in use does not lose its settings. `Teardown` only removes a
link that still points where the state file says it should; a link repointed by
someone else is reported and left alone.

Where a link points is never typed by hand. Each source is mirrored under
`$persist_dir` from the nearest known root, so
`%LOCALAPPDATA%\Vendor\App` becomes `persist\<app>\AppData\Local\Vendor\App`.
Write `%APPDATA%\Vendor => vendor-data` to pin a different relative target when
a program insists on a particular layout.

Accepted roots are `%APPDATA%`, `%LOCALAPPDATA%`, `%LOCALAPPDATA%Low`,
`%PROGRAMDATA%`, `%PROGRAMFILES%`, `%PROGRAMFILES(X86)%`, `%USERPROFILE%`,
`%TEMP%` and finally the system drive, so anything else on `C:` is still
covered. A root itself rather than a subfolder of it, a whole drive, and a path
already inside `persist` are rejected — that keeps a typo from swallowing all of
AppData or building a link that points at itself.

Folders become junctions, files become hard links (falling back to a symlink
across volumes). Passing a parent and a child path in one call is fine: the
parent link is built first and the child is left nested inside it instead of
being linked twice. Re-running `Setup` is a no-op on an already correct link,
and repoints a link that drifted from somewhere else, folding the old data in
first.

`-List` reports the recorded links and whether each one still resolves:

```
pwsh lib\redirect.ps1 -List -PersistDir D:\Scoop\persist\foo
OK      C:\Users\you\AppData\Local\Foo  =>  D:\Scoop\persist\foo\AppData\Local\Foo
MISSING C:\Users\you\AppData\Roaming\Foo  =>  D:\Scoop\persist\foo\AppData\Roaming\Foo
```

Both calls run inside manifest hooks, where `$persist_dir` and `$bucketsdir`
are already set (`lib/install.ps1:48-50`, `lib/core.ps1:1375`). Outside a hook
`$persist_dir` is empty, so pass `-PersistDir` to inspect or repair one by hand.

`scoop update` runs `pre_uninstall` from the old manifest and then `pre_install`
from the new one (`libexec/scoop-update.ps1:348-379`), so the links are cut and
rebuilt on every upgrade; the data in `persist` is untouched by either half.

## Use it

```
scoop bucket add scope https://github.com/<you>/scope-bucket
scoop install scope/zoxide
```

## Local testing before pushing

```
scoop bucket add scope file:///D:/CODE/mine/scope-bucket
```

`scoop bucket add` clones, so two things follow. The path has to be a git URL —
a plain local path is rejected as "not a valid Git URL" — and the repo needs at
least one commit, or the clone lands empty and the bucket shows zero manifests.
After editing a manifest, `cd` into the added bucket and `git pull --ff-only`;
a `file://` remote has nothing else to fetch, but the pull still copies your new
commit over.

## Why short names

The app name alone is the install identity — `apps\<app>`, `persist\<app>`,
shims, and uninstall bookkeeping all key on it and carry no bucket information
(`lib/core.ps1:370-385`). So `zoxide` here and `main/zoxide` install side by
side as two separate apps, and `scoop install scope/zoxide` never resolves to
the official one by accident. The tradeoff: when a name is shared with an
official bucket, you must always spell out the bucket, because bucket order
decides the bare-name lookup (`lib/buckets.ps1:56-75`, official buckets are
moved to the front).
