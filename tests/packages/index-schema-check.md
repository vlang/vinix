# Unambiguous signed repository metadata

Consumers authenticate the original index bytes before applying strict typed,
field-presence and key-uniqueness checks. Format-1 envelopes require every field;
package, dependency and payload records retain every canonical declaration.
Unknown or duplicate fields, escaped duplicate spellings, null collections and
coerced counters are refused. The legacy omitted `window_protocol` still means
zero. Unique escaped names, whitespace and reordered object fields remain valid.
The publisher's existing canonical bytes and signatures are unchanged.

The follow-up [bounded signed-index decoder](index-decode-check.md) replaces
generic typed decoding with owned bounded primitives, retains this signed-schema
contract and qualifies complete/partial decoder lifetimes. The recorded results
below retain the original scanner-only allocation scope.

The subsequent [publisher manifest reader](manifest-decode-check.md) also bounds
source-template and packed-inventory decoding, preserves source defaults and
qualifies owned results and partial failures. Signed declarations and the
historical measurements below retain their original scope.

The shared key scanner now checks each object's required fields and each known
field's JSON value kind without decoding the whole document a second time.
Explicit array checks cover a pinned-compiler strict-decoder gap that accepts
`null` array fields. Scanner key sets and rejected fully decoded records retire
their owned buffers. Signature verification frees its temporary key, signature
and message buffers. Stored states share the same independently decoded package
cleanup; in-memory plans continue to borrow manifests.

Measurement found retained key strings from implicit typed string pushes and
the reader's promoted heap object. Key insertion now transfers ownership, and
the bounded shared SDK key reader explicitly releases its own object. Its
Unicode/escape/boundary assertions supplement the schema tests.

Publisher source templates keep their documented omitted-field defaults while
rejecting ambiguous fields/types. Stored packed inventory manifests require all
declarations before publication. The fixture checks publication refusal without
replacing the previous index and exact canonical reproduction after restoration.

Host assertions cover signatures before schema admission, every required field
at each level, nested/escaped duplicates, unknown keys, explicit booleans,
null/invalid collections, numeric bounds, both architectures and native window
protocols 1/2. Service fixtures sign malformed newer indexes and check failed
refresh/enrollment preserve configuration, cached catalog, replay history and
installed generation, remove staging and leave the cached upgrade review usable.

The 1,000-cycle allocation fixture measures only owned key/type/presence scanning
of prevalidated text, including valid, duplicate, missing and unknown cases.
It does not claim allocation-free typed JSON failure or full service lifetimes.

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -no-skip-unused -gc none -manualfree \
  -o /tmp/index-schema tools/packages/pkgcore/index_schema_test.v
/tmp/index-schema
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -no-skip-unused -gc none -manualfree \
  -d track_heap -o /tmp/index-schema-memory tools/packages/pkgcore/index_schema_test.v
/tmp/index-schema-memory
```

The administrator guest scenario requires signed malformed-index refusals through
the staged CLI and enrollment writer on both architectures, with unchanged
catalog/history/configuration/state and successful refresh after restoration.
Each malformed-index case runs in a fresh worker and requires CLI exit 1 without
a panic. The command helper reports fork/pipe failures; those cannot count as a
metadata rejection. The dependency graph also runs in its own worker, keeping
the fixture within process resource limits without changing those limits.
The original signed ordinary-account install/progress, policy, remove/rollback,
trust revocation and large dependency-graph checks remain required. This qualifies
metadata and service behavior, not public publisher enrollment or graphical login.

All 28 core runners, 11 SDK protocol runners, signed CLI contracts and both sanitizer configurations passed. The scanner retained **zero tracked bytes** over 1,000 cycles.

Both QEMU TCG guests passed with clean shutdown and eight verified hashes each: AArch64 **88.849 seconds**, x86_64 **145.049 seconds**.

The large dependency graphs and each metadata case run in separate fresh workers after diagnostics found allocation refusal near the AArch64 fixture mapping budget. The guest command helper now reports fork/pipe failures instead of returning a false success; a malformed-index refusal requires CLI exit 1 without a panic. All state assertions and resource limits remain intact. Initial build/disk/allocation attempts are retained.

- [AArch64 receipt](results/2026-10-14/index-schema-aarch64.json), [serial](results/2026-10-14/index-schema-aarch64.serial.txt), [QMP](results/2026-10-14/index-schema-aarch64.qmp.txt).
- [x86_64 receipt](results/2026-10-14/index-schema-x86_64.json), [serial](results/2026-10-14/index-schema-x86_64.serial.txt), [QMP](results/2026-10-14/index-schema-x86_64.qmp.txt).
- [Host checks](results/2026-10-14/index-schema-host.txt), [initial attempts](results/2026-10-14/index-schema-attempts.txt), [source/compiler/artifact ledger](results/2026-10-14/index-schema-toolchain.json).
