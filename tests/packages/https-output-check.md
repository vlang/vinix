# Captured HTTPS package output

HTTPS acquisition now opens one destination descriptor before starting transport.
The open uses `O_NOFOLLOW`, `O_NONBLOCK` and `O_CLOEXEC`, without truncation;
`fstat` requires a regular file with one link and a nonnegative size. NUL paths
and resume prefixes larger than the authenticated bound refuse before a request.
The production executable remains fixed at `/usr/bin/curl`; its destination
argument is stdout, and resume uses the captured numeric offset.

Curl's stdout goes to a close-on-exec pipe. The parent reads a fixed 64 KiB buffer
and checks the authenticated bound before every write to the captured file.
An oversized stream is stopped before exceeding that bound. Reads, writes, poll
and wait handle interruptions; partial writes complete without losing bytes.
The parent never writes response bytes to its own stdout. Curl diagnostics retain
stderr. The forked child only duplicates/closes descriptors and execs prebuilt
arguments; destination and package-lock descriptors do not survive exec.
Every failure kills/reaps an outstanding producer and closes pipe/file descriptors.

Fresh transfers defer truncation until the first body bytes or successful empty
EOF, preserving old prefixes on certificate/HTTP failures. A curl Range refusal
still triggers exactly one fresh attempt; a corrupt fresh fallback still stops
after verification. Interrupted bytes remain available to the next transaction.
Curl's own retries are explicitly disabled because delivered pipe bytes cannot
be rewound. Existing connection/total timeouts, certificate/hostname checks,
HTTPS-only redirects, disabled curlrc and signed size/hash verification remain.
Progress follows captured bytes, with completion gated by later activation.

Before returning successful transport, the service checks the captured size and
the named device/inode/type, flushes the captured descriptor and rechecks identity.
Changed destination names refuse without following their replacements. Failures
retain partial data written within the bound; they never unlink a replacement
pathname. Controlled package directories and locks remain required: these checks do not freeze
administrator changes to ancestors or arbitrary same-size in-place edits.

Previously curl opened the caller's pathname directly. A destination alias or
hard link could overwrite external data, a FIFO could block, and replacing the
name after a request began redirected the response. NUL paths silently selected
a shorter pathname. The [real TLS destination probe](https-destination-check.v)
records seven old behaviors and requires prompt refusal with external contents
preserved. All initially malformed destinations must refuse before any request;
the delayed substitution must refuse after its single request. Bounded children
and process-group cleanup retire the old implementation's blocked grandchild.

The [core runner](../../tools/packages/pkgcore/https_output_test.v) uses a private
in-process executable override and the [V producer](output-fixture.v), without
adding a CLI/environment override for production transport. It exercises full,
fresh, resumed, slow, empty, interrupted, over-bound and failed-exec output;
Range fallback; byte progress; replaced names; persistent size changes; and
descriptor inheritance. With a 32-descriptor limit, 64 cycles include success,
producer failure and exec failure, checking for unreaped children after refusal.
The same runner and producer are compiled and executed in both architecture
guests; `PACKAGE PIPE OUTPUT bounded-writes resume range-refusal closed-descriptors reaped-children PASS`
is required. Guest pipe checks use a deterministic producer; host TLS checks use
real curl/certificates. A guest TLS stack or public publisher is not implied.

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/output-core tools/packages/pkgcore/https_output_test.v
V=/path/to/v /tmp/output-core
```

The maintained distribution driver discovers the core runner. Its `--https-only`
mode runs the existing signed TLS/Range lifecycle and the new destination probe.
The probe's `--before` mode requires the previous production implementation.
Both-target guest receipts also pin the output runner and producer. These checks
do not measure whole-process heap retention, physical-media interruption or
broader catalog/API compatibility. Publisher enrollment, catalog migration and
graphical login remain separate roadmap gates.

## Recorded results, 2026-10-14

All 44 package core runners passed. HTTPS output, download recovery, mirror and
release also passed clang ASan/UBSan (leak detection disabled, undefined behavior
fatal). The signed CLI lifecycle, seven real TLS destination cases, maintained
TLS/Range suite, public atomic/hash/copy/metadata regressions and ELF profile
checks passed. The final host ledger records 115 successful compile/run results.

The previous binary reproduces four unsafe acceptances, a FIFO alarm and two
transport-level refusals after requests. The final binary refuses all seven
cases with external files preserved; the six initially malformed destinations
make no request, while delayed replacement is refused after one request.

Both fresh QEMU TCG Linux runtime guests passed all workflow markers and clean
poweroff: AArch64 reported 87.6 seconds, x86_64 reported 94.3 seconds (300-second deadline).
Each receipt pins thirteen inputs/logs, including the target output runner and
producer; separate QMP logs confirm guest shutdown. Services, runtime fixtures,
init and account/session programs were rebuilt with retained kernels/sandboxes.
The new pipe marker requires actual target-side bounded output, recovery,
close-on-exec and child/descriptor checks. Real TLS remains host-qualified.

Evidence: [before](results/2026-10-14/https-output-before.txt),
[after](results/2026-10-14/https-output-after.txt),
[host](results/2026-10-14/https-output-host.txt),
[results](results/2026-10-14/https-output-host.json),
[CLI](results/2026-10-14/https-output-cli.txt),
[TLS](results/2026-10-14/https-output-https.txt),
[sanitizers](results/2026-10-14/https-output-asan.txt),
[AArch64 receipt](results/2026-10-14/https-output-aarch64.json),
[serial](results/2026-10-14/https-output-aarch64.serial.txt),
[QMP](results/2026-10-14/https-output-aarch64.qmp.txt),
[x86_64 receipt](results/2026-10-14/https-output-x86_64.json),
[serial](results/2026-10-14/https-output-x86_64.serial.txt),
[QMP](results/2026-10-14/https-output-x86_64.qmp.txt) and
[compiler/source/artifact ledger](results/2026-10-14/https-output-toolchain.json).
