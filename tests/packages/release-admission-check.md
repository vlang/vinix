# Complete publisher release admission

The publisher now checks the complete staged release before flushing and
reserving its sequence, then checks again after reservation immediately before
exclusive publication. The signed index and signature must retain their exact
captured bytes. The only permitted root entries are `index.json`, `index.sig`
and `objects`; the object directory must contain exactly the selected hashes,
with their authenticated lengths and contents. Files must be ordinary, have one
link and mode 0644. The private root stays 0700 until reservation, and final
directories require 0755.

Releases and offline mirrors share bounded directory admission, metadata reads
and payload checks. Directory enumeration stops at the first unexpected name
without traversing extra directories or following aliases. Each opened directory
is closed on success and refusal, and its named identity is checked. Temporary
paths, metadata, maps and copied iteration keys are released by the new checks.

Before this change, the final reservation checkpoint could change the staged
index and the publisher would publish it. The baseline assertion records
`refused=false unpublished=false` before its expected failure.

The publisher assertions cover changed metadata and payloads, missing files,
aliases, hard links, FIFOs, extra entries and changed modes at both checkpoints.
Early refusal preserves the prior publisher history. A refusal after reservation
keeps the intended signed sequence/digest, so changed metadata cannot reuse the
sequence. Exact retries remain available. Refused releases remove their own
unpublished stage and preserve the source workspace, seed, prior release and
outside files and directories. No new consumer trust or license acceptance is
implied.

The target controller runs the publisher and existing mirror assertions on both
architectures, including the 128 valid and 128 refused scans under a 32-descriptor
limit. Receipts bind the kernel, init, both assertion programs and serial output.
This is publication and recovery qualification, not a guarantee against arbitrary
concurrent administrator changes, physical-media power loss or whole-service heap
retention. Controlled ancestors and stable administrative inputs remain required.
The complete scans add object reads; large-media throughput is not qualified.
The broader roadmap release gates remain open.

## Recorded results, 2026-10-15

The baseline published changed staged index bytes after reservation. Final
checks refused the same change and 34 mutations of files, modes, links and
namespaces at the staged and reserved checkpoints. Refused exports cleaned
their stages and preserved the workspace, seed, prior release and outside data.
Early refusals retained the previous history bytes. Late refusals kept the
intended sequence/digest; exact retry succeeded and changed-sequence reuse
refused without changing history. The existing interruption, closure,
reproducibility and both consumer-architecture cases also passed.

All 25 final host compile/run checks passed: eight core runners, publisher and
mirror under clang ASan/UBSan, and signed real CLI lifecycle/maintenance.
Leak detection was disabled and undefined behavior was fatal. Generated C was
reviewed for stack stat records, borrowed directory-entry views and owned
scratch cleanup. This qualifies exercised safety and descriptor lifetimes;
whole-service heap retention and large-media throughput remain unqualified.

Fresh QEMU TCG runs passed on AArch64 (55.0 seconds) and x86_64 (156.1 seconds),
with all publisher and shared mirror markers and guest-initiated shutdown within
the controller's 600-second budget. Five-artifact receipts bind each committed
kernel, init, both assertion programs and serial output. Compiler, source,
generated C and logs are pinned. The broader publisher/catalog rollout,
graphical, device and runtime release gates remain open.

Evidence:

- [before regression](results/2026-10-15/release-admission-baseline.txt)
- [host results](results/2026-10-15/release-admission-host.json)
- [host summary](results/2026-10-15/release-admission-host.txt)
- [publisher and mirror assertions](results/2026-10-15/release-admission-core.txt)
- [sanitizers](results/2026-10-15/release-admission-asan.txt)
- [signed CLI](results/2026-10-15/release-admission-cli.txt)
- [source/artifact ledger](results/2026-10-15/release-admission-toolchain.json)
- [aarch64 receipt](results/2026-10-15/release-admission-aarch64.json)
- [aarch64 report](results/2026-10-15/release-admission-aarch64.txt)
- [aarch64 serial](results/2026-10-15/release-admission-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-15/release-admission-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-15/release-admission-x86_64.json)
- [x86_64 report](results/2026-10-15/release-admission-x86_64.txt)
- [x86_64 serial](results/2026-10-15/release-admission-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-15/release-admission-x86_64.qmp.txt)
