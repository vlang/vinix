# Resource-only system application package

Implementation and maintained V regression tools: source revision
`18fd4ec91aaaf581c4b30b4da1ae1703bb7122b5`.

Maps327 logged a caught null-path certificate verification error while creating
its location-denial dialog. `ATLLoadedApp.getSystemApplication()` constructs
its package from `Resources.getSystem()` using `PackageParser(null)`, then
incorrectly attempts to authenticate an APK archive. The verifier reaches
`String.concat(null)`. The dialog and Maps continue after the caught error;
this does not establish the cause of the later blank Attractions sheet.

Framework329 removes that one certificate-collection instruction from the
resource-only system factory. The generator requires the exact unique factory,
null-path parser, system resources and collector before applying the change.
External APK loaders, the certificate verifier and PackageParser remain
unchanged. No APK signatures are invented for the system resource package.

The frozen generator snapshot contains 138 sources, with only
`androidtools/framework_signatures.v` changed (SHA256
`d8d2b48a0e8bb02e4e6195c77d80a63913a3bd24ecfd676db93d0826d1c7c763`).
Actual output DEX has 2,068 classes: only `android/atl/ATLLoadedApp.smali`
changes; the other 2,067 classes are byte-identical to qualified Framework325.
Native315 is reused unchanged.

The complete build bundle is
`/Users/alex/.local/state/vinix/android/system-package329-framework-build-2026-10-25`,
manifest SHA256
`4f526669c32b91db3da92d3508b6aa97297d8a8b48b89fef29f6cd3f1f64559e`.
The JAR SHA256 is
`c88b7f8a7ee34776641fc235922d0d86a0d8eefc60d09e50d55836aabb624934`.
Independent full readback passed all 7,018 entries:

```
build/android-maps/build-bundle-check290 /Users/alex/.local/state/vinix/android/system-package329-framework-build-2026-10-25 4f526669c32b91db3da92d3508b6aa97297d8a8b48b89fef29f6cd3f1f64559e /external/fresh-readback.json
```

Host checks passed ten malformed/duplicate/wrong-origin negative cases and a
Smali/DEX roundtrip: exactly one collector instruction removed and all twenty
other methods unchanged. Complete independent readbacks passed 648 build
entries and 180 check entries. The bundles under
`/Users/alex/.local/state/vinix/android/` are:

| Host bundle | Manifest SHA256 |
| --- | --- |
| `system-package329-host-check-build-v7-2026-10-25` | `fd0ee6607651020733a1a8e8c7828618a7dda62d9eb09cf73c59a31fbd3303f8` |
| `system-package329-host-check-v7-2026-10-25` | `bbe13b329da64b2e110ada67635159c6befb654b6d9f5f7db087a15f9346df35` |

The host build retains generated C, compiler commands and all 549 consumed V
files. Production, checker and repository imports use private snapshots;
309 compiler-library files use the validated compiler's original VROOT/vlib,
with identical before/after hashes and retained snapshots. Adjacent C/header,
GC archive and two embedded fixture inputs are pinned. System SDK and dynamic
libraries remain environment inputs. This host check does not execute ART.

The focused paired guest runner is `system-package-run.v`; its probe checks
cached system application identity, `Resources.getSystem()` identity, null
signing metadata and `AlertDialog.Builder.create()`. Both frameworks must
complete those checks. The old variant must additionally retain the caught
null-path verification stack; the new variant must omit it. The unchanged
startup classifier remains separate from this semantic result.

Initial guest preparation stopped at 1,510,192 KiB, below the unchanged
1,536 MiB preparation gate. It succeeded after space recovered to
1,959,800 KiB. The compile and failed preparation receipts remain at
`/Users/alex/.local/state/vinix/android/system-package330-bootstrap-build-2026-10-25`.
The same signed probe APK, SHA256
`5cadfdd530b8f0fad2da7a2089f88c6ceac5aa93d870a66621bb6f9dd34634f6`,
is staged with Native315 and clean283 for both variants; only Framework325/329
differs. The actual signed APK's two classes were disassembled and inspected.

The old guest passed all seven ordered markers and `BOOTSTRAP-READY`, with
exactly one caught null-path verifier stack before `CACHE-PASS` (serial lines
319–329). The new guest initially stopped before launch: 949,664 KiB was below
the unchanged 1,024 MiB per-guest gate. This failure and its outer receipts
remain in `system-package330-run-2026-10-25`. A wrapper retry also stopped
before dispatch because the failed gate had not produced `disk-new.json`;
its receipt remains in `system-package330-new-retry1-2026-10-25`.

The unchanged runner subsequently passed the new-guest gate at 1,909,112 KiB.
The fixed guest passed all seven ordered markers (serial lines 306–321) and
`BOOTSTRAP-READY` (line 324), without the signature error or null-path verifier
stack. Both variants observed a live window for 45 seconds with no startup
failure markers; `functional_passed` remains null. The separate semantic
checks passed their old/new expectations. Retry receipts, including copies
of the failed dispatch evidence, remain in
`system-package330-new-retry2-2026-10-25`.

The complete paired bundle is
`/Users/alex/.local/state/vinix/android/system-package330-fixture-2026-10-25`,
manifest SHA256
`65cc180e2298fd76ea1d1dbffebe626f2c290b9ba33b8811c9b367ffa5c73c17`.
Independent full readback passed all 619 entries; its receipt is
`/Users/alex/.local/state/vinix/android/system-package330-root-readback-2026-10-25.json`.
The completed retry2 audit manifest is
`7c0da9491f14b0037f9037481b80a28f43ef9db33d15830fd7837c81e0e617f6`.
Its generic post-seal readback was stopped after retaining about 4 GiB RSS;
the retained streamed replacement passed. This did not interrupt the guest
or change the canonical seal.

| Guest evidence | SHA256 |
| --- | --- |
| Old serial | `98fc65184c274a982b8f82df3312a295154490218d4266e4b8ee3b78a4da29d0` |
| Old raw results | `7b1e2036af0ed9e8b4a1e2c68d42f1ae00bf217919aa2d1ab9c2d6e8b508a82a` |
| New serial | `c318c6a0c300a9d2fad33deb7320cb035ad20898723b8979fceb78f8a5a60be6` |
| New raw results | `0160f4b0a55792b834444503dcd0216092af20fb93adc46041514e977f8b0c3c` |

The genuine Maps screenshot and the latest application observations remain
documented in [maps327.md](maps327.md). That run rendered the map and Paris
place details on Framework325. Directions and navigation on Framework329,
and the cause of the unresolved Attractions sheet, remain unqualified.
