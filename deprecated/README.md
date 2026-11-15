Retired manifests live here.

Scoop looks up a manifest in `bucket/` first and, if it is gone, falls back to
`<bucket root>/deprecated/<app>.json` (`lib/manifest.ps1:55-74`). A manifest
placed here therefore stops being installable by name while still letting
already-installed copies show up as deprecated in `scoop status`
(`lib/core.ps1:578-581`).

There is no need for sentinel versions or custom `renamed` bookkeeping.
