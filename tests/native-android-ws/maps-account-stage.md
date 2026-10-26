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
The first original creation establishes each existing inode's mode. Later tar
headers overwrite contents while leaving that mode intact. Every occurrence is
audited for kind and protection; the first mode must cover the payload's required
read/execute permissions. The overlay retains that effective mode, and the guest
verifies all protected inputs before removing file write bits. Ordered overwrite
checks cover the baseline's executable SQLite library and later DSO headers.
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
clone-maps-account-stage SOURCE MANIFEST_SHA256 FRESH_OUTPUT
```

The separate clone helper verifies the entire original bundle, makes fresh
regular-file clones with matching file and directory modes, and rechecks both
complete inventories and metadata trees. Its tool, source and provenance stay
beside the output so the copied original manifest remains exact. Apply kernel
patches and boot only the copy; retain the original sealed stage unchanged.

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
  `maps-account-stage-selftests-r10.log` records the executable's explicit
  rejection checks, including ordered original-mode inheritance. Retained tool
  binaries and build logs use the `maps-account-stage-tool-r*` names; exact
  sources are embedded in each tool.
- `maps-account-r1` passed final staging with tool source `af6402672` and
  controller fix `27d5bfe47`. Its complete pre-kernel-patch manifest SHA-256 is
  `2982ad3dd8ac1e8de3c7169382788397be9551f58a19059e58311282a8380070`;
  stage receipt SHA-256 is
  `88fb4254f5baec7b4fc70a56314ea103c35bb051e1963bdc895739f67af04552`.
  `maps-account-stage-request-r1.json` freezes framework r3, JNI r15, account r5,
  launcher r12, Maps controller r3, browser deployment r7, token APK r5 and
  token controller r1. Its SHA-256 is
  `929a6938e07daef5b32f42dee91857734da75ff08cdf206c04e7c1d60ea714fb`.
  Complete frozen input rechecks, both SDK 29 signatures, overlay readback and
  all six unchanged module checks passed. Independent comparison found zero
  kind/mode mismatches across 36 destination collisions in 6,295 base headers
  and 1,926 planned entries. See `maps-account-stage-run-r1.log` and the bundle's
  retained inventories. This image still requires the separately audited
  recvmsg kernel patch before guest execution.
- `maps-account-vm-r1` passed exact cloning with helper source `9f2d74d4c`.
  All 1,910 regular files and the complete metadata tree matched before any
  kernel patch or boot; source and copy both passed the complete original
  manifest above. The original `maps-account-r1` remains unchanged. Adjacent
  provenance `maps-account-vm-r1-clone.json` has SHA-256
  `11eefc5fd71734d0502c95625aef0859faecb0c468d992ac9b78b4b42968a9e6`.
  See `maps-account-clone-run-r1.log`. Guest mutation belongs only in the copy.

The final runtime bundles and actual guest results are separate evidence.
Staging and synthetic fixture success must not be reported as Google account
authentication success.
