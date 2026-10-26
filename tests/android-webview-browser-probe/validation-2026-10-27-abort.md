# WebProcess exported-abort diagnostic validation

This change prepares a narrow diagnostic for the existing WebProcess SIGABRT
failure. It has not been staged or run in Vinix. Browser DOM/cookie/snapshot
success and Google Maps account login remain unverified by this change.

Source baseline: `a33c9bc336bca4498413932407d42a146831b97c` plus the exact
modified sources pinned in the prepared `build.json`. Only the WebProcess
helper receives the new explicit preload argument; UI wait-status reporting
and the production account process are unchanged.

## Correctness checks

The earlier ABI fixture found an exported wrapper recording its own DSO's PC.
The real exported `abort` body now captures its caller before any helper call.
Darwin aliases the source export to that same body without a forwarding frame;
Linux preparation supplies an explicit version script so the native `abort`
symbol remains public. The module uses `-no-builtin`, a fixed stack buffer,
one atomic report guard and one write. It restores incoming errno before native
forwarding. Missing symbols, reentry and unexpectedly returning backends remain
fatal. Hidden/direct/kernel abort paths are outside its coverage.

The macOS host checks passed:

- Seven core tests: one record across 64 forwards, exactly one native call per
  forward, errno preservation, failed stderr write, numeric module resolution,
  missing-symbol/reentry/return failure paths, and libc SIGABRT in a child.
- Native DSO ABI fixture: real public `abort`, original caller image and
  module-relative offset, one numeric record, child-only native SIGABRT.
- Session self-test: helper-role isolation, metadata protection, pins,
  tampering, missing files and symlink rejection. This ran as UID 501; its
  root-owned positive preload-path branch requires a root/guest run.
- Preparation and complete-tree inventory self-tests, followed by fresh
  preparation and inventory write/check.

The prepared aarch64 ELF has one defined global `abort` entry. Disassembly
captures x30 before the first helper branch. Its undefined symbols include
`dladdr`, `write`, `dlsym`, errno and `_exit`; no allocator, stdio or signal
handler imports appear. This is static target inspection, not a target run.
The ABI fixture retries interrupted reads/waits but rejects other errors.

## Resource measurements

`/usr/bin/time -l` recorded maximum resident set sizes in bytes:

| Operation | Maximum RSS |
| --- | ---: |
| Core tests | 92,733,440 |
| aarch64 diagnostic DSO compilation | 35,831,808 |
| Host session compilation | 568,688,640 |
| Host preparation-tool compilation | 1,156,005,888 |
| Inventory-tool compilation | 479,019,008 |
| Whole fresh preparation, including target builds | 4,380,196,864 |

Whole preparation took 50.96 seconds, reported zero swaps, and produced a
13,040 KiB bundle. It checked the existing archives and referenced base runtime
without copying or rebuilding the SDK, compiler or kernel. Its target builds
ran sequentially. The host tool was compiled with `-gc none`: existing
`tarstream.Reader.skip` allocates a 1 MiB buffer per skipped nonempty member,
and `prepare.hash` allocates 1 MiB per call, without explicit frees. These are
identified accumulation mechanisms, not measured attribution of the whole
peak. This change does not fix that separate host-tool allocation issue.

## Retained evidence and pins

All paths below are under `/Users/alex/.local/state/vinix/android/`.

- Prepared bundle: `browser-probe-build-2026-10-27-r17-abort/`; exact sources,
  linker metadata, compiler commands/results, runtime references and the
  complete copied fault fixture are retained.
- Its external inventory: `browser-probe-build-2026-10-27-r17-abort.inventory.json`.
- Host evidence: `browser-abort-review-2026-10-27-r2/`; test/build logs, measured
  preparation log, target ELF/disassembly and host export listing. Successful
  DSOs are `libbrowser-abort-fixed.dylib` and `libbrowser-abort-fixed.so`;
  earlier experiments are retained separately by filename in the same bundle.
- Host evidence inventory: `browser-abort-review-2026-10-27-r2.inventory.json`.

| Artifact | SHA-256 |
| --- | --- |
| Prepared `build.json` | `240b192570ccfe951031979db0cbc4523e5042fbebbfb6175880581949c1108d` |
| Prepared inventory | `83c22e2ab3d81a169ca47399f9895bb336bc7bd129f4772c47738b35cb0c99f9` |
| Prepared `bin/libbrowser-abort.so` | `379323b2f3bace679e273c7f4f4e9b2c0e2205b9664bfaee78d1489df2f8b6ab` |
| Prepared `bin/browser-session` | `f28c981ff7af62fb731531c6536bfe9546edd80cd17208327eb7aeff33597139` |
| Host evidence inventory | `0a79b9276cc19c959e42866544ebf4e7f411f84a0d2a12f23789ab3340ccdfd6` |
| Host fixed DSO | `9a8135bf7599ee95638ab2c77b57fc267fcb2224362c461c8c5d886ac7c91f69` |
| Host ABI fixture | `2c52100680cc7c3e87346c678d73f095aa072ab4fb7e5df189454806f539e87a` |

Preparation used `/Users/alex/code/v-tccbin-bootstrap-20261026/v` with SHA-256
`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`
and `/opt/homebrew/bin/aarch64-linux-musl-gcc` with SHA-256
`0b1146b08ba1c285931fbe5de0121e3d39dc4f2a827174ded0fe172ffe6254dd`.
Archive, base-runtime, probe, guest, waitid-module and fault-fixture pins match
the prior `browser-probe-build-2026-10-26-r16-waitid/build.json` (SHA-256
`5a11abcd134f2eb4f83d2adb131fad01e8bddf56be601e1d4809c65737e2c4fb`).
Compiler/SDK dependencies remain externally pinned references, not a newly
copied hermetic toolchain closure. No authentication data was used or logged.
