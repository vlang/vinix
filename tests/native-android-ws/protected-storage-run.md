# Protected storage paired guest runner

`protected-storage-run.v` prepares and checks the small APK from
`protected-storage-fixture.v`. It does not launch QEMU. The retained general
suite launches a desktop, allocates a 12 GiB guest and only checks startup
markers, so this runner supplies a direct, bounded PID 1 controller instead.

Build the macOS host tool with the pinned V compiler, using one compiler at a
time and an external output directory:

```sh
/Users/alex/code/v-tccbin-bootstrap-20261026/v -new-compiler -nocache -gc boehm \
  -path 'tests/native-android-ws|build-support/android|@vlib|@vmodules' \
  -o /absolute/external/protected-storage-run \
  tests/native-android-ws/protected-storage-run.v
/absolute/external/protected-storage-run selftest
/absolute/external/protected-storage-run prepare \
  /Users/alex/.local/state/vinix/android/NEW_OUTPUT
```

The fixed input catalogs are checked before use. Preparation APFS-clones the
retained boot media and efivars, overlays the 400 KiB retained base module and
required native providers, and appends the fixture/controller plus matched
framework/JNI pair. It copies no SDK. Mesa provider files are selected from
the sealed `maps-account-r5` original runtime inventory, streamed directly
from its FAT runtime module, and installed at their original flat
`native-ws` paths, including Mesa EGL, `dri/swrast_dri.so`, LLVM and their
dependencies. The same provider bytes are used in both cases. The source
module digest is checked before and after preparation; licenses and source
archives remain in the retained original bundle. The inventory concatenates
original modules, so its conflicting `libdl_bio.so.0` translator entries are
excluded from that selection; the explicit sealed baseline translator is
retained. Every selected GPU provider must have a unique inventory entry.
Each deployed provider, translator, APK, framework JAR, JNI library and PID 1
binary is independently read back from the FAT module and hashed. Other
runtime dependencies remain inherited from the pinned boot image; the
small overlay is not a standalone runtime.
`prepared.json` records exact 2 GiB, two CPU QEMU argument arrays; run
the old and new cases sequentially. Preserve the complete external bundle,
including both serial logs and readback inventories.

The guest refuses existing data/home directories, launches the APK with
private directories and a held stdin pipe, and captures merged stdout/stderr.
It bounds output to 4 MiB, lines to 8 KiB, startup to 180 seconds and normal
shutdown to 20 seconds. The positive case waits for the exact full fixture
PASS line and `ANDROID-WS-READY`, closes stdin, drains output through EOF and
reaps the child. Failure cleanup owns only the launched process group.

After each case reaches the controller's DONE marker, stop only that case's
owned QEMU process, then validate its retained serial log:

```sh
/absolute/external/protected-storage-run check missing-field \
  /absolute/external/OUTPUT/old/serial.log /absolute/external/OUTPUT/old/result.json
/absolute/external/protected-storage-run check pass \
  /absolute/external/OUTPUT/new/serial.log /absolute/external/OUTPUT/new/result.json
```

The negative must show `NoSuchFieldError` for `credentialProtectedDataDir`
from fixture `org.vinix.bootstrap.Main.onCreate`, no PASS and child exit 1.
The positive requires unique exact PASS/close/exit markers, READY before
stdin close, clean child exit 0 and no failure markers. Only the exact known
caught `Main.bB:Lnge;` lookup diagnostic and its matching `nge` cause are
allowed together; mutated or unrelated lookup errors fail validation.

The before/after comparison intentionally changes both JAR and JNI. The new
JNI requires `vinixSetDataDirectory`, which the old JAR lacks, so mixing the
new JNI with the old JAR would test an unrelated startup failure. The APK,
controller and retained base runtime are shared; data/home directories and
APFS-cloned media are fresh and separate. This fixture proves logical
directory/context behavior only, with no encryption, unlock-state or Google
account authentication claim.

