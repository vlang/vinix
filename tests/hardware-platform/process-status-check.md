# Host child wait status width, 2026-10-26

`hwhost.Child.poll()` now passes an `i32` status slot to `waitpid` and explicitly
converts the completed status to its existing public `int` storage. The selected
compiler represents V `int` as eight bytes; C `waitpid` writes four. No child
stop, cancellation, outcome or polling policy changes are included.

Source baseline: `0269223bfa02e205d68a3a094e99554d3a648004`, isolated worktree
`/Users/alex/code/vinix/build/hwhost-waitpid-status-worktree`. Qualified source
SHA-256 values:

| File | SHA-256 |
| --- | --- |
| `hwhost/process.v` | `1cefdf1ce196bbe4f05813969107144dd2c123662c56815124da56c92dc5e5d5` |
| `process-status-check.v` | `27877f20b2bb99744dc8bd55d5206f3dff0e5ef2f198d0d2172346281537da65` |
| `process-status-run.v` | `c4fbc121a14781b18f4cb8c2d5d69ba965465e4456e0ff7cf05c695a8fd95453` |

The maintained fixture explicitly imports `hwhost` alongside
`fn C.waitpid(int, &i32, int) int`, matching
`tools/packages/audiopcm/native.c.v`. It uses explicit checks under normal and
`-prod` builds. Each mode passed six real self-child cases: exit 0, 37 and 255,
SIGTERM, SIGKILL, and a child externally reaped before `poll()`. Every case
checks a readiness barrier, pending `poll()` and raw WNOHANG, exact public
outcome, three cached polls, and actual `ECHILD`. The raw explicit-`&i32`
boundary additionally checks adjacent canaries and unchanged pending/error
status. Those canaries do not instrument `poll()`'s private local. Readiness is
published by writing and closing a pending file, then renaming it.

The runner stages an otherwise identical old module by reversing exactly the
two production lines. Both old builds refused with exactly one hard
`i64 *` to `int *` error at the actual `waitpid(c->pid, &status, WNOHANG)` call.
Both fixed builds completed with zero errors. Generated C confirms one exact
`hwhost__Child__poll` definition per build, with old `i64` and fixed `i32`
locals. Prototype text cannot satisfy that check.

Fixture compilation uses the retained ff75 compiler
`/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v`, SHA-256
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`,
and its qualified corrected library overlay. Its complete selected `v`,
`vlib`, `thirdparty`, `v.mod` and `snapshot.json` inventory equals the qualified
`overlay-before.json` (`65b8b8322a34407c4b16762803c618e2fe8f414cc0bc5ccb10144bf20292786f`);
provenance changes are pinned by `changes.json`
(`4941c055c018c321d7a4cc94c054b26ba6494bc6be7fa508d99a1bb10b7b2b21`).
Coherent `V`/`VEXE`/caller markers point at that overlay, and generated C names
only its `vlib`. Complete selected compiler, relevant source and executable
tool inventories match before and after. This does not inventory the entire
host SDK or dynamic library environment.

Homebrew Clang 23.1.0 was selected explicitly. Regression builds use
`-cstrict -Werror=incompatible-pointer-types -Werror=int-conversion`, with no
`-w`. The narrow `-Wno-error=incompatible-pointer-types-discards-qualifiers`
exception retains the existing builtin `rune_maps` qualifier warning. Both old
refusal logs retain that warning and 2,202 warnings total. V captures successful
C compiler diagnostics, so the fixed logs establish the command and zero-error
exit rather than visible warning output. No broad pointer-error demotion is
used. The host runner bootstrap uses the coherent original ff75 root at
`/Users/alex/code/vinix/build/package-https-runtime-work/toolchain`; its builtin
bridge supports the unchanged guard modules. Its ordinary V invocation
includes `-w` and makes no strict-compiler claim. Exact final bootstrap invocation,
source copies, C, log and executable are retained.

Final qualification `qualification-07` completed in 25.812 seconds. All six
supervised commands proved observed process groups, direct leader reaping,
group absence and final `ECHILD`. The inherited-group guard and its owned
`df` helper are unchanged. The runner uses private `VTMP`, `TMPDIR`, empty
`VMODULES` and `-nocache`; it records selected environment presence and clears
ambient `VFLAGS`, `CFLAGS`, `LDFLAGS`, `VTEST_ONLY_FN` and `V3CACHE` before child
compilation. Bootstrap 07 uses `env -i` and separate private temporary/module
directories.

Limits were 300 seconds per complete qualification, 2 GiB actual `df -k`
admission, 1 GiB floor and 64 MiB total new state including this worktree and
all retained failures. Command sampling reserves 2 MiB for final receipts.
Final `df` observed 4,237,652 KiB available; final charged allocation was
51,527,680 bytes. These are sampled filesystem observations, not a reservation
against unrelated host writers. Earlier retained attempts include the initial
unrelated qualifier refusal (03), unsupported `-skip-unused` refusal (04),
generated-function spelling check failure after runtime success (05), and the
passing predecessor before atomic-readiness correction (06). Only 07 qualifies
the final source. Exploratory bootstrap files retain their observed provenance;
only bootstrap 07's exact invocation is used for the final source binding.

Complete uncompressed audit bundle:
`/Users/alex/.cache/vinix-hwhost-status-20261026-01`. Preserve it intact; the
historical diagnostics and generated files are included, not substituted by
this report. `bundle.json` inventories every original file and directory except
itself, SHA-256
`1d80f53c7f317972c62b13980b4e4f7c5ff75ebc59b7d3e56e1aecbb7c9df1b2`.
No raw artifacts are committed.

Final runner SHA-256:
`604b273149a0a1fceae1a8a6db8b94e9b89e0554de02b92ea8d19b219248de34`.
`qualification-07/result.json`:
`3400a5688a56725a8e2896cafc2005a3c95830ffd497c5c0d39acac70cd995bb`.
`qualification-07/generated-c.json`:
`7a7d39f60504ca502ee1b45dc3d44d0d0b18235aa4d2b72b68816c7e882776ed`.
Sibling seal log `/Users/alex/.cache/vinix-hwhost-status-20261026-01.seal.log`:
`924a0ac47877eb458dc69247d03ba8882099d331967cb8322de941f1e7c65292`.

The maintained runner deliberately names this exact source, compiler and output
profile, and refuses a completed output. A fresh qualification needs a new owned
output and explicit source/compiler bindings. No shared V mutation, target
compile, image staging or VM execution was performed. This qualifies the host
ABI prerequisite, not the remaining native section 14 workflows.
