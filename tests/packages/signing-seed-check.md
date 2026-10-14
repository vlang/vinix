# Publisher signing seed capture

Both publishing commands admit a seed through one descriptor opened with
`O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK`. `fstat` requires an ordinary
file owned by the invoking publisher, no group/other permission bits, exactly
one link, and a length from 64 through 128 bytes. Admission precedes allocation
or reading. At most the admitted length plus one sentinel byte is read; EINTR
retries do not change that bound. Size, ownership, permissions, link count and
the named device/inode/type must still agree before decoding.

The content must be exactly 64 hexadecimal digits after surrounding ASCII
whitespace is removed. Uppercase hex, LF and CRLF remain supported. Errors
describe the violated contract without including secret contents. Restoring a
private ordinary seed permits retry; refusals do not chmod or unlink inputs.
Raw/decoded buffers and the derived private-key buffer have explicit retirement.
This does not qualify erasure of every temporary inside the pinned signing
library, whole-process heap retention or arbitrary same-size in-place editing.
Controlled publisher directories and stable inputs remain required.

Previously the legacy `publish` accepted publicly readable or hard-linked seeds.
Both commands accepted a valid seed padded to the generic 8 MiB metadata bound;
`publish-release` also accepted hard links. Release permission checks, signing
and the accidental-secret digest came from separate pathname observations.

Release publication now uses the same captured seed for signing and for its
raw-file exclusion digest. Replacing the pathname after capture cannot change
which seed bytes the exclusion check protects. The check catches an exact copy
of the raw seed file; credentials in other representations remain the publisher's
responsibility. Publisher history and release output remain absent on refusal.

The [core runner](../../tools/packages/pkgcore/signing_seed_test.v) covers:

- Uppercase/lowercase hex, common line endings and the exact 128-byte boundary.
- Empty, short, malformed, NUL-containing and oversized inputs.
- Growth, truncation, public permissions, alias/FIFO/directory substitution and
  ordinary-file replacement at captured-size and post-read checkpoints.
- NUL path refusal through release publication.
- An original seed accidentally packed as a payload, with its pathname replaced
  after capture: the original secret is still excluded, no history/output is
  published, and restoring inputs permits retry with the original public key.
- 128 success/refusal cycles under a 32-descriptor limit.

The [CLI probe](signing-seed-check.v) runs both publishing commands with unsafe
permissions, hard links, padded inputs, aliases and FIFOs. Root guest runs also
check different-owner files. It requires bounded completion, unchanged outside
contents, absent new publication/history and matching index/signature bytes
after a valid-seed retry. Its `--before` mode reproduces the previous acceptances.
The maintained [distribution driver](distribution-check.v) invokes the probe.
Both [Linux runtime guests](linux-runtime-check.md) execute the same probe with
the rebuilt target service and require `PACKAGE SIGNING SEED`.

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/seed-core tools/packages/pkgcore/signing_seed_test.v
/tmp/seed-core
v -nocache -gc none -manualfree -o /tmp/seed-check tests/packages/signing-seed-check.v
/tmp/seed-check /path/to/vinix-package /tmp/new-seed-work
```

Publisher enrollment, advertised-catalog migration and graphical/runtime
qualification remain separate roadmap gates.

## Recorded results, 2026-10-14

All 45 package core runners passed. Signing-seed, release, catalog and composition
runners passed clang ASan/UBSan (leak detection disabled, undefined behavior fatal).
The signed CLI lifecycle and maintained real TLS/Range suite passed. The host
ledger records 107 successful compile/run results.

The retained previous CLI reproduces five unsafe acceptances. The final CLI
refuses all ten host cases before new index/release/history publication, preserves
outside inputs and successfully retries with matching index/signature bytes.

Both fresh QEMU TCG Linux guests passed all workflow markers and clean shutdown:
AArch64 reported 192.2 seconds; x86_64 reported 241.1 seconds (300-second deadline). Each receipt
pins fourteen artifacts/logs, including the target signing-seed probe. Root
guest cases also refuse different-owner seeds. Services, fixtures, account/session
programs and init were rebuilt with retained kernels and sandboxes. QMP records
confirm guest-initiated shutdown. These runs do not enroll a release publisher
or qualify graphical applications, physical write-cache loss or broader runtimes.

Evidence: [before](results/2026-10-14/signing-seed-before.txt),
[after](results/2026-10-14/signing-seed-after.txt),
[host](results/2026-10-14/signing-seed-host.txt),
[results](results/2026-10-14/signing-seed-host.json),
[CLI](results/2026-10-14/signing-seed-cli.txt),
[TLS](results/2026-10-14/signing-seed-https.txt),
[sanitizers](results/2026-10-14/signing-seed-asan.txt),
[AArch64 receipt](results/2026-10-14/signing-seed-aarch64.json),
[serial](results/2026-10-14/signing-seed-aarch64.serial.txt),
[QMP](results/2026-10-14/signing-seed-aarch64.qmp.txt),
[x86_64 receipt](results/2026-10-14/signing-seed-x86_64.json),
[serial](results/2026-10-14/signing-seed-x86_64.serial.txt),
[QMP](results/2026-10-14/signing-seed-x86_64.qmp.txt) and
[compiler/source/artifact ledger](results/2026-10-14/signing-seed-toolchain.json).
