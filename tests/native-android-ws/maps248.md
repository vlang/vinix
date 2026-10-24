# Maps248: map displayed, then JNI abort

On 2026-10-24, signed Google Maps 26.42.01.997557324 reached the Vinix native
backend and displayed a detailed North America map after Skip. The retained
`map-before-input.png` was visually inspected: land/water, Google Maps branding,
Local Vibe and navigation tabs were visible. Search and layers were not exercised
in this run.

The process then exited with code 134 at approximately 14:23:30 UTC. ART reported
`NewDirectByteBuffer` with a pending `IllegalStateException: Bridge not initialized
yet.` in `ClearcutJniBridge.create()` during `ValidationJni.nativeValidate()`.
The original result remains `startup_failed`, with launcher entry, backend ready,
native Maps observed and process exited all true; `functional_passed` remains null.
The configured 180-second observation ended early. This is retained failure
evidence, not a functional or endurance pass.

The run resumed the unchanged prepared Maps244 image, using framework244 and
native236. The implementation checkpoint was
`58d3877930fe516f7fbe841495e060d039171bb6` (ActionProvider callbacks); exact
113-file framework and 83-file native source snapshots are retained alongside
their build inventories. Later CompoundButton changes are not part of this run.
The report/auditor was prepared from checkout
`5577de6f3667423d27fd7bb01b9bc688494aef05`.

| Input | SHA-256 |
| --- | --- |
| Framework244 jar | `933fc7db4267d123a33bb1e4e064ea3b69450fd065bb4d8e4f5898b91cf842b8` |
| Native236 library | `78da0707dc12d4cc8a55e3b3efa3e94ee202ec5c36babbf2470f259423a59d3d` |
| Prepared boot image | `faae9dba43aee2249d4cfaa3bebcd57ab4869ffe3f9e64af3a9649ce4d432c58` |

Read-only preflight at 14:21:14 UTC matched all seven runtime files extracted
from the FAT image against the staged Maps244 module. The complete external
bundle includes that image, three signed APKs and their inspection metadata,
runtime files, kernel, QEMU/firmware, frozen helpers, exact source snapshots,
original results and failure markers, serial logs, screenshots, interaction
timeline and packet capture. Mutable UEFI variable storage is explicitly retained
as **post-run** state; its preflight hash does not describe those later bytes.
The separate Maps246 interruption record is also retained: it stopped during APK
verification before launcher readiness and has no final result.

Artifact root:
`/Users/alex/.local/state/vinix/android/maps248-2026-10-24`.
The complete evidence is retained in `bundle/`. Additional tar copies are not
retained: host storage was exhausted during duplicate archive creation, and the
incomplete copies were removed. The audited directory remains intact.
Bundle `sha256.json` SHA-256:
`465c52b1559a2b6d24df67d6285eae5bf7406b1b253cd5cc6323f6e29b3721e9`.
Retention `sha256-inventory.json` SHA-256:
`f445467e3baa2d5eacd29fe90f5720931d4b796688220c5111b88c4fbd8cf9a6`.

Audit the complete directory with:

```sh
v -prod -o /tmp/maps248-evidence tests/native-android-ws/maps248-evidence.v
/tmp/maps248-evidence check /Users/alex/.local/state/vinix/android/maps248-2026-10-24/bundle 465c52b1559a2b6d24df67d6285eae5bf7406b1b253cd5cc6323f6e29b3721e9
```

Validation: complete-bundle audit passed; a manifest-only partial bundle was
rejected for missing evidence. The audit and negative-check logs are retained
beside the bundle with `sha256-inventory.json`. The auditor preserved the
original failure markers and results. No APK modifications or
exception-classifier changes were made for this run.
