# Administrator envelope ownership

Package administration sends a canonical format-1 request through the fixed
`packages-change` action and binds worker completion to its SHA-256. Successful
decoding previously retained temporary storage; late malformed input retained
partial decode/error storage, and receipt construction/validation retained the
one-shot hash context and digest.

The decoder now reads only the existing fixed envelope, without recursive JSON
values. It owns every accepted nonce/argument and frees partial fields, the
argument table, reader and quoted-string buffer on refusal. The complete
request still passes command validation and exact re-encoding before acceptance.
`Request.close()` remains repeatable. Receipt construction and validation share
an owned hash helper that retires the encoded request, bytes, SHA-256 context
and checksum. Failed receipt construction also retires its error before returning
the existing empty result.

The format, key order, escaping, literal path bytes, command allowlist, review
fingerprints, 69-argument/4,096-byte bounds and completion status rules are
unchanged. Malformed JSON/schema input now gets bounded administrator-envelope
diagnostics rather than general JSON decoder context. Ordinary command and
completion validation retain their existing diagnostics. No authorization rule,
password handling, transaction state or kernel behavior was changed.

## Measurements

Matched probes use sources from `fe668b6da`, the same frozen compiler, the same
caller-owned inputs, and explicit retirement of returned owners and errors.
Shared JSON type metadata is initialized outside tracking. Each probe repeats
five times:

| Probe | Previous retained bytes | Final retained bytes |
| --- | ---: | ---: |
| Encode | 0 | 0 |
| Decode and close | 400 | 0 |
| Late invalid argument | 5495 | 0 |
| Receipt construction | 1705 | 0 |
| Valid receipt check | 1705 | 0 |
| Invalid receipt check | 1705 | 0 |

The final fixture measures **58 windows**, each retaining zero user allocation
bytes:

- Sixteen command/boundary cases repeated 1,000 times, including all reviewed
  operations, literal escaping/Unicode, 69 arguments and an exact 4,096-byte
  envelope. Two independently owned decodes survive release of the source and
  one sibling. Repeatable close and eight cycled completion statuses are checked.
- Every one of the 4,096 truncated prefixes of the largest legal request.
- Twenty-eight malformed, noncanonical, type, control-byte and size cases,
  each repeated 1,000 times, including partial values and deep nested input.
- Excess argument counts, oversized encode/decode and failed receipt
  construction repeated 1,000 times.
- Twelve invalid completion cases repeated 1,000 times, including wrong request
  identity, leading-zero/negative/oversized status, trailing bytes and long input.

An independent previous/final fixture produces **537 identical compatibility
rows**: canonical encoding and receipt hashes, reviewed operations/eight
statuses, every path byte 32–255 including non-UTF-8 bytes, malformed/truncated
refusals and exact argument/byte boundaries. It checks acceptance and bytes;
general malformed-JSON diagnostic wording is intentionally not compared.

These are live user allocation bytes, not allocator residency or kernel memory.
The protocol fixture performs no repeated socket allocation and needs no
endpoint reclamation waits.

## Qualification, 2026-10-16

All **32 focused native compile/run checks passed**, covering
protocol/account/launch/administrator regression fixtures,
tracked ownership, ASan/UBSan, signed CLI lifecycle/driver builds, compatibility
pairs and matched probes. ASan/UBSan disables leak detection; allocation
retirement is measured separately. Test fixtures retire only the table when a
shallow clone borrows strings.

Both target guests run all ownership windows as root and UID 1000, plus existing
protocol, account-rule and private-socket companions. Fresh package/account tools
also run the real authenticated administrator scenario, including passwords,
reviewed install/remove/rollback, progress, stale/role/trust refusals, metadata,
policy/deployment operations, audit and clean runtime state. Runs use the
unchanged isolated tracking kernels from socket qualification and require clean
guest-initiated QMP shutdown. Receipts pin staged tools and kernels.

| Architecture | Ownership fixture, root and UID 1000 | Authenticated administrator workflow |
| --- | --- | --- |
| AArch64 | PASS, 116 zero-retention windows, 37.4 s | PASS, 28.7 s |
| x86-64 | PASS, 116 zero-retention windows, 69.4 s | PASS, 36.6 s |

This closes measured administrator request/completion protocol storage. It does
not establish flat allocation across the administrator client, action runner,
password or UI workflow. Production publisher/catalog rollout, foreign-runtime
qualification and graphical session/display integration remain broader roadmap
14 gates.

Repeat from the repository root:

```sh
v -nocache -no-skip-unused -gc none -manualfree -d track_heap \
  -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/admin-envelope \
  tools/packages/pkgadmin/ownership_test.v
/tmp/admin-envelope
```

The target controller is `tests/packages/admin-envelope-runtime-check.v`, using
`--arch aarch64|x86_64 --kernel PATH --state-dir NEW_SHORT_DIRECTORY`.
The distribution driver includes the tracked fixture.

- [Native checks](results/2026-10-16/admin-envelope-host.json), [summary](results/2026-10-16/admin-envelope-host.txt), [tracked windows](results/2026-10-16/admin-envelope-memory.txt), [sanitizers](results/2026-10-16/admin-envelope-asan.txt), [CLI lifecycle](results/2026-10-16/admin-envelope-cli.txt)
- [Matched probes](results/2026-10-16/admin-envelope-comparison.txt), [V probe](results/2026-10-16/admin-envelope-comparison.v), [537 compatibility rows](results/2026-10-16/admin-envelope-compatibility.txt), [V compatibility fixture](results/2026-10-16/admin-envelope-compatibility.v)
- [Generated-C review](results/2026-10-16/admin-envelope-generated-c.txt), [source/toolchain/artifact pins](results/2026-10-16/admin-envelope-toolchain.json)
- [AArch64 receipt](results/2026-10-16/admin-envelope-aarch64.json), [serial](results/2026-10-16/admin-envelope-aarch64.serial.txt), [real administrator receipt](results/2026-10-16/admin-envelope-aarch64.admin.json), [serial](results/2026-10-16/admin-envelope-aarch64.admin.serial.txt)
- [x86-64 receipt](results/2026-10-16/admin-envelope-x86_64.json), [serial](results/2026-10-16/admin-envelope-x86_64.serial.txt), [real administrator receipt](results/2026-10-16/admin-envelope-x86_64.admin.json), [serial](results/2026-10-16/admin-envelope-x86_64.admin.serial.txt)
