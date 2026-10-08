# Native Android runtime staging

`runtime-query.v` owns the complete production `build.py` workflow in V:
streamed SHA reads, cached and temporary downloads, APKINDEX resolution and
six-worker package fetches, concatenated APK extraction, library aliases,
font relocation, calculator extraction, overlay validation, staging, cache
reuse and post-parser defaults. The Python front retains its public signatures,
metadata and argparse interface. Its existing public callbacks remain mockable.

The appended `_build_*` bindings in `_boot_native.py` call standard-library
operations, retain original objects and exceptions, and use the shared
`native_host.Controller`. Records, Paths, Namespace fields and module results
remain their original Python objects; each worker owns its own transport and
resource tables. Iterator completion is tagged separately from a yielded None.
The original bootclasspath binding prefix and wire functions are unchanged.

Managers and entered values have distinct ownership. V explicitly exits every
normal stream, ZIP and tar scope before using its result or returning its
exception. Normal exit returns are ignored; exceptional exits retain the
original error and supplied traceback property relation and preserve deliberate
traceback clearing or replacement. Abrupt transport death retires remaining
managers through the standard-library ExitStack in reverse order, including
inner suppression and replacement errors. Query children have a separate
process group; shared transport cleanup masks SIGINT while closing pipes and
performing bounded wait/kill/reap and resource retirement. Python 3.9 active
traceback frame lists still include the replay and transport frames.

The staging cache retains its original ordered inputs and appends a deterministic
maintained controller closure: `_boot_native.py`, `runtime-query.v`, shared
`native_host.py`, and sorted V/ABI files from runtimebuild, boothost, androidhost,
fixturehost and hosttest, excluding helper test files from the added closure.
The runtime compiler's existing `inputs()` contribution remains intact. The
compiled controller's executable bytes are not cache inputs. This intentionally
invalidates older cache keys and makes future native-source edits invalidate
staged artifacts.

Qualification used the frozen original builder at
`cdc36ad78c4b76c7b25e6649617bc7f27325a761` (21,957 bytes, 416 lines;
SHA256 `8537a6cf06d54619e5581590eba2f331cb29bea47af7a0aa0986405f1e43e800`)
and the immutable V 0.5.2 compiler
`6d549c2f095d5e3e97963e55a2ebf1dc2810db46`. ARM64, actual x86_64 and ARM64
ASan/UBSan passed 112 original/native workflow, partial-filesystem, malformed
input, error, identity and manager controls per profile. Each also passed 13
retirement controls, including 100 requests with stable descriptor counts,
five exact parser CLI pairs, three actual curl file transfers and a real
process-group interrupt during a blocked read callback. Both host architectures
passed cold compiler installation through `run-v-tool.sh`.

All unchanged independent fixtures passed per profile: 26 ART/Bionic/ATL,
nine bootclasspath and ten musl tests. Both original and extended cache keys
were independently reproduced; changing each of the 51 added maintained inputs
in a private copied tree invalidated cache reuse on every profile. A peer reviewed
all new lifetimes before commit. This is host workflow validation, with no new
kernel, physical Android, full guest or device execution claim.

Gross original policy migrated: 17,986 bytes / 314 lines. After counting the
7,393 added Python binding bytes, the scoped change removes 9,291 Python bytes
and 139 Python lines. Metadata, parser and generic bindings remain honestly
counted. Local frozen sources, exact logs, byte/mode/link snapshots, cache-input
identities and receipts are in
`~/.cache/vinix-python-to-v/android-runtime-builder-20261009/`; the qualification
receipt SHA256 is
`f4c7eebe02dcc7fd51f23a0ac30d83ce2cb763087e27b9f4dd4c14d8f0c214a4`.
That directory is local evidence, not a runtime
dependency. Rebuild the controller with `build-support/run-v-tool.sh
build-support/android/runtime-query.v --install-query /tmp/android-runtime-query`
and set `VINIX_ANDROID_RUNTIME_QUERY` to exercise the unchanged Python fronts;
`tests/android/art-runtime-test.py -v`, `bootclasspath-test.py -v` and
`musl-runtime-test.py -v` exercise the committed independent fixtures.
