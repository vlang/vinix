# Download integrity recovery

Before this change, a damaged `objects/HASH.part` prefix was resumed and then
discarded after its complete hash failed, leaving the user to retry manually.
A complete invalid partial could also request a resume at end-of-file. The V
baseline harness builds `d87086b9d`'s transaction code against the new assertion
runner and retains its expected checksum-failure exit.

The service now distinguishes verified complete partials, invalid complete/
oversized partials, and incomplete prefixes. Verified complete data is promoted
without transport. Invalid complete/oversized data starts at byte zero. If a
completed resumed transfer fails its signed size/hash, the service discards it
and makes one fresh transfer from the same authenticated source and size bound.
A second integrity failure stops and discards the bad data. An initially fresh
transfer is never retried for integrity. Transport errors continue to retain
partial data for later commands; they do not trigger this automatic retry.
No generation publishes until cache and staged copies pass verification.

The pinned V compiler's `os.is_file` only excludes directories and accepts FIFOs.
Metadata, hashing, verification and offline acquisition now inspect ordinary
regular-file type before a potentially blocking read. Nonregular partial paths
refuse before transfer. Symbolic partials, including dangling links, are removed
without touching their targets. These checks assume the existing administrator-
controlled state/repository and package-lock boundaries; they do not serialize
an unrestricted administrator replacing a path concurrently.

[The V assertions](../../tools/packages/pkgcore/download_recovery_test.v) cover
corrupt-prefix recovery through a reviewed install, valid short prefixes,
verified complete cache with an absent source, invalid complete/oversized/empty
partials, bounded bad-source failure with retained activation and working
rollback, and directory/FIFO/symbolic partial handling. Direct FIFO metadata,
hash and offline-source reads refuse. Progress assertions distinguish resumed
bytes, a reset to zero, both completed transfers, and activation-only completion.

The real Linux guest prepares a damaged application prefix and an invalid
complete runtime partial in an offline signed deployment client. One reviewed
deployment recovers and verifies both payloads. A separate client installs and
removes the app, then retries against a tampered repository object. The CLI
rejects both resumed and fresh bytes, reports one restart, emits no activation/
completion, preserves its current generation, and successfully rolls back to
verified installed bytes. Both guests require the marker
`PACKAGE DOWNLOAD RECOVERY damaged-prefix complete-partial bounded-retry bad-source-refusal preserved-rollback PASS`.

Reproduce the host checks with the pinned compiler and staged headless UI module:

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -no-skip-unused \
  -o /tmp/distribution-check tests/packages/distribution-check.v
V=/path/to/v V_MACOS_V3_NO_FALLBACK=1 \
  VINIX_PACKAGE_TEST_UI2=/path/to/desktop-assets/modules \
  /tmp/distribution-check --direct-tests --cross
```

Run [the Linux guest controller](linux-runtime-check.v) with matching retained
AArch64/x86_64 kernels and native sandbox inputs, `VINIX_HWTEST_TCG=1`, and fresh
state directories. Service/init/account/session programs are freshly built.
The new assertion runner also runs ASan/UBSan with leak detection disabled and
undefined behavior fatal. Full logs, baseline, binaries and generated C are
retained under `build/package-download-recovery-work`.

The 2026-10-13 host driver passes all 31 assertion runners, SDK context heap,
CLI/PTY/Software fixtures and both target service builds. The new runner passes
ASan/UBSan. Both QEMU TCG workflows pass within the 180-second deadline:
AArch64 in 91.8 seconds and x86_64 in 122.7 seconds, with clean guest shutdown.

[Host results](results/2026-10-13/download-recovery-host.txt) and
[compiler/source/artifact ledger](results/2026-10-13/download-recovery-toolchain.json)
retain markers and witnesses. Guest receipts, serial and QMP:

- [AArch64 receipt](results/2026-10-13/download-recovery-aarch64.json),
  [serial](results/2026-10-13/download-recovery-aarch64.serial.txt) and
  [QMP](results/2026-10-13/download-recovery-aarch64.qmp.txt).
- [x86_64 receipt](results/2026-10-13/download-recovery-x86_64.json),
  [serial](results/2026-10-13/download-recovery-x86_64.serial.txt) and
  [QMP](results/2026-10-13/download-recovery-x86_64.qmp.txt).

The ledger verifies eleven artifact hashes per guest. Existing compiler notices
and generated-C warnings remain in local logs. Sanitizer results concern the
exercised safety checks; leak detection is disabled.

This qualification exercises signed local/offline sources. It does not add an
HTTPS server/Range-negotiation fixture, physical-media/power-cut test, public
publisher enrollment, graphical broker or broader foreign-runtime coverage.
Roadmap 14 remains open.
