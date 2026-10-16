# Isolated launch envelope ownership

The existing isolated launch wire schema and completion receipt are unchanged.
A private reader now parses the fixed canonical request envelope without the
generic JSON decoder's retained temporary storage. Each accepted nonce and
argument string belongs to the returned `Request`; `close()` releases them
and resets the result. Partial strings, records and array growth buffers are
released on refusal. The reader's own storage is explicitly retired too.

The wire contract already required byte-exact `Request.encode()` output.
Parsing preserves that requirement, the format/field order, lowercase nonce,
five launch modes, 772-value envelope, 512 KiB wire limit, 256 argument/document,
4096-byte value and 64 KiB command limits. Canonical JSON control escapes are
decoded, while ordinary argument bytes retain their existing non-NUL Unix
contract, including byte sequences that are not UTF-8. The existing encoder
still checks semantic limits and canonical equivalence before acceptance.

Completion receipts now retire the SHA-256 context, its internal buffers and
the raw digest before returning their existing nonce/hash/code text. Invalid
request receipt generation releases its error too. The completion receiver
keeps its 129-byte bounded array on the stack and retires an owned copy of the
received text after validation. Generated C inspection checks that this buffer
is no longer promoted to unretired heap storage.

Matched probes use unchanged production sources from `62a4345c2`, the same V
fixture/options and explicit retirement of returned requests, text and errors.
Five cycles retained 1035 bytes for owned decode, 3515 for malformed decode,
1705 for receipt generation, 5 for request wire transfer and 4055 for completion
wire transfer. Descriptor-rights transfer already retained zero and its
implementation is unchanged. Every final probe retains zero. Counts depend on
the fixture's literal inputs; they measure parent user-space storage, not kernel
allocations or allocator residency.

The independent previous/current compatibility fixture produces **162 identical
rows**, including **54 identical receipt values**. It covers all five launch
modes, non-NUL byte values, escaped controls/Unicode, empty strings, maximum
argument count and escaped 64 KiB input, accepted exit codes and schema/limit/
truncation refusals. Diagnostic wording may differ; acceptance and wire bytes
retain their existing contract.

The native tracked ownership fixture exercises:

- Six accepted literal/mode/count cases, 1000 decode/close cycles each, plus
  16 heavily escaped 64 KiB requests. Independent sibling results outlive their
  encoded input, and repeated close is safe.
- Every truncated prefix of a request and 33 malformed/schema/limit cases,
  each of the latter repeated 1000 times with partial state retired.
- Six 1000-cycle request/three-rights/completion roundtrips preserving codes
  0/37/126/127/143/255, plus two invalid receipt-generation paths. Descriptors
  retain close-on-exec protection and no descriptor accumulates.
- Nine malformed/tampered/oversized completion cases, five truncated/oversized
  request packets and closed-descriptor read errors, each repeated 1000 times.

The main wire fixture transfers independent `/dev/null` descriptors. The existing
companion separately checks distinct stdin/stdout/stderr pipes and closes
surplus rights on rejection. Sustained socketpair churn exhausted resources on
the pinned target kernels, including with independent streams: `socketpair`
returned ENOMEM while only three or four descriptors were open. Flat user heaps
and descriptor counts do not establish why those kernel resources were
unavailable. Original logs are retained; no kernel source changes are involved.

Native wire stress therefore retains 1000 cycles per case, while the guest
worker explicitly defines `transport_guest` for **16 wire cycles** per case.
Guest decoding, malformed-envelope, invalid-receipt generation and invalid-fd
read checks retain 1000 cycles. Every measured window must still retain zero
bytes, and wire descriptor counts remain flat. Guest wire behavior is qualified
at that shorter count; sustained guest socket churn remains open. The initial
AArch64 log also records a fixture mistake: shortening code `37` to `3` yields
another valid receipt. The corrected truncation removes the entire code.

The final partial-request fixture closes its peer completely to model an
interrupted client. An earlier half-close variant was stopped while the guests
were waiting through poll deadlines; those logs are retained too. Half-close
poll latency is not qualified by this increment.

