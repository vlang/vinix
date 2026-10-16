# Software deployment file selection

Software's **Deployment → Choose file…** opens the existing session file dialog
for organization root manifests, exact deployment locks and saved installed
snapshots. It starts in the current path's parent, or the user's home directory
when the field has no valid absolute path. A parent/home exceeding the session
record's bound falls back without truncation. The manual field continues to
accept paths up to 4096 bytes. The dialog uses the existing bounded session
protocol and does not filter by extension.

Selection fills a validated literal UTF-8 path. It starts no package worker,
review, authorization or transaction. **Review deployment** retains its existing
frozen path/fingerprint and explicit confirmation. Cancellation, invalid results
and broker failure preserve the field; an unavailable dialog explains the manual
path alternative. Repeated clicks cannot open duplicate requests. Intervening
input, navigation or another operation invalidates the pending selection. Its
eventual result is drained without changing the current draft, review or status,
including navigation away and back and pending audit/snapshot work.

The [fixture](software_deployment_chooser_fixture.v) runs the actual Software
controller against a freshly compiled session daemon over authenticated local
IPC. It acts as the compositor only to inspect dialog requests and deliver
selection/cancellation results. It covers pending polling, duplicate suppression,
literal Unicode/metacharacter paths, manual review, cancellation, invalid UTF-8
and control bytes, late edit/navigation/review/audit/snapshot responses and a
disconnected/unavailable broker. The allocation mode separately measures result
admission, directory selection and full/compact rendering, including 4096-byte
and oversized paths and retirement after navigation.

Run the maintained V driver with the generated desktop assets and headless ui2
module described in [deployment UI qualification](deployment-ui-check.md):

```sh
v -o /tmp/distribution-check tests/packages/distribution-check.v
/tmp/distribution-check --direct-tests --software-only --desktop
```

These are host controller/session-IPC checks, allocation measurements and Linux
target typechecks. They do not establish compositor presentation, ordinary-user
graphical login or the remaining production catalog/runtime acceptance gates.

## Recorded results, 2026-10-16

All fourteen focused compile/run checks passed: the full Software functional
fixture, real-broker chooser, chooser and deployment-navigation allocation
modes, the same controller checks under ASan/UBSan and a fresh launcher check.
The broker used its
normal build; sanitizer leak detection was disabled. After warmup, 1,000
chooser result/directory/full/compact lifecycle cycles retained zero tracked
bytes. This measurement excludes whole-session IPC and service processes.

The maintained Software-only distribution run passed its functional suite,
all 26 allocation modes and both full desktop Linux architecture typechecks.
Its final launcher helper omitted the account module path; the corrected helper
passed a separate fresh compile/run. The raw driver failure and passing retry
are retained. Compiler, source, copied fixture and binary/log hashes are pinned.
The driver resolves repository modules before the headless ui2 overlay; an
initial stale-overlay interface failure and its correction are recorded.
No new guest presentation or full graphical-session acceptance is claimed.

- [focused checks](results/2026-10-16/software-deployment-chooser-host.json)
- [summary](results/2026-10-16/software-deployment-chooser-host.txt)
- [controller and real broker](results/2026-10-16/software-deployment-chooser-ui.txt)
- [allocation checks](results/2026-10-16/software-deployment-chooser-memory.txt)
- [sanitizers](results/2026-10-16/software-deployment-chooser-asan.txt)
- [maintained driver and both architectures](results/2026-10-16/software-deployment-chooser-driver.txt)
- [initial overlay diagnostic](results/2026-10-16/software-deployment-chooser-attempts.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/software-deployment-chooser-toolchain.json)
