# M1 AGX prepared batch publication, 2026-11-15

Status: **incomplete driver parity**. Native submissions now prepare every
participating subqueue before exposing the first write pointer, matching the
packaged Asahi `QueueJob::run` ordering. A 64-command batch needs one outer
notification slot per participating pipe. A full later pipe holds the whole
batch; it no longer leaves an earlier pipe partially published.

The manager validates addresses, complete event FIFO, host/GPU ring space and
every outer pointer under its publication lock. Pending-operation wake preparation
can fail and roll back before notifier accounting or hardware visibility. Commit
installs all command records, retirement positions and ownership first, then
exposes and notifies fragment, vertex and compute in that order, once each.
Notification failure after visibility transfers the entire batch and stops new
dispatch; backing remains owned until completion or stopped-firmware cleanup.

The file worker handles a scalar ownership mask and clears transferred pointer
values without dereferencing metadata that may already be freed. Native returns
either zero or the full mask. The async fixture deliberately permits partial
transfers to retain adversarial callback/fault/shutdown coverage. Installed firmware
prefixes order execution without CPU callback waits.

Whole-sequence event validation rejects an omitted unpublished middle ticket
before accounting or ring mutation. Explicit synchronous stack-element borrows
avoid V escaping the local ring plan into an allocation. Final generated ARM C
contains actual stack storage; all 33 live monitored helper bodies pass allocation,
structural-copy and fixed-storage checks plus negative selftests. V omits three
now-unreachable standalone publishers; their unchanged source remains exercised
by the failure fixture. Earlier sealed checkers and evidence remain unchanged.

Validation passed: 75 actual publisher/channel/event/reaper ASan/UBSan transactions
cover compute/render/mixed batches of 1/2/63/64 jobs, ring and stamp wrap, canceled
gaps, prefix/TVB byte oracles, exact notification capacity, late-pipe refusal and
retry, invalid middle tickets and write offsets, pending overflow/wake rollback,
counter wrap, and notification-failure quarantine through injected firmware stop.
Every final physical event slot returns. Prior admission/initial/barrier/TPC,
async ownership, event and standalone failure/recovery sanitizer regressions,
three V unit suites and selected reference/source gates pass. Independent reviews
approved ownership transfer, complete FIFO, lock ordering and stack borrows.
ARM and clean ordinary x86 cross-builds pass; x86 excludes AGX. No whole-kernel
allocation measurement, native GPU execution, Vinix boot or reboot was performed.

Build baseline: `0381561f61a21cd730209925bbf958579227ff41`, plus the four retained
event/poller/admission/batch overlays. All AGX/syncobj V sources match the isolated
checkout and audited snapshot; all four overlays match both retained build inputs.
The sibling `completion.txt` binds the feature commit to 14 implementation/test/
source-gate snapshots; these self-referencing reports are retained after commit.

Fresh Omarchy `9e989357f377fe3165aa15c61902963a888ed4b4` and package repository
`ce6125bbb7a5bb7e7f14a7926d84501777a9edf0` still pin Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf` and Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`. The Apple defaults now delegate their
Vulkan dependency to `omarchy-mac`; its retained recipe depends on `vulkan-asahi`,
provided by `mesa-aurora`. The m1n1 reference remains
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

Complete evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-batch-publication-20261115/`:
canonical `bundle/`, `inventory.json` and `bundle.tar.gz`. Full archive extraction
and restored/canonical inventories passed the unchanged inventory checker.
Preliminary test/build/checker failures remain diagnostic evidence.

| Artifact | SHA-256 |
| --- | --- |
| Inventory receipt | `1a179377194940fd8b5c8ade9ed413d07c164bdc0a71e2bcc78d488c5f514dc8` |
| Complete archive | `42aba1c169520a4147b5a14d05fdc1ea17e309abd45633b16908cb2e46550027` |
| ARM ELF | `7fa983aef81f8f24943c1b801c329d9616edbacd56992d3a5577d400868da2db` |
| x86 ELF | `4857751722487c7a2ae595bbd7e914c7c67d1b220c8a2ecb2a0e0fe36e1b9655` |

The final audit still returns **not_equivalent** (expected exit 1). Prepared backlog
beyond 127, modern ABI/VM/GEM/Mesa integration and other unverified driver paths
remain open. This closes the native transaction/notification gap identified in the
[earlier admission report](m1-agx-batch-admission.md), without certifying complete
driver equivalence. No hardware test, deployment or publication was performed.
