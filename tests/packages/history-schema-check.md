# Persistent repository history admission

The previous consumer reader accepted `repositories:null` or an omitted list as
empty trust history. After revocation and an empty refresh removed cached
snapshots, a valid older signed index could be enrolled again. `publish-release`'s
equivalent `indexes:null` also reset its durable sequence reservation and allowed
an older release. The before-change CLI reproduction uses signed empty catalogs:
it accepts sequence 1 after remembering/reserving sequence 10 on both paths.

Both readers now share strict typed, field-presence, key-uniqueness and explicit
value-kind checks. Present files require an object envelope, format and collection,
plus each floor's ID, publisher key, positive sequence and index digest. Root
null, missing/null arrays, unknown/duplicate/escaped duplicate fields, coerced or
overflowing counters and invalid or duplicate identities are refused. The two
envelope collection names remain distinct. Explicit empty arrays, uniquely
escaped keys, sibling records and maximum u64 sequences remain valid.
Canonical writer bytes and the 4,096-identity limit are unchanged. Independently
decoded rejected records and input text release their owned buffers; histories
constructed from borrowed floor records do not use this cleanup helper.

An absent file still permits initial creation or authenticated legacy-snapshot
migration. A malformed present file is preserved and stops acquisition/enrollment
or publication. It is never rewritten as empty history. Administrators must
restore retained trusted history under the package/publisher writer lock;
deleting history loses the recorded replay floor. This is local metadata
validation, not protection against a root administrator deliberately editing or
deleting valid records. Revocation remains available without readable history.

Core assertions cover schema admission, canonical reproduction, numeric and
collection limits, and both history domains. The service fixture checks failed
refresh, reviewed install/review, mirror export and enrollment preserve installed
and previous generations, cached payload hashes, configuration, signed catalog,
damaged history and staged recovery data. Restoring the file permits the original
reviewed install, verification and rollback. Existing administration tests retain
legacy migration, key rotation, empty refresh and revocation coverage. Publisher
fixtures preserve prior release bytes and reject new staging/publication before
restoring history for an exact retry.

The real CLI requires exit 1, a history diagnostic and no panic for malformed
consumer history after revocation/empty refresh while an older signed index is
available. Restoring valid history still refuses that replay, then permits a
current signed index. Publisher CLI checks reject damaged history and retain the
prior release's exact signed bytes. The existing complete signed CLI lifecycle
also runs.

Allocation checks measure only owned key/type/required-field scanning over 1,000
valid, missing, unknown and duplicate cycles per history domain. They make no
whole-decoder or service lifetime allocation claim. Sanitizers disable leak
detection; static target builds do not claim guest execution.

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -nocache -no-skip-unused -gc none -manualfree \
  -d track_heap -o /tmp/history-schema tools/packages/pkgcore/history_schema_test.v
/tmp/history-schema
```

Public publisher enrollment, catalog migration and graphical/runtime acceptance
remain separate roadmap gates.

All four affected core runners and the complete signed CLI contracts passed. Each history scanner retained **zero tracked bytes** over 1,000 cycles. History admission, service recovery and publisher lifecycle passed clang ASan/UBSan with leak detection disabled. Both target services built as static ELF binaries with machine checks; no guest execution is claimed.

- [Host, CLI and build results](results/2026-10-14/history-schema-host.txt).
- [Before-change replay/rollback reproduction](results/2026-10-14/history-schema-baseline.txt), [sanitizers](results/2026-10-14/history-schema-asan.txt).
- [Source/compiler/artifact ledger](results/2026-10-14/history-schema-toolchain.json).
