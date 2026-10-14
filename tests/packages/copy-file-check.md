# Captured local package copies and offline recovery

Local package copying now validates captured source and destination descriptors
before writing. Both opens use `O_NOFOLLOW`, `O_NONBLOCK` and `O_CLOEXEC`; `fstat`
requires ordinary regular files. The source's captured size must fit the caller's
authenticated bound. A resume offset must fit the source and equal the captured
destination length. Missing resume destinations refuse without creating a file.

The destination opens without `O_TRUNC`; only after type/identity/offset admission
may a fresh copy truncate it. Identical device/inode tuples refuse, including the
same pathname and hard-linked names. This avoids destroying the source while
trying to copy it. Copied bytes are limited to the captured source size, with one
sentinel read to detect growth. Shrinkage, final size mismatches and changed
destination path identity fail before the final progress report. Writes and
reads handle interruptions and short writes; successful output is flushed.

The later [output qualification](copy-output-check.md) also requires exactly one
destination hard link, checks identity/size/link count around callbacks and the
flush, and retries interrupted flushes. Source hard links remain supported. Its
separate baseline reproduces writes through an output linked to an unrelated
file; the original nine-case probe below retains its original baseline contract.

Offline `file://` acquisition shares this copier. It admits the source before
changing any retained partial and resumes an ordinary partial only when its
offset fits the captured source. An oversized partial restarts from zero after
source admission. An oversized/unavailable source preserves the existing partial;
incomplete valid prefixes can resume after trusted media is restored. Existing
cache rules still discard invalid complete or oversized partials before transport,
and a bad resumed hash still restarts once. HTTPS transport keeps its curl/TLS/Range
contract; its verified cache-to-generation copies use the same local copier.

Previously generic copies followed aliases, could block on FIFOs and truncated
the destination before checking identity or source length. Copying a file to
itself, including a hard link, returned success after emptying the source.
Oversized input truncated an existing destination before refusal, while offline
fetch deleted its partial outright. Resume offsets could append to a destination
of a different length. The maintained [bounded reproduction](copy-file-check.v)
records all nine behaviors against the previous implementation; its normal mode
requires refusal with every source, destination and external file preserved.
Two-second child alarms make blocking regressions fail promptly.

The [core assertions](../../tools/packages/pkgcore/copy_test.v) cover exact full,
empty and resumed contents, existing modes, private new files, invalid/overflowing
offsets, missing resumes, malformed paths and source-size limits. A progress
observer replaces captured source/destination names with FIFOs or aliases and
changes sizes during copying. Old source descriptors remain readable; replaced
destination names fail identity checks before writing through the captured
output, without following the replacement. Under
a 32-descriptor limit, 128 successful/refused cycles exercise descriptor cleanup.
These tests do not claim whole-process heap retention or atomic file-copy rollback.

The signed download-recovery runner checks that an oversized repository object
leaves the partial, active generation and rollback history intact. Restoring its
bytes resumes from the original prefix and activates verified content. The Linux
guest repeats this through the production CLI and requires
`PACKAGE OFFLINE COPY captured-files oversized-source retained-prefix restored-resume PASS`.
Its existing signed runtime, isolated launch, review, mirror/deployment, revoked
publisher, runtime update, rollback and bad-source recovery checks remain required.

Captured descriptors protect file identity and bound I/O. They do not snapshot
arbitrary same-size in-place writes or serialize an administrator changing parent
directories. Package locks, controlled directories, signatures and later payload
hash verification retain their roles. A failed copy can leave a bounded partial;
transactions and publisher/mirror staging decide when to retain or remove it.

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/copy-core tools/packages/pkgcore/copy_test.v
/tmp/copy-core
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/copy-check tests/packages/copy-file-check.v
/tmp/copy-check /tmp/new-copy-qualification
```

The maintained distribution driver discovers the core runner and runs the bounded
reproduction. `--before` requires the previous implementation. Sanitizers disable
leak detection and make undefined behavior fatal. The unchanged real TLS fixture
runs through `--direct-tests --https-only`. The Linux guest controller accepts
recorded target kernels and `VINIX_LINUX_SANDBOX`, rebuilding its probe, explicit
musl loader/runtime and current package/account/session/init programs without
invoking the legacy staging wrapper. See [Linux qualification](linux-runtime-check.md).

## Recorded results, 2026-10-14

All 15 focused core runners passed: copy, download recovery, progress, catalog,
composition, import, native/SQLite/FFmpeg profiles, release, mirror, deployment,
service, state and metadata. Copy, download recovery, mirror and release also
passed clang ASan/UBSan with leak detection disabled and undefined behavior fatal.
The full signed CLI lifecycle, metadata races, bounded copy reproduction and
updated distribution driver compilation passed. Real TLS/Range checks passed
through the maintained HTTPS-only driver.

The previous copier reproduces all nine unsafe cases: two FIFO alarms, source/
destination alias following, destructive same-path/hard-link copies, truncated
output on oversized input, inconsistent resume append and deleted offline partial.
The final copier refuses each case promptly while preserving fixture contents.
Successful full/empty/resumed copies and source-restored retry remain accepted.

Both fresh QEMU TCG Linux runtime guests passed every required marker and clean
poweroff: AArch64 reported 46.5 seconds, x86_64 reported 53.3 seconds, within the
300-second functional deadline. The service, init, account/session programs and
dynamic probe/library/static runner were rebuilt from the final sources with
retained kernels and production sandboxes. Each receipt pins eleven inputs/logs;
QMP shutdown logs are retained separately. Both guests require the new oversized-
source/preserved-prefix/restored-resume marker, along with the existing signed
Linux runtime maintenance and ordinary-account isolation workflows. No public
publisher enrollment, graphical login or broader catalog/API acceptance is claimed.

Evidence: [before](results/2026-10-14/copy-file-before.txt),
[after](results/2026-10-14/copy-file-after.txt),
[host checks](results/2026-10-14/copy-file-host.txt),
[individual results](results/2026-10-14/copy-file-host.json),
[signed CLI](results/2026-10-14/copy-file-cli.txt),
[TLS/Range](results/2026-10-14/copy-file-https.txt),
[sanitizers](results/2026-10-14/copy-file-asan.txt),
[AArch64 receipt](results/2026-10-14/copy-file-aarch64.json),
[serial](results/2026-10-14/copy-file-aarch64.serial.txt),
[QMP](results/2026-10-14/copy-file-aarch64.qmp.txt),
[x86_64 receipt](results/2026-10-14/copy-file-x86_64.json),
[serial](results/2026-10-14/copy-file-x86_64.serial.txt),
[QMP](results/2026-10-14/copy-file-x86_64.qmp.txt) and
[source/compiler/artifact ledger](results/2026-10-14/copy-file-toolchain.json).