Target V source inventories use the exact Linux/arm64/new-compiler/gc-none/
static options used for the guest compile. Those sources and the explicit
`modulestream/spawn_abi.h` are frozen and hashed before/after compilation.
Selected tool binaries are pinned. This is not a hermetic C toolchain build:
system headers, target sysroot and toolchain libraries are not fully frozen.

## Validation on 2026-10-27

Host build and preparation evidence is retained at:

- `/Users/alex/.local/state/vinix/android/protected-storage-run-build-2026-10-27-r2`
- `/Users/alex/.local/state/vinix/android/protected-storage-guest-validation-2026-10-27-r2`

The host build passed in 4.26 seconds with maximum RSS 339,165,184 bytes;
the 22-case semantic selftest passed with maximum RSS 3,768,320 bytes.
Whole preparation, including the guest compilation, both media overlays,
four-way payload readbacks and full input rehashing, passed in 56.31 seconds
with maximum RSS 350,863,360 bytes and zero swaps. Both target V inventories
match; their frozen source tree is 2.2 MiB.
The first preparation (`r1`) is retained but was not qualified for boot:
its source inventory selected host files rather than the compiled Linux
target. The coherent `r2` preparation corrects that inventory and includes
the reviewed child cleanup and output-tail fixes. Its old guest then failed
before ART: `libvinix-ws-mesa-EGL.so` was missing and graphics dispatch failed.
The strict checker rejected that run because the required protected-field
failure was absent; it produced no successful result JSON. The failed `r2`
bundle is preserved. Its provider directories were incorrectly nested under
`egl-ws`/`vulkan-ws`, and its readback covered only four application payloads.
The subsequent `r3` preparation selects original runtime provider paths and
checks every deployed provider as well. No fixture success or authentication
success follows from the `r2` run.

The fixture APK is 17,031 bytes, SHA-256
`786681da81d8b075e38f844014ab767e26f4388bfb5f8bf62e4cd380c978f0e6`.
The old JAR/JNI SHA-256 values are
`71d05c6e6288978de66a5c71279e8cb27d92c9166950813ddbf0c33ff86e1d0d`
and `70b8db58c59d769f4f4ae4e6775fb7c3a2c4c9af42cfd3f14076092ec14818c0`;
the new pair is
`a8ba34eb79be2473f89042c8ee940ab1994dbc902c3d45143877f8891d3b428b`
and `05ed64c8c0778cc09ea2db7d820c873c7e53c493f99c886c4992f3243f8f913a`.
Full producer seals, source revision, source/tool hashes, command arrays and
independent deployed-payload hashes are retained in the external bundle.
Preparation recorded source base `7c1b86aec7e8e35dcba1267fb42b53105d72b86d`
plus runner source SHA-256
`ddf91eb41cfb3aacd7b6b8e8a398404519b798c70cb1d02947be442ee2ff86b0`.
The prepared manifest SHA-256 is
`d8c792beea9bb3c47605f014570713544a5231d4970d71c038123f2837d8a26e`.
Guest controller SHA-256:
`fa9e0888a8f28cf5794028b5c38b30e6c52351c0baa0d25b5edbac142ee46394`.

The provider correction is prepared at
`/Users/alex/.local/state/vinix/android/protected-storage-guest-validation-2026-10-27-r3`;
its build and test logs are in the corresponding
`protected-storage-run-build-2026-10-27-r3` directory. The selective FAT
extraction test passed in 13.83 seconds with maximum RSS 158,842,880 bytes,
including success, missing input/member and invalid path cases. The host
build passed in 7.34 seconds with maximum RSS 360,513,536 bytes; all 22
semantic tests passed with maximum RSS 3,751,936 bytes. Whole preparation
passed in 71.50 seconds with maximum RSS 354,369,536 bytes and zero swaps.
It installed the same 18 provider/translator files (117,846,960 bytes) in
both cases, verified all 22 deployed payload hashes per case, and matched
the Linux target source inventories. The rebuilt checker also rejected the
actual failed `r2` serial log with exit 1 and no successful result JSON.
Both `r3` guest cases subsequently passed the strict checker, as detailed
below.

