# Checked ART compilation guard preparation

This follows 6f521e20b's account attempt. Its retained r85 broker log explicitly
identifies the module compiler failure: image_space.cc cannot create the boot
image, runtime.cc reports "Dex file fallback disabled, cannot continue without
image", and dex2oat cannot create its runtime. The parent ART process continues
with imageless running and JIT, but repeatedly launches that failing compiler.
Twenty such attempts were retained. Their contribution to the account request's
ten-second timeout has not been measured independently.

The new V tool `art-no-image-aot.v` prepares a one-method source overlay for
[the ART source recorded by the runtime manifest](https://gitlab.com/android_translation_layer/art_standalone/-/blob/e78bf68917bcaaf58fef3960cd88793b3b7f39cc/art/runtime/oat_file_assistant.cc).
Its proposed GetBestOatFile condition permits compilation only when a boot image
is actually loaded. Existing cached-OAT selection and ReleaseFileForUse remain
byte-for-byte unchanged, as do the compiler success/failure branches. With no
image it leaves normal DEX loading, verification and JIT fallback in place.
With an image it preserves the original condition. It adds no runtime flag,
compiler wrapper, new allocation, trust change or JNI-check change.

This is a prepared source candidate, not an activated runtime fix. The native
bootstrap and deployed libart were not changed. A compiled ARM runtime and real
Maps retry are still required before making performance or authentication claims.
In particular, the source checks do not establish runtime behavior or ABI safety.

Usage with a source file from the selected ART build:

```sh
art-no-image-aot INPUT/oat_file_assistant.cc FRESH_OVERLAY
art-no-image-aot --self-test INPUT/oat_file_assistant.cc FRESH_CHECKS
```

The output contains art/runtime/oat_file_assistant.cc, no-image-aot.patch and a
receipt identifying the input, output and patch hashes. Apply the patch to a
fresh matching ART build tree before rebuilding, with the runtime's complete
existing 16-KiB/ABI patch set and dependencies. The tool refuses an existing
output, repeated application, missing includes/method boundaries and selected
changed compilation/cache/fallback anchors. It does not certify arbitrary
upstream revisions merely because these anchors match.

Host checks on the actual retained source passed exact restoration after
reversing the one replacement, seven source-shape mutations, output overwrite
refusal, zero-fuzz patch dry-run/application and unchanged original input.
The generated patch applied in a separate copy and matched the generated full
file exactly. Generated C++ and all test output remain outside Git.

Build and both checks passed the original explicit caps: RSS 629145600 bytes,
wall 300000 ms, reserve 1073741824 bytes, growth 536870912 bytes and output
4194304 bytes, exit 0/0 with complete cleanup. Tool compilation took 1396 ms,
peak sampled RSS 319635456 bytes and growth 122880 bytes. Self-test/preparation
took 218/208 ms and observed shared growth 26075136/26071040 bytes. The initial
r1 tool compile failed on V's Option/Result distinction; the corrected r2 is
the qualified tool. That failed log and receipt are retained separately.

Available `/Users/alex/code/v/v` reports V 0.5.2 9a38ec5, SHA256
f52821ef2d15507ef5238e36a5237c909dfbdbc09786671c5d87a3feb1ed843c.
No historical compiler was selected. The receipt's compile-time V source
revision annotation is distinct from this executable identity.

The native runtime checkout's art-runtime-manifest.json records the matching
ART source revision and GCC 15.2.0 on ARM64 musl. However, art-expected-source
contains only six audit source files, not a complete build tree or reusable
objects. The production recipe requires native ARM64 musl Linux because its
host tools execute during the build (see docs/android.md). This host is macOS;
the available stopped Lima guests are Ubuntu, without an identified matching
ART build/cache. A compatible native build environment remains the blocker to
compiling and qualifying this candidate. No test VM was started or left running.

All artifacts are under `/Users/alex/.local/state/vinix/android/`, with guard
logs/receipts beside their generated roots:

| Artifact | SHA256 |
| --- | --- |
| art-no-image-source-20261114-r1/oat_file_assistant.cc | ac0b1eb846b0ead3cdd5e827c2eeccbe63ef47f545b8973e28700377c1aad65b |
| art-no-image-tools-20261114-r2/source.v | 540a0527ef94f0032e7331934d3ffd5fde4c3038419329f7032188fe3d6ca5f2 |
| r2 art-no-image-aot | 14f1979a9c1be9f743bb13ce27312b4f43da1ffdc635cd079075228548ee50e3 |
| art-no-image-overlay-20261114-r1/art/runtime/oat_file_assistant.cc | b0dc593f6ae11ea7f2df977334cbdfffa0a594158b5c822bce742677224b03d1 |
| overlay no-image-aot.patch | b29b694ac2b1d103cd850b13584ad47c308639db75cd81852a077be537bd4484 |
| overlay receipt.json | ac1cba212921210c031d7e2e4a288c7f369a04c2f4b4eedbbe21a1422d4fcb2b |
| art-no-image-checks-20261114-r1.guard.log | cd2d96ba3111719ab3bdf1acaacb5a3897825f3bf254b1a3de3a65bf12e8b366 |