Native protocol/stream, command/ownership, account-session planning, launch-plan
ownership and administrator protocol/socket fixtures run alongside ASan/UBSan
and tracked assertions. The signed CLI repository/install/update/rollback/remove
lifecycle and distribution-driver build also run. The distribution driver now
includes the tracked transport fixture. The guest suite runs the ownership
fixture as root and UID 1000, followed by protocol, stream and command companions,
and records the target account-session executable as an artifact.

These checks cover the request/receipt and descriptor-transfer primitives. They
do not establish allocation retirement across authentication transactions,
the complete privileged client workflow, graphical login/display integration
or additional foreign runtime compatibility. Roadmap 14's production publisher,
advertised catalog, graphical and broader runtime/filesystem gates remain open.

## Recorded results, 2026-10-16

All **36 focused native compile/run checks** passed: nine core pairs, tracked
and ASan/UBSan pairs, two matched-probe pairs, two compatibility pairs, four
CLI/driver checks and two guest-tool builds. The six final allocation probes
retain zero, and all 162 compatibility rows match the previous implementation.

Fresh QEMU TCG guests passed with clean shutdowns: AArch64 **41.3 seconds** and
x86_64 **42.9 seconds**. Both ran root and UID 1000 at the explicit counts above,
with zero retained user bytes in every measured window. Each receipt's eight
artifact hashes were verified, including the target account-session helper.
The durations qualify functionality rather than performance. The retained
ENOMEM and stopped half-close runs remain separate from these receipts.

Repeat the native allocation fixture from the repository root:

```sh
v -nocache -no-skip-unused -gc none -manualfree -d track_heap \
  -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/launch-transport \
  tools/packages/pkglaunch/ownership_test.v
/tmp/launch-transport
```

The guest controller is `tests/packages/launch-transport-runtime-check.v` with
`--arch aarch64|x86_64 --kernel PATH --state-dir NEW_DIRECTORY`. It enables
tracking on the ownership worker only. Use a short new state path for its QMP
socket. Copy the retained V probe/compatibility
fixtures into isolated previous/current `pkglaunch` copies as
`transport_comparison_test.v` and `transport_compatibility_test.v`; define
`transport_baseline` only for previous comparison sources. The original guest
logs are retained separately from final qualification receipts.

- [host checks](results/2026-10-16/launch-transport-host.json), [summary](results/2026-10-16/launch-transport-host.txt)
- [core assertions](results/2026-10-16/launch-transport-core.txt), [tracked allocations](results/2026-10-16/launch-transport-memory.txt)
- [sanitizers](results/2026-10-16/launch-transport-asan.txt), [CLI lifecycle](results/2026-10-16/launch-transport-cli.txt)
- [matched probes](results/2026-10-16/launch-transport-baseline.txt), [V probe](results/2026-10-16/launch-transport-comparison.v)
- [compatibility output](results/2026-10-16/launch-transport-compatibility.txt), [V fixture](results/2026-10-16/launch-transport-compatibility.v)
- [source/toolchain/artifact pins](results/2026-10-16/launch-transport-toolchain.json)
- [generated-C completion-buffer review](results/2026-10-16/launch-transport-generated-c.txt)
- [initial AArch64 fixture log](results/2026-10-16/launch-transport-aarch64.before.serial.txt), [initial x86_64 log](results/2026-10-16/launch-transport-x86_64.before.serial.txt)
- [AArch64 socket exhaustion](results/2026-10-16/launch-transport-aarch64.stress.serial.txt), [x86_64 socket exhaustion](results/2026-10-16/launch-transport-x86_64.stress.serial.txt)
- [AArch64 stopped half-close fixture](results/2026-10-16/launch-transport-aarch64.partial.serial.txt), [x86_64 fixture](results/2026-10-16/launch-transport-x86_64.partial.serial.txt)
- [AArch64 receipt](results/2026-10-16/launch-transport-aarch64.json), [report](results/2026-10-16/launch-transport-aarch64.txt), [serial](results/2026-10-16/launch-transport-aarch64.serial.txt), [QMP](results/2026-10-16/launch-transport-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/launch-transport-x86_64.json), [report](results/2026-10-16/launch-transport-x86_64.txt), [serial](results/2026-10-16/launch-transport-x86_64.serial.txt), [QMP](results/2026-10-16/launch-transport-x86_64.qmp.txt)
