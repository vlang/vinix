# GMS caller-identity check — 2026-10-29

The retained GMS `aqxf.i(Context)` throws the exact message
`Only 0p apps are allowed to call this API.` when `bpbx.T(Context)` is false.
The targeted audit establishes that `bpbx.T` obtains `Binder.getCallingUid()`
and passes that UID to `dgyj.a(Context, int)`. It does not establish the nested
trust predicate or validate Google authentication.

The V helper `gms-0p-auth-check.v` was added on source base
`ee5946e194875d5c80d8079c5806cd393860cfa2`. Its source SHA-256 is
`cc6aae420dc3242dae2e1868af353a2265549eefd2a3a577a9063b16b9d17e36`.
It verifies the existing pinned APK, baseline inventory identity, every root
DEX and consumed Java/JAR identities, locates the class through DEX metadata,
and disassembles only `Lbpbx;`. The owner is root `classes.dex`; `T` starts at
line 1471 of the retained selected smali. Consumed inputs are rehashed afterward.
This read-set check does not replace full historical-bundle verification.

Artifacts remain outside Git at
`/Users/alex/.local/state/vinix/android/gms-0p-auth-check-2026-10-29-r1`.
`audit/sha256.json` has SHA-256
`1cde99f3b63f7a1f8b9543bff39c9150d57cdf9190e8bb1caa3fbab71b508539`.
It pins the selected smali, command, inputs, source copy and executable copy.
The original targeted cache was not modified.

Compilation and the actual audit passed under unchanged 600-MiB aggregate RSS,
300-second, 512-MiB observed shared-volume growth and 1-GiB reserve limits.
Compile/run elapsed times were 2.910/44.659 seconds, sampled peak RSS
333,660,160/159,547,392 bytes, observed shared-volume growth
66,183,168/385,122,304 bytes, with exit/child status zero and complete cleanup.
The logs report zero swaps. Guard receipts are sibling `-compile.guard.json`
and `-run.guard.json`, SHA-256 respectively
`480d83a2bc22dd501ae71a7755966d9c8ba0595d8d2f80591796e27e43f5b302`
and `e5a48654a427e935de26031f3acbca2bf800e5c79fbdd2849404c3e35eff4c74`.
Compiler, guard, executable and source hashes are also retained in
`tool-inputs.sha256`. No guest or credential operation was performed by this audit.
