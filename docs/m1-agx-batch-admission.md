# M1 AGX whole-batch admission, 2026-11-15

Status: **incomplete parity**. This change matches the packaged Asahi driver's
whole-job event/ring readiness check before the first command publishes. A
64-command batch behind 63 older same-pipe publications now waits intact for
host retirement instead of publishing its first 63 commands and blocking the last.

The manager checks all participating vertex, fragment and compute subqueues under
its lock. Counts include explicit prefixes after initial-event compaction,
fragment barriers and simulated first/growing TVB bindings. Strict reference
spare capacity remains required. After every pipe passes, existing prepared event
tickets receive scalar admission grants. These prevent repeated event charging
between commands when canceled predecessors leave stamp gaps. Publication consumes
the grant; cancellation and fresh ticket initialization prevent grant reuse.
Slot ownership, ticket identity, publication FIFO and actual ring-write checks
remain enforced. The pending node caches one scalar and retains no borrowed job
references after publication.

Source baseline: `a2d8b8731c908f5c38df555bcdb1af2b1139d6d0`, with the three retained
AGX event/poller/admission overlays. Every AGX/syncobj V file matches the isolated
build checkout; all three overlays match both retained build inputs. The feature
commit is bound to all 16 implementation/test/source-gate snapshots in the sibling
`completion.txt`; these reports are retained separately after committing.

Remote heads were rechecked unchanged: Omarchy
`4f26515d55f5d03ddf884a8b416f3b66b8ee7ae4` and packages
`703430e884c0c46bce2a83f11c34a44af3f2ec5b`, still selecting Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf` and Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`. The m1n1 reference is
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

Offline validation passed:

- Actual production preflight/event/reaper ASan/UBSan checks: 63+64 compute/render,
  each physical event pipe independently full, mixed ring equality and retirement
  retry, zero/one/two prefixes, TVB binding/growth, identity/ticket rejection,
  corrupt counters, initial-prefix wait/compaction/flush retry, 125 canceled
  predecessors followed by two admitted publications, and canceled-grant reuse.
- Real-ioctl async ASan/UBSan checks with injected GPU/capacity services: independent
  queues, mixed-batch deferral/FIFO, retries after pointer transfer, shutdown during
  admission and its final callback-count load, plus prior ownership regressions.
- Event and failure/recovery/publisher sanitizer regressions, three V unit suites,
  negative source contracts and all selected reference/audit gates. Thirty generated
  ARM helper bodies pass allocation/structural-copy/fixed-storage checks and negative
  checker selftests. Independent lifetime review approved the final grant lifecycle.
- Isolated ARM and clean x86 builds. Ordinary x86 excludes AGX. This is not a
  whole-kernel allocation measurement or native GPU execution result.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-batch-admission-20261115/`.
The complete canonical `bundle/`, `inventory.json` and `bundle.tar.gz` are retained.
Full archive extraction and both restored/canonical inventories passed the unchanged
inventory checker. Preliminary failures and pre-grant output remain diagnostics.

| Artifact | SHA-256 |
| --- | --- |
| Inventory receipt | `e110945e03b869099b36fc8600fafb06dbb02e86cc32dd414464501836d2da2a` |
| Complete archive | `2a8e7e9bb9fa10a210842e3dc8b9e00cf016eb8fe65b7b75d2f7ba8e48085b6a` |
| ARM ELF | `0bdc43b8e2951ad020bdd53a1165bd58167179732ecea2e93ccc4f3e81106d59` |
| x86 ELF | `49fba3c1e0775a4fcf61cabc9c994383eb4331c7028a53a781e6d52a66354ac5` |

The final audit still returns **not_equivalent** (expected exit 1). Full transactional
subqueue publication/notifications, prepared backlog beyond 127, modern ABI/VM/GEM/Mesa
integration and other unverified driver paths remain open. Outer-ring backpressure
can still cause partial publication after admission. No Vinix boot, hardware test,
reboot or deployment was performed. Prior evidence remains unchanged; see the
[main parity report](m1-agx-parity.md) for the remaining gaps and historical incident.
