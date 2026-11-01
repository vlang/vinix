# Serial resource theme diagnostic: missing custom attribute after copy

The strict serial diagnostic reaches the lookup after cross-owner theme copy,
then reports `cross-B2`, cookie=-1 with presence required and no pending JNI
exception. Fresh-destination, style application and same-owner custom-attribute
copy checks passed beforehand. This happens before the owned Asset/AssetDir
controls or workers start. The missing application-defined attribute is
observed; its underlying cause, complete concurrent stress and Maps crash
causation remain unestablished. No broker or controlled Maps run was started.

Diagnostic fixture `194b55a0c` retains the original application-attribute oracle
and adds failure phases plus an identical serial preflight before workers.
Tools `203e162c9` pin that APK. The prepared image, Intent SDK and resource-lock
native DSO remain unchanged. The [first resource failure](maps-resource-lock-runtime-2026-11-01.md)
and [aggregate theme failure](maps-resource-lock-retry-runtime-2026-11-01.md)
remain separately sealed. This serial result does not retroactively identify
the inner phase of the earlier concurrent failure. The [successful Intent Maps baseline](maps-intent-extras-retry-runtime-2026-11-01.md)
also remains separate, with authentication unverified.

Artifacts remain under `/Users/alex/.local/state/vinix/android` (`S`): controls
`maps-resource-lock-retry-controls-2026-11-01-r2` (`E`), stopped guest
`maps-resource-lock-vm-r3` (`VM`), audit
`maps-resource-lock-runtime-audit-2026-11-01-r3` (`A`), transfer
`resource-locks-api-transfer-live-2026-11-01-r3` (`T`), and diagnostic fixture
`resource-lock-fixture-2026-11-01-r5` with its matching control root.

| Input or result | SHA-256 |
| --- | --- |
| Unchanged prepared parent `maps-resource-lock-r1/sha256.json` | `d4dcdfa033e7e0fa21a634cae6087e95deedbbee4c4936d6be4b7af69f4d5171` |
| Framework JAR | `02aefc8136cb87eb8e9ebd0928cb15f3e1c2042e47d2a687170a0f9309ac4b20` |
| Native production DSO | `aeb5ccd643020cbb20ad5630dabff4bfd0ff8b04a5b0fbcfd1b657b3bcd91dd7` |
| Signed r5 fixture APK | `b90fe510799ddf4d550c1915d3a730ab2db3aacbcdc95122c2862a85afdb814f` |
| Packaged diagnostic helper | `0192d06f30d20a4ee47f5573c30e50e98248837bb70a1f7e5b8bea1d9b8f0e97` |
| ARM runner | `fc4584fa5070b7398f4df6987348467e027538c4469377e5042cf395a349af78` |
| Failed-log diagnostic receipt | `31f5098fcce6a121a2a03424bccf25496a823ae41eddcc67418ee053e6a9c9ec` |

Fresh clone and frozen-kernel installation/readback passed in 8.525/55.236
seconds at sampled aggregate RSS 36,012,032/34,406,400 bytes, with zero guard/
child exits, host cleanup complete and zero swaps under unchanged 600 MiB/
900-second/2 GiB-growth/1 GiB-reserve/file-size caps. Owned VM91557 ran
06:13:54–06:18:37 UTC with exclusive 12 GiB/four CPUs and user-default
networking. Dedicated UID/GID10137, root-owned pinned inputs and read-only
runtime bind were verified. No compiler ran while the guest was live.

The complete failed child is 10,069 bytes/105 LF-terminated lines, SHA-256
`8badf5cf8bbf558a54a6d3059cd59dde00a9e600b422036da7e84cda402d47a2`.
Line 91 records:

```text
RESOURCE-LOCKS-THEME-DIAGNOSTIC phase=cross-B2 cookie=-1 expected_present=1 type=0xffffffff data=0x00000000 pending=0
```

