# scope-bucket

Personal Scoop bucket.

```
bucket/          manifests, flat
deprecated/      retired manifests
bin/             scoop's scripts + schema check
lib/             redirect.ps1
```

## Add an app

1. Write `bucket/<app>.json` (copy `zoxide.json`).
2. `.\bin\checkhashes.ps1 <app> -Update`
3. `.\bin\checkver.ps1 <app>`

## Update

Bump the versions in the manifests — this is what you push:

```
.\bin\update.ps1            # bump, validate, show the diff, stop
.\bin\update.ps1 -Commit    # bump, validate, commit
.\bin\update.ps1 -Push      # bump, commit, push
.\bin\update.ps1 -Preview   # report what changed, then undo the edits
.\bin\update.ps1 -Install   # also update the apps on this machine
```

A bare run leaves the edits in the working tree so you can look at them first;
`-Commit` picks up whatever the previous run left behind. `-Install` pulls
`D:\Scoop\buckets\lu` and runs `scoop update lu/<app>`, so skipping it leaves
your local copy alone. CI runs the same check every 2 hours and commits on its
own.

## Retire an app

Move the manifest to `deprecated/`.

## Data outside the app folder

Apps that scatter data on C: get a link into `persist`:

```json
"pre_install": [
    "& \"$bucketsdir\\$bucket\\lib\\redirect.ps1\" -Setup -Paths \"$env:APPDATA\\Vendor\\App\""
],
"pre_uninstall": [
    "& \"$bucketsdir\\$bucket\\lib\\redirect.ps1\" -Teardown"
]
```

`-Paths` takes any absolute path; targets are derived automatically under
`$persist_dir`. Add `=> relative\dir` to choose one yourself. Check with
`pwsh lib\redirect.ps1 -List -PersistDir <persist dir>`.

## Local testing

```
scoop bucket add lu file:///D:/CODE/mine/scope-bucket
```

Needs at least one commit. After editing, `cd D:\Scoop\buckets\lu; git pull --ff-only`.

Install by full name (`scoop install lu/zoxide`) — `main` has a `zoxide` too and wins on a bare name.
