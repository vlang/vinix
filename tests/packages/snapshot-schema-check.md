# Cached repository snapshot admission

Follow-up [bounded snapshot decoding](snapshot-decode-check.md) qualifies complete
decode and file-reader lifetimes. The recorded results below keep their original
schema-scanner and lifecycle scope.

The baseline reader accepted a root null as an empty cache, ignored unknown and
duplicate fields, defaulted an omitted URL and treated a dangling cache link as
absence. The baseline probes exercise the production `read_snapshots` function.

Present caches now require an array of complete snapshot and repository objects.
Field kinds and unique decoded key names are checked after strict typed decoding.
Repository identities share configuration validation and must have distinct IDs;
both configuration and cache support at most 4,096 repositories. Signed text and
bounded signature strings must be present and nonempty. Signed bytes, legacy
signature whitespace and canonical writer encoding remain unchanged. Signature,
expiry and replay-floor authentication still occur through the existing paths.
Fresh absent caches and explicit empty arrays remain valid.

[Core assertions](../../tools/packages/pkgcore/snapshot_schema_test.v) cover every
required field, null/coerced values, escaped duplicate keys, malformed Unicode,
identity/source errors, bounds and exact decoded bytes. A signed lifecycle removes
history to exercise authenticated legacy-cache migration, exposes an older signed
repository, and checks that malformed cache refusal preserves configuration,
activation, current/previous payloads, cached objects and interrupted recovery
work. Restoring the original cache still rejects the older sequence, permits the
original reviewed install, and allows authenticated renewal. Revocation and
uninstall remain usable with a damaged cache.

The maintained [CLI lifecycle](distribution-cli.v) checks exit 1 and useful cache
diagnostics without a panic before refresh, enrollment, planning or acquisition.
Payload verification remains available. Restoring the cache permits refresh and
the remaining signed deployment/mirror/rollback/uninstall workflow.

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' -d track_heap \
  -o /tmp/package-snapshots tools/packages/pkgcore/snapshot_schema_test.v
/tmp/package-snapshots
```

Allocation tracking covers only owned schema key/type/required-field scanning
over 1,000 cycles, not whole decoding or service lifetimes. ASan/UBSan disables
leak detection. Static target builds do not qualify guest execution or crash
durability. These local metadata checks do not prevent an unrestricted
administrator from replacing valid records; recover original cache/history under
the writer lock rather than guessing missing fields or resetting lists.
Publisher enrollment, catalog migration and graphical/runtime acceptance remain
separate roadmap gates.

All eight core runners and the full signed CLI lifecycle passed. The snapshot
schema scanner retained zero tracked bytes over 1,000 cycles. The primary
schema and legacy migration lifecycle passed ASan/UBSan. Both maintained stages
built static service/session/Linux-runner binaries and checked target ELF
machines. Compiler/generated-C warnings are retained in private build logs.

- [Host, CLI, allocation and target results](results/2026-10-14/snapshot-schema-host.txt).
- [Before/after probes](results/2026-10-14/snapshot-schema-baseline.txt), [sanitizers](results/2026-10-14/snapshot-schema-asan.txt).
- [Source/compiler/artifact ledger](results/2026-10-14/snapshot-schema-toolchain.json).
