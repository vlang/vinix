# Standalone sandbox generator qualification

Audio preparation now builds the existing compatibility generator directly
with V and explicit checkout module parents. A private empty `VMODULES` no
longer hides `fixturehost`, `hosttest`, `guesthost`, `policyhost` or `nativepolicy`.
The shared argument factory supplies `-prod -nocache -keepc -backend c`, uses the
already captured host compiler, and overrides target `CFLAGS`, `CPPFLAGS` and
`LDFLAGS` with empty values for that host child. The controller retains the
generator binary, generated C, arguments, environment and build log.

The same real build exposed a separate C boundary in `guesthost.quit_monitor`.
Its sole `connect` call now declares the generic socket address pointer and
explicitly casts the existing Unix socket address, preserving its storage and
length. The compiler's real libc prototype is satisfied without suppressing
pointer diagnostics.

The [first native preparation](audio-portal-plan-check.md) is still a failed
attempt. Its cross-probe linked, then the old shell generator stopped on module
lookup. The runner returned actual exit 1, naturally reaped its child, observed
an empty group and ECHILD, and retained equal complete original input maps:
`f8042cffc824c38a0ae92c99167e965d8ee070844a4a157222956062378c11be`.
No completed preparation receipt or guest run was produced. The complete failed
state remains retained outside Git; a new original-checker seal attempt timed
out after 300 seconds before creating a manifest and is preserved as a refusal.
No failed-bundle seal is claimed.

The focused checker uses that attempt's captured headers, startup objects and
libraries read-only. Generator source is a fresh small committed sparse worktree
at `2da44097162cbff9ae5718b51a88beabe09992bd`, derived from the independent
preparation source `56941c3e3d059911b736f4ac21d169f122013b5d`. Every materialized
entry matches the reviewed old source except the four explicitly named,
maintained-source-matching changes. The selected module closure, detached
revision, independent file inodes and complete source metadata are checked.
Frozen W/N and the historical captured inputs are not edited.

Pinned V `ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`
and LLVM 23 clang build the checker and changed controller with
`-prod -nocache -keepc -backend c -Werror=incompatible-pointer-types`.
Independent source review passed. The changed controller's host build passed.
All five original complete postchecks passed for W, N, the compiler, selected
kernel and original full kernel bundle; all 14 authority anchors stayed equal.
The real focused run returned actual exit 0 and its exact PASS marker:

| Focused command | Result |
| --- | --- |
| Build the real compatibility generator with private modules | PASS |
| Generate the sandbox C core and existing ABI assertions | PASS |
| Static AArch64 link with `-Wall -Wextra -Werror` and strict pointer diagnostics | PASS |
| ELF64 little-endian AArch64 ET_EXEC admission | PASS |
| Three child reaps, empty groups and ECHILD checks | PASS |
| Selected input and complete fresh-source before/after identity | PASS |

The selected input maps have SHA-256
`2363fb82e03bda47eb9d82b5d89d3d4be15ed803643af9c16c0a8a1f4e032279`;
the fresh generator source maps have SHA-256
`7e09fc86e2df0e1987ae149cac7a123db2bd42a6a15e34d54ee7a197b5f9c1c6`.
These prove unchanged selected captures during this diagnostic, rather than an
independent reconstruction of the failed attempt's original complete capture.
`artifacts.json` is a snapshot before final receipt writing, not a whole-bundle
seal. Existing format-1 preparation and historical evidence checkers are unchanged.

Evidence is retained at
`/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/a4-independent-fixtures-aarch64-prepare-20261104-01`.
The admitted generator source is `sandbox-generator-source-03`; the passing
run is `sandbox-generator-fix-03`. Its `qualification.json` SHA-256 is
`6197e30caeca60a341afd45c0cbcc5ee4b0dfd769866f39a87e2af6d894eeec2`.
Generated sandbox C SHA-256 is
`fae06fbedceacc4ff1ae81ea9567a8e444a4f5f3d71d738d7d1977ac87e9b45d`;
the linked ELF is
`dd5e5430f84704594f5bc12a7c0d60007f1e43f680669ce5c577456c06842890`.
The earlier missing bootstrap module-parent, old socket boundary and extra
unreviewed README refusals remain preserved, with their as-run source snapshots.

This phase reserves 96 MiB across all retries: 16 MiB bootstrap, 64 MiB runtime
and 16 MiB final records. The passing run used about 13.3 MiB apparent output.
Its final conservative apparent namespace observation was 2,025,447,424 bytes
under the unchanged 2 GiB cap. Allocation/free-space sampling and independent
apparent endpoint checks retain their stated scope; no continuous dual-cap,
RSS, exclusive-growth or unconditional descendant-cleanup claim is made.

Final six-root observations were 1,752,152 KiB allocated and 1,901,015 KiB
apparent, with 50,326,524 KiB actual free. All diagnostic retries and source
worktrees added 48,212 KiB allocated / 46,804 KiB apparent within the 96 MiB
envelope. `setup/sandbox-generator-final-01.json` SHA-256 is
`a401397d8c0a9cc48f8dd2eef2017b239be7550da128579de82edba6b60e1e65`;
the literal command/status record `setup/sandbox-generator-execution-results-01.json`
is `7918bec1df2be7dce20e2ee558c235dcb897e9d02f47d9f575cc6984eae0430f`.

The full eight-program preparation, renewed complete host qualification and
native audio scenarios remain open. Format 1 cannot point fresh target outputs
at this failed state's existing captures: artifacts must remain under one state
root, trace paths derive from it, and resume requires a completed preparation
receipt. Any continuation needs a separate versioned contract and resource
projection; this change makes no native audio acceptance claim.
