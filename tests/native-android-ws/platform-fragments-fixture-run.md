# Platform fragments fixture runner — 2026-10-29

`onboarding-api-run.v --platform-fragments` selects the signed platform-fragments
regression APK and its exact framework/native pair. It retains the existing
`org/vinix/bootstrap/Main` entry, protected fixture setup, single pass/readiness
checks, bounded child lifetime and exit/cleanup requirements. The transfer
selector is `serve --platform-fragments-api`, serving only
`/platform-fragments-api-run` and `/platform-fragments.apk`. Historical profile
values and routes remain unchanged.

The fixed fixture marker is:

```text
PLATFORM-FRAGMENTS-PASS stable-manager tagged-queue fifo-once application-injection lifecycle-order late-add host-isolation callback-identity
```

Actual artifacts were rehashed before pinning. Paths below use
`S=/Users/alex/.local/state/vinix/android`:

| Input | Path under `S` | SHA-256 |
| --- | --- | --- |
| Signed APK | `platform-fragments-fixture-2026-10-29-r1/probe.apk` | `f2e08f444782607a408bd25766da399100e908cf2b99edeebcfb80d267dc21de` |
| Framework JAR | `combined-account-webview-platform-fragments-framework-2026-10-29-r1/api-impl.jar` | `6970582da55b15dd30391491d2be2213abe665fe0256167f45cccdd3de25bcd4` |
| Native DSO | `current-native-build-2026-10-29-exception-restore-r2/native/libvinix-android-native.so` | `613c6b2c7b1e816a5d7b0694d626a52a5b4df19604a6a224df99ad13055aa74c` |

The fixture's produced manifest and roundtrip classes confirm package
`org.vinix.bootstrap`, activity `.Main` and the exact marker. Runtime/fixture
provenance remains in their original complete producer bundles.

All five checks passed serialized under unchanged 600-MiB aggregate RSS,
300-second, 512-MiB observed shared-volume growth and 1-GiB reserve limits.
Every guard recorded exit/child status zero and complete cleanup; time reports
recorded zero swaps. The runner selftest rejected 409 malformed, duplicate,
mixed-profile and failure cases, including 28 actual malformed-CLI refusals.
Transfer tests retain pin/snapshot/binary/HTTP/deadline checks and add nine
platform-selector/port refusals without creating outputs. ELF inspection
confirmed a static AArch64 executable without an interpreter.

| Check | Seconds | Peak sampled aggregate RSS, bytes | Time-report peak process RSS, bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 1.338 | 342,114,304 | 371,179,520 |
| Runner selftest | 0.529 | 21,446,656 | 17,416,192 |
| AArch64 runner compile | 1.754 | 356,384,768 | 367,427,584 |
| Host transfer compile | 1.474 | 349,323,264 | 382,844,928 |
| Transfer selftest | 0.590 | 6,406,144 | 8,486,912 |

The static runner is `S/platform-fragments-api-run-2026-10-29-r1/run`, SHA-256
`58259a403faa16d64e2e4d56d6447128520d2e768c0feaa1ee908b595a52bf1f`.
The host transfer is
`S/platform-fragments-api-transfer-build-2026-10-29-r1/transfer`, SHA-256
`b3be89af8b2e4817932e8cc85fadf9eb88aa337d4da7dc2def82978566a05c2e`.
Runner/transfer source hashes are respectively
`3f706ba3d6a4a6c92dd1f1d1da5d8c8ee8c206edb1f468c1efbdcf2558d6d6c5`
and `2d3f897d938e0ce01fe416301bf9fc5a5c1dfcb671c7c2744694c4bfc9971946`.
The recorded checkout base is `355caa04832c2368ae95f384c034ba6221d4af97`;
exact modified source copies and command receipts are retained.

The four closed roots are the runner, `platform-fragments-api-run-build-2026-10-29-r1`,
the transfer build, and `platform-fragments-api-transfer-controls-2026-10-29-r1`.
Their complete in-place seal and a separate fresh-process full readback passed
for four roots and 32 entries:
`S/platform-fragments-api-tools-sealed-2026-10-29-r1/manifest.json`, SHA-256
`9b3c5f510f920edd9bee3ee7b758bc49f38ea6fec8d6280119d331f3b35a7903`.
Seal/check controls are adjacent to that sealed root; both use 600-MiB RSS,
300-second, 64-MiB observed growth and 1-GiB reserve limits. Independent source
and artifact review passed. These checks qualify the tools and static ARM
build; ART fixture execution, Maps behavior and Google authentication remain
pending runtime validation.
