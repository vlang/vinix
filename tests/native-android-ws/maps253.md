# Maps253: account provisioning reaches a native startup crash

Maps253 provisions an actual `maps253` passwd/group account for UID/GID 10000,
preserving every original database byte. The retained serial contains exact
before/after Base64 and SHA256 values, and confirms account resolution before
invoking the production launcher with the explicit identity, home and data
directory. This run emits no post-drop `/proc` identity measurement, so it does
not independently establish the resulting process credential tuple.

The original result remains **`startup_failed`**: native ART is observed, then
the main thread faults at `0x80006d2c59c` with address zero after a Dalvik-cache
warning and exits 139. `launcher_entered`, `native_maps_observed` and
`process_exited` are true; `backend_ready` is false and `functional_passed` is
null. The only host interaction is a successful boot-progress screenshot.
The configured 300-second limit is not endurance evidence. No onboarding,
map, bridge initialization or functional pass is inferred.

The prelaunch source revision is
`008e32bf91b6e33fcb4d1acad3e851147c3b039b`.
The complete external bundle is
`/Users/alex/.local/state/vinix/android/maps253-2026-10-24`.
Its 56-file prelaunch `frozen-inputs.json` SHA256 is
`45ead4229f35061237d1f74dc9a95e71f3bb4526f6e91830dab04d24f7ada397`;
its final 200-file `sha256.json` SHA256 is
`7b59975e452d3372bd4324c07306f92eb9a88e3bcf3d79c5c3135004701e0690`.

The bundle retains complete ordinary raw output, harness stdout, original
signed Maps and companion APKs, the runtime with 109 regular files, post-run
private boot media and firmware variables. The auditor replays the actual FAT archive,
including hidden files and symlink targets, and compares its initramfs account
databases with the exact original serial bytes. Frozen framework/native
sources (125/83 files), wrapper and production launcher sources, build receipts
and compiler identities are retained. Later maintained fixture edits do not
replace the frozen source. Supplementary native247 provenance is a retained
recipe and binary identity, rather than an original compiler execution receipt.

Rebuild and check with assertions enabled:

```sh
/Users/alex/code/v/v_old -cc cc -cflags -O2 -o /tmp/maps253-evidence \
  tests/native-android-ws/maps253-evidence.v
/tmp/maps253-evidence check \
  /Users/alex/.local/state/vinix/android/maps253-2026-10-24 \
  7b59975e452d3372bd4324c07306f92eb9a88e3bcf3d79c5c3135004701e0690
```

The full check passed and removed its approximately 0.9 GiB extraction scratch.
Negative checks rejected a manifest-only partial bundle, an all-zero pin and
the superseded pre-correction pin. A separate `-prod` build exited 2 before
I/O. Validation logs are retained beside the bundle as
`maps253-2026-10-24-check-corrected.log`,
`maps253-2026-10-24-negative.log` and
`maps253-2026-10-24-prod-guard-corrected.log`; negative evidence is in the
`maps253-2026-10-24-negative/` directory.

The complete superseded bundle remains at
`maps253-2026-10-24-superseded1019/`. Its checker failed an incorrect
interaction-log absence assumption before media replay; the final checker
instead verifies the exact screenshot-only log and associated output bytes.
