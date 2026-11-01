# Resource synchronization ARM pass and Maps runtime

The scoped resource regression passes on ARM. Maps renders real tiles, Paris
search/place photos and its profile menu with the new native library. Sign in
still shows “Something went wrong” and a Google-server communication error.
No credentials or Next were supplied; authentication is unverified. GPS, routes
and navigation were not exercised. This bounded run establishes no crash cause
or general leak freedom.

Production fixes `a5310a98f`/`fea4b7a85`, [native pair](resource-lock-native-pair-2026-11-01.md),
fixture `e005631f3` and runner `56b341d52` preserve the unchanged Intent SDK.
The fixture explicitly covers same-owner app-attribute copies and cross-owner
framework-attribute copies. Four workers complete 64 iterations each, join, then
validate/release the retained owned Asset/AssetDir. The [original custom-key
failure](maps-resource-lock-theme-diagnostic-runtime-2026-11-01.md) and earlier
failed attempts remain separately sealed; this revised oracle does not qualify
that negative case. Google APKs and strict runtime health checks are unchanged.

Artifacts are below `S=/Users/alex/.local/state/vinix/android`: audit
`maps-resource-lock-runtime-audit-2026-11-01-r4` (`A`), stopped
`maps-resource-lock-vm-r4` (`VM`), controls
`maps-resource-lock-retry-controls-2026-11-01-r3` and transfer
`resource-locks-api-transfer-live-2026-11-01-r4`. The admitted r6 fixture and its
controls remain in `resource-lock-fixture-2026-11-01-r6` and the matching control
root. Prepared parent `maps-resource-lock-r1` is unchanged.

| Input or receipt | SHA-256 |
| --- | --- |
| Prepared parent `sha256.json` | `d4dcdfa033e7e0fa21a634cae6087e95deedbbee4c4936d6be4b7af69f4d5171` |
| Framework JAR | `02aefc8136cb87eb8e9ebd0928cb15f3e1c2042e47d2a687170a0f9309ac4b20` |
| Native DSO | `aeb5ccd643020cbb20ad5630dabff4bfd0ff8b04a5b0fbcfd1b657b3bcd91dd7` |
| Signed r6 APK | `eedcc5a40c86f2f6131121e922a7625e416f5df68671baa70cea581246c3e55e` |
| ARM runner | `8cf50d0972cda4bfa445f33a944b19026eae862cf5caa00f0292bc44453d6bca` |
| Fixture receipt | `5769cde50049e1c1d56251cf6ce67f62303ec16eb4e8b48b999fabdf68e65851` |
| Controller receipt | `45f212cf1f25c25e818d67a9124d479c39d6539069aad2113e27b5d742110264` |

Clone/kernel checks passed. Owned VM53252 ran 06:28:48–06:38:35 UTC with exclusive
12 GiB/four CPUs/user-default networking. UID/GID10137, six actual pins and eleven
runner checks pass; child3228 exited0. The complete 9,791-byte/116-line log has one
scoped PASS at99, READY110 and onDestroy/final LF116, with no worker/phase or selected
failure marker. Unchanged zero-removal diagnostic SERVICE-QUERY import passed
32 chunks/15,974 archive bytes; this is not strict fixture-protocol qualification.
Supporting source/receipt/guard review is `A/fixture-validation.md`, SHA-256
`c4da40d49b107e614ee841e317c66e116ea62e2bf40e00e8a9e46c5a391ed306`.

After Skip, `VM/maps-resource-after-skip.png` at 06:35:53 shows real North America
tiles. Search at 06:36:15 and `maps-resource-paris-photos.png` at 06:36:35 show Oasis
d'Aboukir street tiles, 4.6 stars/98 ratings and photos. `maps-resource-profile.png`
at 06:36:48 shows the profile menu; `maps-resource-account-screen.png` at 06:37:13
shows the readable communication error. Bounded private captures record
Intro→Wrapper→PreAddAccount→Error; they establish no network-health or login success.

Controller06:33:34–06:38:01 reports `user-stopped-no-authentication-claim`, readiness
true and empty error. Stop was requested at 06:37:58 within the 15-minute bound.
Broker24769 exit137 follows controlled cleanup; drain EOFtrue/status1/182,214bytes/errno0.
Two cleanup survivors' running/zombie states are unknown; no clean exit is claimed.
Unchanged strict account import passes 25 entries/2,836 chunks/1,451,758 bytes,
SHA-256 `989f3615f0764c54497a29e3d2b033affee26a8b5bd55e840371769629ad5b20`.
Private raw app/broker logs remain excluded except hashes/bounded captures.
The VM received one SIGTERM at 06:38:35; the first stop reported a post-signal
ownership race. Reconciliation returned0 and absence was recorded at 06:38:43,
without a second kill.

All ten new roots, including r6 fixture/control roots and four VM clone sidecars,
are closed. Notes SHA-256 is
`dc748f4f336b438113b8e62f9ebb17c912ab7f4a2827d719d7bbbfc8c4570266`.
One seal and separate fresh-process full readback pass 611 typed entries, manifest
`S/maps-resource-lock-runtime-sealed-2026-11-01-r4/sealed/manifest.json`, SHA-256
`fd5c6fd9d90b8fda7aea449b8ece7c70c43aa9d1d977eed8e1496df6a423717d`.
Seal/readback took 5.998/2.412 seconds, both guard/child0/cleanupcomplete; original
600 MiB/900-second/64 MiB-growth/1 GiB-reserve/file-size caps remain. No seal attempt
failed here. Retain complete original/source/failed-control bundles and unchanged
auditors; export integrity is not authentication.
