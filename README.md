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

CI runs checkver every 2 hours and commits when something changed. Manually:
`.\bin\checkver.ps1 -Update -SkipUpdated`

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
scoop bucket add scope file:///D:/CODE/mine/scope-bucket
```

Needs at least one commit. After editing, `cd D:\Scoop\buckets\scope; git pull --ff-only`.
