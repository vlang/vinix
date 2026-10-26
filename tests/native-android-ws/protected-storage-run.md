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
framework/JNI pair. It copies no SDK. Each deployed APK, framework JAR, JNI
library and PID 1 binary is independently read back from the FAT module and
hashed. `prepared.json` records exact 2 GiB, two CPU QEMU argument arrays; run
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
match; their frozen source tree is 2.2 MiB. Guest execution is pending.
The first preparation (`r1`) is retained but was not qualified for boot:
its source inventory selected host files rather than the compiled Linux
target. The coherent `r2` preparation corrects that inventory and includes
the reviewed child cleanup and output-tail fixes.

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