The archived helper reaches that phase after the cross-copy call returns
without a pending exception. The destination attribute lookup returns -1.
type=0xffffffff/data=0 are diagnostic sentinels on the negative-cookie path,
emitted before TypedValue fields are read; they are not actual observed field
contents. The local pending=0 does not establish general JNI health.
Main.themePreflight(source18) throws through Main.run(source20)/onCreate(source8).
There is one resource FAIL and one ANDROID-WS-FAIL, with no PASS, native readiness
or worker marker. No worker or owned Asset/AssetDir lifetime control started.

The guest explicitly exported standard base64 to /dev/console. Linked immutable
snapshots identify the 15,092-byte interval, SHA-256
`cde8f34dd372fc114abe144dada97b50b86c41ce22235b305ea87e829bd98bc8`.
An initial byte-count transcription as 10,068 was refused by the unchanged
[diagnostic decoder](diagnostic-uart-base64.md); that failed control remains.
The second screenshot was re-read as 10,069 with the same guest SHA. Fresh
derivation and separate retained-decoder full check passed exact preservation,
including all original UART. They took 78/341 ms at sampled RSS
1,523,712/1,294,336 bytes, both exits zero, host cleanup complete and zero swaps
under original 600 MiB/300-second/64 MiB-growth/1 GiB-reserve/file-size caps.
No payload/checker/assertion repair occurred. Complete validation remains at
`A/fixture-failure-validation.md`, SHA-256
`d68d965b29c73aa348d9a0354674b65fb2c75672ab0a39ec7b2d3266b4eebe7d`.
Preservation integrity is not successful six-pin/eleven-check qualification.

Owned VM91557 received one SIGTERM at 06:18:37. The first stop tool reported an
ownership race after signalling; the operator confirmed absence, then
reconcile-stop returned zero without a second kill. gone.json records absence
at 06:18:46. Final serial matches the complete 89,938-byte full snapshot,
SHA-256 `b19dfa40705d542ae03d517ff7fe6c3589cbaf20bcb9c16f804ea70984ad9ff4`.
No successful runner receipt/SERVICE-QUERY archive or strict Maps/account import
applies. No full stress, owned-lifetime, new Maps or authentication success is
claimed. A later common-framework-key cross-owner control has a distinct oracle;
it cannot erase or qualify this original custom-attribute failure.

All ten new roots, including r5 fixture/control roots and four adjacent VM clone
sidecars, are closed to writes. Final `A/operator-notes.md` SHA-256 is
`5b75dd473fb3091cffcde3adcf9952b5eb22f6127c14b87737d1d5c2825fc3e3`.
Earlier prepared/source/native/tool and failed-runtime roots retain their
separate complete seals. The first runtime seal remains preserved at
`S/maps-resource-lock-runtime-sealed-2026-11-01-r3`. Its unchanged guard stopped
on 75,218,944 bytes of observed shared-volume growth against the 64 MiB cap,
after 3.740 seconds at sampled RSS 8,994,816 bytes. Guard/child exits were
125/137 with cleanup complete. No manifest was produced and no fresh readback
was run for that failed attempt. Original roots and the complete failed control
remain retained without modification.

One authorized recovery after a quiet backoff passed complete sealing and
separate fresh-process readback for eleven roots: the ten originals plus the
failed control, 507 typed entries. Manifest
`S/maps-resource-lock-runtime-sealed-2026-11-01-r3-r2/sealed/manifest.json` has
SHA-256 `c030f7c1d963070f5e981438fbe3a305127b44a9d875ad58dc7ddf4bfaf6c754`.
Seal/readback took 3.260/1.949 seconds at sampled aggregate RSS
28,360,704/12,320,768 bytes and shared growth 19,918,848/2,306,048 bytes. Both
guard/child exits were zero, cleanup complete and process swaps zero under the
unchanged qualified sealer and original 600 MiB/900-second/64 MiB-growth/
1 GiB-reserve/file-size caps. Retain every original and both control bundles;
evidence completeness does not change the negative custom-attribute result.
