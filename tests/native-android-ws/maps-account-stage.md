# Protected Maps account staging

`maps-account-stage.v` creates a fresh additive image from the unbooted
`headless-stage-r4-2026-10-26` baseline. It verifies complete pinned build
inventories, coupled framework/native/launcher receipts, ELF dependencies,
real Maps/GMS SDK 29 signatures, unused Unix IDs, every original tar entry,
overlay destinations and all six preserved modules. It retains its sources,
request, tools, command receipts and readback inventories outside Git. It does
not boot an image or establish Google login success.

The request selects separate sealed framework, JNI, account library, launcher,
Maps controller, browser, token APK and token controller bundles. The overlay
includes the unchanged UI fixture and headless fixture, updating the latter's
runtime pins. UID/GID 10014 is reserved for the synthetic token cache fixture;
the Maps controller provisions its separately audited IDs 10012 and 10013.
Existing regular-file modes are preserved in the tar and recorded; the guest
controller verifies all protected inputs before removing file write bits.
The initial passwd/group contents are retained in the overlay inventory. They
are excluded from immutable controller pins because provisioning appends the
validated Maps/GMS identities and records both database versions.

Build with the pinned V compiler's new backend, `-prod -gc none`, and import
roots `build-support`, `build-support/android`, and `tests/native-android-ws`.
The tool embeds its sources and requires a fresh canonical external output:

```
maps-account-stage REQUEST_JSON REQUEST_SHA256 FRESH_OUTPUT
maps-account-stage --audit-base BASE JAVA APKSIGNER_JAR FRESH_OUTPUT
maps-account-stage --replay-ui ORIGINAL_UI_STAGE BASE FRESH_OUTPUT
maps-account-stage --verify-inventory BUNDLE MANIFEST_SHA256
maps-account-stage --self-test
```

Evidence under `/Users/alex/.local/state/vinix/android/`:

- `maps-account-base-audit-2026-10-26-r2` passed unchanged image/module and APK
  checks. Complete manifest SHA-256:
  `5baf1ed7d574ba08409fac7049189958873bf942a5a053d601abb70a4402226c`.
  Both APKs have the single SDK 29 signer
  `f0fd6c5b410f25cb25c3b53346c8972fae30f8ee7411df910480ad6b2d60db83`.
- `account-ui-stage-2026-10-26-r3-replay` reproduces every file from the original
  complete UI manifest
  `f5def88d6933a888f81b8a816788dbd28c38ca89523cc8417d074bfd1d1a624b`.
  Only firmware comes from the exact original unbooted baseline. The old stage
  and its post-run files remain intact. Adjacent replay provenance SHA-256:
  `577d5e02d8f86efcd4fb091a0e074d9cc46112d1de7244e02b58a692850f93ac`.
  `maps-stage-ui-inventory-r2.log` retains the original mismatch diagnostic.
- `maps-account-stage-module-tests-r8.log` records all four module test files
  passing with assertions enabled, including inventory/identity mutations,
  ELF validation, headless pin replacement and streaming media readback.
  `maps-account-stage-selftests-r7.log` records the executable's explicit
  rejection checks. Retained tool binaries and build logs use the
  `maps-account-stage-tool-r*` names; exact sources are embedded in each tool.

The final runtime bundles and actual guest results are separate evidence.
Staging and synthetic fixture success must not be reported as Google account
authentication success.
