# Host supervisor wait status width

The inherited-group supervisor now gives `waitpid` a four-byte `i32` status
slot in `nativeguard.poll`, `nativeguard.cleanup` and
`recoveryguard.terminate_group`. The retained compiler represents inferred V
`int` locals as eight-byte `i64`; passing their addresses to C's `int *` is
incompatible. Public exit codes and cleanup receipts remain V `int` values.

Source baseline: `72056488a98e34b4ef5735d9520f41204da189c0` plus these two
production files and the maintained fixture/runner in this change. Qualified
source copies and complete selected-input maps are retained with the evidence.

## Qualification

`nativeguard-width-run.v` is a production, source-bound host profile. It builds
`nativeguard-width-check.v` in normal and production modes with explicit private
`VTMP`, empty `VMODULES`, `-nocache`, the qualified wait-width compiler overlay
and coherent no-fallback compiler markers. Normal and production controls
reconstruct the three original wide status declarations while retaining the
harmless explicit conversions used by public receipts. They are width controls,
not byte-identical historical sources.

Both wide-slot controls exit 1 with exactly three incompatible `i64 *` status
errors under strict Clang. Both fixed builds and both real fixture executions
exit 0. Pointer and integer-conversion errors are mandatory; the separate
retained `rune_maps` const-discard warning is allowed with
`-Wno-error=incompatible-pointer-types-discards-qualifiers`.

The fixture uses explicit checks that survive `-prod`:

- Raw four-byte status storage has an immediately adjacent canary and checks
  normal exit, signal exit, running-child `WNOHANG` and post-reap `ECHILD`.
- Actual `nativeguard` launch/poll/cleanup checks normal and killed children,
  empty groups, final `ECHILD` and stable repeated cleanup receipts.
- Actual `os.Process` and `recoveryguard` check running/normal/killed children,
  repeated waits, group removal and final `ECHILD`.

Generated C independently identifies the definitions of all three production
functions: each fixed output has three `i32` status declarations and no `i64`
status declarations; each control has the inverse. All four fixture C outputs
identify only the qualified overlay's adjacent `vlib` root.

All six guarded build/run commands observed their process group, reaped their
leader, removed the group and returned final wait `-1` / `ECHILD`. Complete
selected compiler, source and executable-tool inventories match before/after.
The maintained runner returned actual status 0 in 9.665 seconds. Its final
sample charged 10,555,392 bytes against a 64 MiB namespace budget, including the
source worktree and bootstrap state. Admission requires actual `df` availability
of 2 GiB; sampling requires a 1 GiB floor, a 2 MiB receipt reserve and a five-minute
deadline. Sampling is not a filesystem quota; inherited groups do not track
daemonized descendants. The separately retained external bootstrap returned
actual status 0 and is not covered by the runner's before/after maps.

## Retained evidence

Raw evidence, generated C, executables, selected-input maps and source copies:
`/Users/alex/.cache/vinix-nativeguard-width-20261026-01`.

Complete independently checkable inventory:
`/Users/alex/.cache/vinix-nativeguard-width-20261026-01-seal/inventory.json`,
SHA-256 `34a2d62a6542edb2799ef92a91f4b575b1b96700d910eaf3fcd8e7c8f7296bb3`.

Maintained runner SHA-256:
`d9b6086dd5d50dbab4864dab130d449f118e28944babfc99fd4fb9c5b301afd1`.
Fixture SHA-256:
`e5f345c35051c4a241e0183123e41a377fc30f1022a05b0defad78a171b6fb7b`.
The selected compiler has SHA-256
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`;
its complete qualified overlay map has SHA-256
`65b8b8322a34407c4b16762803c618e2fe8f414cc0bc5ccb10144bf20292786f`.

This qualifies host supervision and status storage. No target program or QEMU
guest was executed by this profile.
