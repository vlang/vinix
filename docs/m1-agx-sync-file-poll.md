# Sync-file completion readiness and wakeups

Offline increment, 2026-11-16. Full M1 equivalence remains **incomplete**;
see [the parity report](m1-agx-parity.md).

An exported sync-file created before completion previously kept its initial
unreadable status indefinitely. It now reports `POLLIN` when its immutable fence
completes, including completion with an error. Its first pending poll registers
a wake subscription; first completion advances the resource event and wakes
poll/epoll consumers through the existing event machinery. This follows the
selected readiness/callback/release behavior of the
[packaged Linux sync-file implementation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/dma-buf/sync_file.c).

Each wrapper embeds one borrowed subscription node; each fence holds a list
head. Readiness, registration, notification and cancellation share the fence
lock. Completion detaches and clears nodes before notifying, retaining the
lock through every event trigger. Final wrapper release always takes that
immutable fence lock to cancel before freeing its box and wrapper. Repeated
polls and duplicated descriptors reuse the node; separate exports get separate
events. Replacing or destroying the source syncobj leaves the snapshot intact.
Subscriptions add no allocation, but the new embedded fields increase metadata
size and can change slab cost. Native heap cost was not measured. Published
object/fence reclamation remains unchanged.

Validation passed:

- ASan/UBSan with stack-use-after-return detection: 10,800 poll cases covering
  pending/completed/error readiness, repeated probes, immutable old snapshots,
  fanout, duplicates, first/middle/last close, source namespace teardown and
  exact-lock signal/close/initial-poll interleavings. Before freeing export
  storage, a hook checks that no fence still references its node or event.
- A primitive case registers 4,096 borrowed nodes, checks duplicate registration,
  cancellation/re-registration, cleared links and exactly one wake each.
  All 58,450 prior synchronization cases, 4,103 geometry probes and 200 capture
  primitive cycles pass. The shared host Event fixture models locked generation
  changes; native blocking poll/epoll syscalls and scheduler threads were not run.
- The unmodified DRM wrapper from
  `89e1a2f9ad9c86096b12be3d1c5b80f5793d291d` passes all prior synchronization
  cases and generic event primitives, then fails the new observable readiness
  assertion: it returns zero after completion instead of `POLLIN`.
- Async submission, DRM wire/node and fence sanitizer regressions, nineteen V
  test files, selected source/reference gates, and strict generated-C checks
  requiring 75 live ARM helpers plus negative allocation selftests.
- Isolated ARM and clean x86 builds from
  `cc91a06ed43bc1d293dc260d1645bbc4ea2519b0` plus three retained overlays:
  `kernel/drm/drm.v`, `kernel/drm/syncobj/syncobj.v`, and
  `kernel/drm/syncobj/events.v`. Selected sources, reviewed event/resource,
  file/epoll and scheduler support match the private inputs. Both ELF/C pairs
  and overlays were retained before switching architecture; x86 excludes AGX.
- Independent design/source/ARM C lifetime review found no defect under the
  immutable fence/node/event contract. Poll dispatch uses stack scratch and
  the actual wrapper event without boxing. No reverse lock path or synchronous
  close reentry was found through event wake and either scheduler backend.

The unchanged global allocation allowance audit **still fails** for baseline
and feature. Both report 383 ARM/289 x86 sites, with identical per-file/per-kind
counts; source counts increase by one to 823/809. No auditor or allowances were
relaxed. This is not native heap, leak or concurrency qualification.

Fresh Omarchy `4bf10ed28342b597009dcf573ffc0d70b94b31e3` and packages
`cce66eb75505f769d6894305f0e720f64d31e7a4` match checked remote heads. The
package checkout was refreshed after moving during cloning. Pins remain Linux
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`, and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Exact `sync_file.c` is now
required clean and retained by the audit. Selected gates pass; the full verdict
remains `not_equivalent` (exit 1).

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-sync-file-poll-20261116/`.
Canonical `bundle/` retains sources/references, executables, C, logs, review and
the unchanged complete typed inventory checker. Canonical and fully restored
archive inventories are verified. The first seal rejected an inherited log
filename; its partial `failed-source-copy/`, seal and log remain retained.
`completion.txt` binds seventeen non-report paths, including one deletion, and
two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `8de71c20d25eafa1862ccbed22139a27fbb683d331346ca5a8cdf493a33856be` |
| `bundle.tar.gz` | `8287c31625baf9b7b0fc204a7478334c5ab036368f7d343c737729869cbd100a` |
| `bundle/vinix-aarch64` | `ee55078ca33ff5658c469dd29d9ef5e51a649e766af6d48ead86fc8e4d3a966d` |
| `bundle/vinix-x86_64` | `2838b8e8da9e9b4e2ebb5d80090f373087350815853599dd5dba0ae2ab35eb77` |
| `failed-source-copy.inventory.json` | `8268da7641b0647390bf62921692c37e1bc043859a90cbf94e138d6b5db13c14` |

Sync-file info/merge ioctls, export reservation/error precedence, modern
ABI/Mesa integration, timeline chains, other generic descriptor behavior,
indexing/locking performance, reclamation, syncobj callback waits, cache/accounting
and hardware behavior remain open. No Vinix boot, GPU/firmware execution,
hardware test, reboot, SSH or deployment occurred.
