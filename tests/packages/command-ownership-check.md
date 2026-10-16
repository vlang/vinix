# Command request ownership

`command_launch` now retires prefix scratch after success and every refusal.
Its temporary document vector is capped at 256 entries, borrows source strings
through explicit pointer pushes, and never clones a rejected argument tail.
After the complete borrowed request passes validation, the returned
`CommandLaunch` owns independent document/argument vectors and strings.
`CommandLaunch.close()` retires them, resets `data_cwd`, and permits repeated
close. The CLI closes parsed requests when either launch mode returns.
Manually assembled command inputs and the run/plan APIs can still borrow fields;
their caller must not free borrowed values through this ownership helper.

The frozen compiler already cloned legacy document strings on normal append.
Generated C made that implicit ownership explicit. The defects were retained
array growth buffers, rejection storage and the lack of a public retirement
method, rather than changed literal argument semantics. The new temporary vector
uses raw array retirement, and accepted fields are cloned exactly once.

Ordinary-user transport validation also uses a bounded borrowed prefix vector.
It retains its existing 772-value envelope, duplicate-option diagnostics and
late 257th-document refusal. Its old normal appends cloned document strings that
raw array retirement did not free. Five validations with 0/1/64/256 documents
retained 0/100/14,615/57,165 bytes; the matched final probes retain zero.

Matched warmed five-cycle baseline probes explicitly retired both returned
vectors and their strings. Empty and one-document successes retained zero bytes;
64-document successes retained 8,215 bytes and 256-document successes 31,565.
Duplicate-data-cwd, missing-separator, unknown-prefix, missing-path, invalid-path,
NUL, oversized-string and aggregate-overflow refusals retained 410, 22,450,
22,450, 22,450, 38,010, 22,725, 22,725 and 24,525 bytes respectively. The same
probes against the final implementation retain zero bytes in all twelve cases.

The owned fixture retires its source vector before reading two independent
results, closes one sibling and validates the other, then closes each twice.
Tracked native loops repeat success with 0/1/64/256 documents and twelve refusal
paths 1000 times with zero retained bytes. Functional boundaries admit 256
arguments and documents together, 4096-byte fields and 65,535/65,536 aggregate
bytes; 65,537 bytes and excess counts refuse. Documents and arguments contribute
their terminators to the same byte limit. Count refusal still precedes invalid
path validation. Unicode, empty values, newline arguments, option-looking values,
`--`, shell-looking text and `@APP@` remain literal.

Existing parser, sandbox-plan, session and SDK-context fixtures run alongside
the new assertions. CLI checks cover both run modes and exact diagnostics before
account/session setup. This work qualifies request parsing/retirement and
unchanged launch plans, not the lifetime of every service/process allocation or
new foreign runtime compatibility. No kernel changes are involved.

Transport checks repeat both command modes with 0/1/64/256 documents and nine
refusal paths 1000 times. The CLI fixture runs both on the ordinary host and as
root inside each native guest, preserving the earlier isolation/TTY gates and
the core parser's diagnostics. No fixture executes an application or requests an
account session for malformed input.

Roadmap 14 remains open for production publisher enrollment, catalog migration,
graphical login/display integration and broader foreign-runtime acceptance.

## Recorded results, 2026-10-16

All **34 focused compile/run checks** passed: ten core pairs, a tracked ownership
pair, an ASan/UBSan pair, the matched final-probe pair, six CLI/driver checks and
two guest-tool builds. Tracked cases repeat 1000 times; sanitizer and untracked
functional loops repeat 64 times. The aggregate-size and source-retirement
boundary cases run separately from the tracked loops.

Fresh QEMU TCG guests passed with clean shutdown and nine verified artifact
hashes each: AArch64 **10.4 seconds**, x86_64 **9.1 seconds**. Deadlines qualify
functionality, not performance. Final guest images contain the current CLI,
the CLI refusal worker and four parser/plan/session/context workers.

- [matched before/after probes](results/2026-10-16/command-ownership-baseline.txt)
- [host results](results/2026-10-16/command-ownership-host.json)
- [host summary](results/2026-10-16/command-ownership-host.txt)
- [core assertions](results/2026-10-16/command-ownership-core.txt)
- [tracked allocations](results/2026-10-16/command-ownership-memory.txt)
- [sanitizers](results/2026-10-16/command-ownership-asan.txt)
- [CLI diagnostics and signed lifecycle](results/2026-10-16/command-ownership-cli.txt)
- [source/toolchain/artifact pins](results/2026-10-16/command-ownership-toolchain.json)
- [AArch64 receipt](results/2026-10-16/command-ownership-aarch64.json), [report](results/2026-10-16/command-ownership-aarch64.txt), [serial](results/2026-10-16/command-ownership-aarch64.serial.txt), [QMP](results/2026-10-16/command-ownership-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/command-ownership-x86_64.json), [report](results/2026-10-16/command-ownership-x86_64.txt), [serial](results/2026-10-16/command-ownership-x86_64.serial.txt), [QMP](results/2026-10-16/command-ownership-x86_64.qmp.txt)
