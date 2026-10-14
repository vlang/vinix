# Complete package generation admission

Install, upgrade, removal, repair and managed deployment share complete generation
checks before recursive directory flushing, before exclusive publication and
after the final activation callback. The expected namespace comes from the
validated state: declared package files, generated application launchers,
`state.json` and an empty read-only `lease`. State bytes must match the exact
captured serialization; payload lengths/hashes and launcher bytes must match
their declarations. Ordinary entries, service ownership, single-link files and
canonical file/final directory modes are required. The private root is 0700
before flushing; final directories are 0755.

Directory enumeration stops at unexpected names without traversing extra
directories or aliases. A breadth-first queue keeps only one directory stream
open, including at deeply nested paths. Opened/named directory identities are
compared. New checker maps, paths, metadata and streams are retired on success
and refusal. This does not claim zero heap retention for complete transactions.

Failures remove unpublished stages and preserve the active generation. Exclusive
publication cannot replace a raced destination. After publication, failure
retains the new generation for inspection, prints its path and leaves `current`
unchanged. Retrying uses a fresh generation identity and verified cache/source
data. Rollback checks its complete target before and after activation progress;
its captured state text remains compatible with previously accepted whitespace.
No completion event is emitted for refused activation or rollback.

The baseline reproduces activation of a changed staged `state.json`. New tests
exercise 90 mutations across preparation, staging, publication and activation:
state, payload, launcher and lease contents, missing entries, aliases, FIFOs,
hard links, modes and unexpected namespaces. They check preserved current state,
catalog/history, outside data and offline retry. Additional assertions cover a
raced empty publication destination, four late rollback mutations, whitespace
compatibility and 128 valid plus 128 refused scans of a 64-level tree under a
32-descriptor limit. Existing lifecycle cases cover interruption, offline cache,
uninstall and rollback; host coverage also exercises repair and deployment.

The controller runs the new assertions and existing distribution lifecycle on
both architectures using retained committed kernels. Receipts bind the kernel,
init, both assertion programs and serial output. These are controlled admission
checks. Stable administrative inputs and controlled ancestors remain required;
arbitrary concurrent administrator mutations, physical-media power loss,
whole-service heap retention and large-application throughput are not qualified.
Complete-tree verification adds payload reads. Broader roadmap release gates
remain open.

## Recorded results, 2026-10-15

Baseline `89e35cea5` activated changed staged state bytes. Final assertions
refused that change and all 90 preparation/staging/publication/activation cases.
They preserved current state, history and outside data, emitted no completion,
cleaned the unpublished stages and retained published failures for inspection.
An offline cache retry and rollback succeeded. A raced empty publication target
was preserved; retry used a fresh identity. Four late rollback mutations refused,
then restored whitespace-compatible state retried successfully.

All 29 host compile/run checks passed: nine core runners, the checker heap probe,
generation admission and distribution under clang ASan/UBSan, and signed real CLI
lifecycle/maintenance. Leak detection was disabled and undefined behavior was
fatal. The heap probe measured zero retained checker allocations in 128 valid
checks and five sets of 128 refusals (namespace, metadata, payload, registration
and lease). This does not qualify whole-service heap retention. Generated C was
reviewed for borrowed directory-entry views, stack stat records, independent
queue string copies and all checker scratch cleanup.

Fresh QEMU TCG runs passed on AArch64 (112.5 seconds) and x86_64 (121.0 seconds),
including all new markers, existing distribution lifecycle and guest-initiated
shutdown within the 600-second budget. Both architectures completed 128 valid
and 128 refused 64-level scans under a 32-descriptor limit. Five-artifact receipts
bind each committed kernel, init, both programs and serial output. Compiler,
source, generated C and logs are pinned. Broader publisher/catalog rollout,
graphical, device and runtime release gates remain open.

Evidence:

- [before regression](results/2026-10-15/generation-admission-baseline.txt)
- [host results](results/2026-10-15/generation-admission-host.json)
- [host summary](results/2026-10-15/generation-admission-host.txt)
- [generation assertions and lifecycle](results/2026-10-15/generation-admission-core.txt)
- [sanitizers](results/2026-10-15/generation-admission-asan.txt)
- [signed CLI](results/2026-10-15/generation-admission-cli.txt)
- [source/artifact ledger](results/2026-10-15/generation-admission-toolchain.json)
- [aarch64 receipt](results/2026-10-15/generation-admission-aarch64.json)
- [aarch64 report](results/2026-10-15/generation-admission-aarch64.txt)
- [aarch64 serial](results/2026-10-15/generation-admission-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-15/generation-admission-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-15/generation-admission-x86_64.json)
- [x86_64 report](results/2026-10-15/generation-admission-x86_64.txt)
- [x86_64 serial](results/2026-10-15/generation-admission-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-15/generation-admission-x86_64.qmp.txt)
