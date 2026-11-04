# Wireless controller discovery checkpoint — 2026-11-04

`333afb4f215508e8ba38de7fbc0abc0e83f200b4` implements
`+[GCController startWirelessControllerDiscoveryWithCompletionHandler:]` and
`+stopWirelessControllerDiscovery` for the existing empty input backend.
There is no Bluetooth transport or physical-controller bridge. A search
therefore completes empty on the next main-queue turn; no device or connection
notification is fabricated. Main-queue delivery and this immediate empty
result are explicit backend policy, not measurements of native scan timing.

Starts during an active search replace its retained completion, including a
nil replacement. Stop ends replacement eligibility while preserving that
operation's queued completion. A subsequent start owns a separate operation.
Completion detaches its operation before calling application code, allowing
reentrant searches to run on a subsequent turn. Block copy/dispose helpers and
callbacks run outside registry and scheduler locks. The dispatch job owns its
context; the shared active pointer is borrowed. Shutdown retires discovery
before managed threads join, and scheduler cleanup releases pending captures
without invoking them before runtime teardown.

This follows the asynchronous completion and early-stop model in Apple's
[controller discovery guide](https://developer.apple.com/library/archive/documentation/ServicesDiscovery/Conceptual/GameControllerPG/DiscoveringControllers/DiscoveringControllers.html).
Native Catalyst metadata matches `v24@0:8@?16` and `v16@0:8`. Native scans
were not started. The current macOS 27.2 framework has a 296-byte GCController
class; the earlier reference used 232 bytes. The native fixture records and
accepts both measured sizes. Vinix retains its original layout and construction
guard because its backend does not construct physical controller objects.

The expanded GameController fixture passes normal and deterministic ASan/UBSan
runs, native metadata comparison, and standalone guest execution. It covers
nullable and replacement handlers, duplicate stops, stop/start isolation,
callback reentry, capture retention and release, destruction while another
thread acquires the registry lock, 512 concurrent starts per runtime, subclass
sharing and pending-operation shutdown. Two runtime cycles drain all objects,
blocks and dispatch state. Existing physical-profile, color, mouse, construction
rejection and StoreKit host regressions pass. The focused driver now selects
Catalyst for the GameController fixture.

The final guest uses 4096 MiB and four CPUs. Its state is
`guest/game-controller-1491666/`, with child wait status 0 and
`VINIX iOS GAMECONTROLLER: PASS`.

Fortnite passes the previous missing-method boundary and reaches Unreal's GPU
requirements check. It displays this alert:

```text
This device does not support the Apple family 3 GPU features (Apple A9+), which is required as the minimum for this engine version.
```

The existing `metal_device.c.v` deliberately returns nil from
`MTLCreateSystemDefaultDevice`: its GLES renderer cannot execute Metal command
buffers or AIR shaders. The next work is an actual Metal rendering backend and
the capabilities Unreal needs. Reporting a supported GPU family without that
backend would not make this game render. Controller transport remains empty.

All 46 guest fixtures return status 0 (45 reused plus freshly rebuilt StoreKit),
and supplemental StoreKit inspection passes. The game uses original cooked
content with advertising skipped, 8192 MiB guest RAM, one CPU, a 2 GiB process
budget and the existing 60-second desktop window. The final desktop peer records
497 snapshots, 496 polls, handshake=true, closed=true, supervisor_kill=false and
wait=0. Its UI grows from one to two nodes, with zero images throughout. These
are UI tree snapshots, not game frames or a game frame rate. The game exits 0
after the controlled window closes; capture exit is 0. There is no application
runtime panic, and all six budget event counters are zero. The final charge of
1566990 bytes is measured after exit, not peak memory use.

Progress remains **four of eight observed gates**: loading/binding, +load,
initializers and application entry. A rendered game frame, menu, login and
playable match remain unverified. This is not a 50% engineering estimate or an
ETA. Reaching the engine's unsupported-GPU alert identifies a substantial
rendering gap beyond the Foundation/startup compatibility fixes.

The saved historical inspector and seal command correctly reject this capture
because their contract requires one runtime panic, process exit 1 and an
unclosed desktop peer. Their rejections remain in `operation-inspect.log` and
`historical-seal-rejection.log`. A separate saved `check` invocation rejects the
absent historical manifest. No historical checker was relaxed, and this capture
is not a sealed launch qualification. The original full guest-media audit and
339-control qualification were not completed for this different outcome.
All complete capture files are instead protected by an external typed inventory,
as required for diagnostic outcomes outside the historical checker's contract.

`gpu-gate-diagnostic.v` independently checks this specific diagnostic profile:
46 distinct zero-status fixtures, the GPU alert, consecutive UI snapshots with
zero images, guarded termination and clean budget counters. Normal and
ASan/UBSan analysis agree on the capture, and both self-tests reject 12 corrupt
inputs. This read-only analysis does not verify guest media or qualify rendering;
its source, executables, results and the unchanged historical rejection are
preserved with the capture. The game capture pins `2405826ea` (the runtime
matches `333afb4f2`); its diagnostic helper is committed separately as
`63148d41a`.

Complete focused evidence under `/Users/alex/Library/Caches/vinix-ios/`:

| Artifact | Location | SHA-256 |
| --- | --- | --- |
| Validation bundle, source `333afb4f2` | `controller-validation-20261104-r1/` | External receipt below |
| Validation receipt | `controller-validation-20261104-r1.inventory.json` | `836fcf00193a235d8681e9093727ef458a6c169869da4e241aba301656cda3f6` |
| Validation source | `controller-validation-20261104-r1/source.tar` | `d5719642a07f3f764387ede3904a75f27128807b2831622d93fe768f4dfb366a` |
| Complete diagnostic capture | `controller-probe-20261104-r1/` | External receipt below |
| Capture receipt | `controller-probe-20261104-r1.inventory.json` | `4487f8a42ae1b24d006c0dbc73848d4aab194f48e16c5ea54b35b197bcd3af69` |
| Capture source, revision `2405826ea` | `controller-probe-20261104-r1/source.tar` | `9126f59a92987987e5a172b2e45ebab50c043d82eca4c9493560670893c996e2` |
| Runtime | `controller-probe-20261104-r1/run-ios-gles` | `56f84288a39e67865b73830ce016599606cdbd9d34c7ec63f3023fea3c8205ad` |
| Serial | `controller-probe-20261104-r1/probe-no-ads-132916/serial.log` | `69af4340ad06b3a9fe22b2fb7482e0d6132aa5d64947f2df53b827ecc2c3298d` |
| Diagnostic helper source, revision `63148d41a` | `controller-probe-20261104-r1/diagnostic-tool-source.tar` | `45c2358e605e1f71594447b9cd6886774f0dd02d8875fe52c91258ee2316ed19` |

Storage preparation preserved complete checksum-bound historical archives and
their unchanged auditors. Nine expanded restorations passed direct archive
comparison of every path, byte, size, type, permission and link target, then
their saved historical checkers, before retirement. Seven incomplete original
working copies were separately backed up and restored exactly; their existing
auditors correctly rejected missing media. The new archive coverage check
proved every temporary backup entry is also preserved in its complete retained
archive before retiring those redundant backups. Three further old partial
working copies passed the same round-trip and coverage checks against archives
whose complete restoration and historical audits were preserved in the earlier
display-pump storage proof. Historical auditors were not modified.

`2405826eac3196ec68595829bca83b601fe8b1da` adds this read-only coverage
mode to `swift-staging-archive.v`, shares the strict mtree parser with the
existing full restoration checker, and documents retirement requirements.
Normal and ASan/UBSan self-tests pass all 21 corruption controls, including
eight coverage-specific cases for uncovered entries, both archive bindings,
changed bytes, permissions, types, root mode and link targets. Coverage permits
additional retained entries; it does not qualify partial launch evidence.

Storage proofs under the same cache root:

| Proof | External inventory receipt | SHA-256 |
| --- | --- | --- |
| Nine complete archive/restoration and historical checks | `controller-storage-validation-20261104-r1.inventory.json` | `446292666f1d32152c665ff8118ca1ce2f2f7689fd109adce2acea92d75c1ce6` |
| Tested coverage tool, self-tests and seven archive comparisons | `controller-archive-coverage-validation-20261104-r1.confirmed.inventory.json` | `d237ae1cd8bb52af399b19d7fe75cc24e88236652c2064cce154638fa5ff286b` |
| Three additional retirement proofs, including earlier full archive audits | `controller-extra-storage-validation-20261104-r1.inventory.json` | `5b18ac4449079ca9b16a9cf31e553f26d31225b46c2d0ecbb6d57b440d58c69d` |
| Final retirement records, inventories and diagnostic rejections | `controller-legacy-partials-20261104.final.inventory.json` | `13d2b198a4c18df1637a14dc241b43f05884482292647042e1bc270fb55999f7` |

Each proof directory has the receipt's basename without `.inventory.json`
(the coverage directory also omits `.confirmed`, and the retirement records
omit `.final`). The original complete
20261025 tar.zst archives retain the hashes pinned in their original reports
and the new coverage logs. Restore those complete archives before rerunning
their historical auditors. Temporary gzip files and old partial directories
have been retired; their typed inventories, checksum records, coverage proofs
and diagnostic rejection logs remain. Per-entry temporary-backup inventories
are historical records; the final aggregate receipt describes the files now
present. The first two diagnostic `root-modes.log` files used an access-time
stat format and are not mode comparisons; root permissions are covered by the
mtree checks. Later mode logs use `%Lp` correctly.