The `r3` preparation recorded source base
`d32325678505b726b2e89a572e58baafac569af4` and runner source SHA-256
`709643eca22b99523765a18ed8a843fe3ac7b9a01335c165982826fab4afaced`.
Its prepared manifest SHA-256 is
`a3567dfc87d2e02bf7d7deb331eeb43d38ec308daa83a5c87b336c4283552e5d`;
guest SHA-256 is
`66673e91ffb5fa9381f4dbdb4ecfd41486197e530c59fa0272c43401ec03b0ab`.
The original runtime module SHA-256, checked before and after extraction,
is `1c6988d1f3d3844425f0e8cbb49a878b3a16f2a270b4eb3852c71dfaa8fe200e`;
the complete original inventory SHA-256 is
`d3c2fcc3ede63edc181729940123929c60acb07fdf2d76972f0bd41e3a6f5423`.

## Paired guest result

The reviewed runner/provider change is commit `15fd6d2eb`. The old and new
guests ran sequentially with the recorded 2 GiB/two CPU arguments. The old
case produced the direct `ApplicationInfo.credentialProtectedDataDir`
`NoSuchFieldError` at fixture `Main.onCreate`, then child exit 1 and the
expected controller DONE marker. The new case produced its exact PASS at
serial line 302, READY at 313, stdin close at 314, activity destruction,
child exit 0 at 322 and DONE at 323. Both serial logs include the captured
app stderr and drained output tail. Repeating both strict checks produced
byte-identical result receipts; an independent read-only review agreed.
The ART AOT warnings preceded app execution; this run does not qualify AOT
compilation.

The host stopped each owned QEMU after its guest DONE marker.
Recorded identities bind old PID 21290 and new PID 22961 to their respective
images and serial paths; a subsequent PID query confirmed both absent.
QEMU stderr records SIGINT cleanup, rather than guest-initiated VM shutdown.
The old process ran for 42.10 seconds with maximum RSS 1,825,505,280 bytes;
the new ran for 35.10 seconds with maximum RSS 1,834,090,496 bytes. Both
recorded zero swaps. Repeated host checks peaked at 5,292,032 and 6,258,688
bytes respectively. These are host process measurements, not guest heap
measurements.

Old serial SHA-256:
`9709da1f6fef4ae3d27462c62ee6428a5c27da66de680356dd4f2e9cf2df9092`;
new serial SHA-256:
`cd55fad1c2c4e7b134982e37931069074dc4294c0eaa26b4ee888666cc4f56a1`.
Their result receipts are respectively
`33308d4873a34ff9892397ec7cbe92cd38758c70b1d07c7e80c36f25aef101de`
and `bc0afb3e07926fbbcdda723508a584cce5e105678f4873fb82aff20246d82ad2`.
The preparation receipt remains unchanged; the post-run results are
separate files. This confirms the paired framework/JNI protected-storage
fixture only. Map rendering and Google account authentication remain
outside its scope.

The complete closed evidence is bound in place by the stream seal at
`/Users/alex/.local/state/vinix/android/protected-storage-guest-closed-2026-10-27-r3`,
manifest SHA-256
`ee7ab9acf6d06cf352205fbc1b3cf49e1be6bc414c6328da1898859210c036ab`.
Its 20 roots include both complete guest preparations, the preserved failed
`r2`, build/test logs, the full direct fixture/framework/JNI/runtime/suite
producer directories, audit receipts, selected tool binaries and the sealer
build plan. The exact root list and repeated-check receipts are retained at
`/Users/alex/.local/state/vinix/android/protected-storage-guest-audit-2026-10-27-r3`.
Retain every listed root and all original producer bundles; this integrity
inventory does not replace their historical checkers or qualify deletion.
No files were added to the guest preparations after sealing.
The seal and its built-in complete recheck passed over 39,806 entries in
301.23 seconds with maximum RSS 24,772,608 bytes and zero swaps. The timing
and PASS transcript is retained outside the sealed roots at
`/Users/alex/.local/state/vinix/android/protected-storage-guest-seal-2026-10-27-r3.log`,
SHA-256 `45a960ceba10e020c14ff6121b3ba64d14080106385d6775f629b9047e3f190b`.
