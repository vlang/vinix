# Captured publication of recovered package objects

A complete verified `objects/HASH.part` skips transport. Previously this also
bypassed the copier's single-link output admission, then used pathname-based
`chmod`, flush and rename. A hard link to an unrelated file could therefore
change that file's permissions during a successful recovery.

Existing partials now require an ordinary file with exactly one hard link before
resume/reset or promotion. The final promotion captures the object directory and
partial, admits the signed size, hashes through the captured descriptor and
checks named identity/link count before applying permissions or publishing.
Permission changes and file/directory flushes use those descriptors. Publication
uses `renameat`, replacing a leaf destination symlink instead of writing inside
its target. `EINTR` retries both flushes; other failures refuse, with an explicit
**cached payload saved** diagnostic if publication already happened.

The [public service probe](cache-promotion-check.v) signs an app, installs/removes
it, and attempts reviewed recovery using hard-linked prefix, complete, invalid
complete and oversized partials. A verification observer also substitutes a
hard link after initial admission. Each refusal must preserve unrelated bytes
and mode, active state, catalog/history and rollback generations. Retiring the
partial alias permits an ordinary complete-partial retry without an upstream
object and with working rollback. `--before` is for the retained prior service
and reproduces its 0640-to-0444 change on an unrelated complete hard-linked file.

The [core assertions](../../tools/packages/pkgcore/cache_promotion_test.v) replace,
link, substitute symlink/FIFO, change contents and swap the parent after descriptor
capture. They also exercise a destination directory symlink, hash/length refusal,
file and directory `EINTR`, pre-publication `EIO`, post-publication diagnostics,
and 128 success/refusal/error cycles under a 32-descriptor limit.

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/cache-promotion tests/packages/cache-promotion-check.v
/tmp/cache-promotion /tmp/new-cache-promotion-work
```

The [target controller](cache-promotion-runtime-check.v) runs the core and public
probe on both architectures. Controlled parent directories and package writer
serialization remain required. These checks do not freeze arbitrary same-size
writes by another process with the same authority. A private partial's mode can
already be read-only when a later flush fails; successful retry still rechecks
its bytes. Cache publication alone does not activate a generation. Wider storage
crash, graphical-session, public-publisher and application-catalog release gates
remain open.

## Recorded results, 2026-10-14

The retained previous transaction implementation (`64f73d399`) reproduced
successful recovery changing an unrelated hard-linked file from mode 0640 to
0444. The final public probe refused all five early/late alias cases, preserved
unrelated bytes/mode and active state/history, then completed ordinary offline
retry and rollback without the upstream payload. The core assertions passed
path/parent/link/type/content substitutions, atomic destination-link replacement,
file/directory flush retries and failure diagnostics, and 128 cycles under a
32-descriptor limit.

Ten host assertion runners passed: cache promotion, download recovery, copy
output, copying, hashing, durability, mirror export, distribution, service and
review. The complete signed CLI lifecycle passed, and the maintained distribution
driver compiled. Core and public-probe clang ASan/UBSan runs passed with leak
detection disabled and undefined behavior fatal. The ledger records 30
successful host compile/run results; no whole-service leak measurement is claimed.

Fresh QEMU TCG runs passed on AArch64 (18.6 seconds) and x86_64 (22.0
seconds). Each ran the core assertions and public signed-service probe, then
shut down within the 300-second allowance. Both use retained committed kernels;
no concurrent kernel edits were rebuilt. Five-artifact receipts pin kernel, init,
both programs and serial log. Generated C/build logs are pinned in the ledger.
These runs qualify package recovery/publication rather than graphical sessions
or foreign application APIs.

Evidence:

- [previous-implementation control](results/2026-10-14/cache-promotion-baseline.txt)
- [host results](results/2026-10-14/cache-promotion-host.json)
- [host checks](results/2026-10-14/cache-promotion-host.txt)
- [core assertions](results/2026-10-14/cache-promotion-core.txt)
- [public recovery probe](results/2026-10-14/cache-promotion-probe.txt)
- [sanitizers](results/2026-10-14/cache-promotion-asan.txt)
- [signed CLI lifecycle](results/2026-10-14/cache-promotion-cli.txt)
- [source/artifact ledger](results/2026-10-14/cache-promotion-toolchain.json)
- [aarch64 receipt](results/2026-10-14/cache-promotion-aarch64.json)
- [aarch64 report](results/2026-10-14/cache-promotion-aarch64.txt)
- [aarch64 serial](results/2026-10-14/cache-promotion-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-14/cache-promotion-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/cache-promotion-x86_64.json)
- [x86_64 report](results/2026-10-14/cache-promotion-x86_64.txt)
- [x86_64 serial](results/2026-10-14/cache-promotion-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/cache-promotion-x86_64.qmp.txt)
