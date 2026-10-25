# Maps334: diagnostic launcher overlay

Maps334 follows the blank Attractions sheet recorded in [Maps333](maps333.md).
Its framework and native payloads are the complete, unchanged
[Maps332](maps332.md) builds. The only changed entry in the 109-file effective
runtime is `usr/bin/run-android-calculator`. This is a diagnostic replay;
building or preparing it does not qualify Attractions.

Paths below are relative to `/Users/alex/.local/state/vinix/android/` unless
otherwise stated. Dates and times are UTC on 2026-10-25. The source inputs were
prepared at revision `eaf7155bc`; the three new V tools are committed in
`cac3591ca`.

## Launcher and media

[The launcher builder](maps334-trace-launcher.v) derives the sealed clean283
launcher with exactly five environment setters at `main()`:

- `VINIX_ANDROID_TRACE_TREE=1`
- `VINIX_ANDROID_TRACE_THREADS=1`
- `VINIX_ANDROID_TRACE_OBJECT_CLASS=1`
- `VINIX_ANDROID_TRACE_VIEW_ADDS=com.google.android.apps.gmm.base.components.gmmrecyclerview.GmmRecyclerView`
- `VINIX_ANDROID_TRACE_VISIBILITY=com.google.android.apps.gmm.base.components.gmmrecyclerview.GmmRecyclerView`

The complete build is `maps334-trace-launcher-build-2026-10-25`. It retains
216 frozen inputs, two compiler passes, generated C, dependency and linker
records, the original compiler recorder and the full sealed283 baseline.
The retained builder's full `check ROOT MANIFEST_SHA256` passed independently
at its original location and in a relocated readback clone.

| Artifact | SHA256 |
| --- | --- |
| Launcher build manifest | `25855fcb5aa5016d7cc5df659017f66b6f3dc5d96e4935d474d691b59de9fc27` |
| ARM64 static launcher, 382,552 bytes, mode 0755 | `52e305950821e56d85bb9c4d6ba51a3c5f74ccf2b15b158d1fd47279cb70ef56` |
| Derived launcher V | `bc1fb116c9f3dac8ec71bb8c21b19b992a28f55239df8a3418114ff000767241` |
| Generated replay source | `8a6c887a56a45066ab97174b7d6f5f72868840923f9a00acd38cbb63e15e9307` |
| Recorded replay binary | `4f37a5c1bfce6ff8ae357270a8dbea28b8346e2d7c8c1b13f9407112069e95c9` |
| Launch pins | `dc2848c3e062975ea20f5c4d45044730af440b9e33eb300f09f515a1ad6a8b9b` |
| Prelaunch typed manifest | `b930b3a530294d0ef32d5e8ea094913199beb1ba58eb9f002544155fec7c2fd8` |
| Preparation envelope manifest | `f4b8159e4178fe7ca4096fba50a974b5d49a737d4a301dd9e4132fbda32a192b` |
| Read-only gate envelope manifest | `e3c23199533defea7d42d17ea5ab919dd0d8871902e7a945b7ab5c0dff0449d5` |

[The generator](maps334-generate.v) authenticates the original333 source and
derives the replay using [the preparation fragment](maps334-overlay-prepare.v).
It clones the full333 prelaunch baseline and the exact full332 build bundles.
The final boot module contains one regular file, the launcher; its tar listing,
extracted typed tree, and FAT readback are checked. `limine.conf` loads it after
the existing runtime. Kernel, initramfs and the embedded 907,648,000-byte runtime
archive are read back unchanged. The matching frozen kernel processes modules
in order and replaces the duplicate regular file's storage and size; its
existing 0755 mode agrees with the replacement.

The 1,536-MiB gate remains at generation, preparation and launch. This staging
method avoids rewriting the large runtime archive. No prior evidence was
deleted and no historical checker was weakened. Initial checks were delayed
by host storage pressure; space recovered before actual generation.

## Validation

The generator's `--check-source ROOT PIN FRESH_CHECK_ROOT` compiles the same
derived source into a separate directory without creating replay destinations,
staging media or launching a guest. That small host compilation has its own
128-MiB floor. `maps334-source-check-2026-10-25` retains the full V closure,
compiler/CC pins, before/after input hashes, build output and binary. Its
manifest is `375cbd0802f69d015822fc2767ce9b658f925844652b3133c7bff0ead56f5060`.
Root and peer independently verified all 281 retained files. The generated
runner's streaming stdin hash also returned the standard SHA256 for `abc`.
Inherited unused-constant notices and CommonCrypto deprecation warnings are
retained in its build log.

Actual generation and the recorded preparation wrapper completed successfully.
Preparation ran 15:24:55–15:27:25 with the unchanged six Native332/Framework332
pins, clean host environment, and original 600-second classifier self-test.
The envelope is `maps334-preparation-receipt-2026-10-25`; the canonical replay
root is `maps334-2026-10-25`. Generation and runner closure evidence is retained
under `maps334-run-build-c-2026-10-25` and copied into the canonical root.
The read-only launch gate passed. Root and peer independently read back both
nine-file envelopes with exact inventories and hashes. The peer additionally
verified the 109-entry runtime delta, single tar member and unchanged embedded
base media against sealed333.

Tree/Future samples are render-driven and limited to twelve; thread samples
stop after 300 seconds. A completed Future plus an empty recycler cannot by
itself distinguish absent data from skipped layout. Runtime conclusions must
be based on the actual replay and screenshots, with these limits preserved.

## Runtime failure

The recorded run envelope ran 15:29:33–15:31:48 and completed collection with
unchanged input pins and no forbidden host environment keys. The application
itself failed after four seconds: `backend_ready=false`,
`native_maps_observed=false`, `process_exited=true`, and
`outcome=startup_failed`. Its guest launcher recorded exit 1. The enclosing
runner's exit 0 records completed collection, not application success; the
600-second window was not reached.

The preserved serial ends with musl rejecting `vinix-android-native` as
`Not a valid dynamic program`. It records the explicitly invoked musl loader
at base `0x400000`, entry `0x469de8`; the successful333 boot placed the same
loader at `0x1b200000`. The unchanged native executable is ET_EXEC, SHA256
`611b0e74b21c669aad9d17cef0d3e83d93be6cb57c103cc3f1d3444015e4b5da`,
whose LOAD range starts at `0x400000`. The frozen kernel's PIE selection permits
that address. Retained musl `map_library()` rejects an ET_EXEC mapping moved
away from its required address with EBUSY, and its caller emits the observed
message. These addresses and source paths identify a loader placement
collision. No Java diagnostic samples or Attractions observation were reached.

The canonical `maps334-2026-10-25/sha256.json` is
`e09ca0db6527adf174f098abb858742f0996e83b72c85e4ef5d29de00594ee4e`;
the exact recorded runner's complete typed readback passed all 24,610 entries.
The nine-file run envelope `maps334-run-receipt-2026-10-25` has manifest
`60cce2e9e3842bee216721be16782f134fe526c99090d7d8ad95697035b2d3d0`
and passed complete inventory/hash readback. The result, serial, startup-failure
PNG and postrun media are retained in the canonical bundle. A fresh attempt is
required; this sealed failure is not reused as a successful replay.
