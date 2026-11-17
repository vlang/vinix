# Returning AGX worker scheduling

The G13 event worker, G17 idle event worker and fake backend's dependency wait
now call `sched.reschedule()`. Their previous `sched.yield(false)` calls never
returned: ARM entered the dying-thread idle path, and AMD64 halted without
saving the caller's context. A worker could therefore stop after its first
handoff and miss subsequent completions or failure cleanup.

The existing returning API preserves the runnable thread. Each worker releases
its manager lock before the handoff. The production change is exactly three
call substitutions; no allocation or ownership is added. The extra reschedule
after `syncobj.wait()` is redundant but safe. The actual terminal fake completion
worker still frees its owned state before `dequeue_and_die()`. Independent
lifetime review found no lifetime or locking blocker.

Offline validation passed:

- ASan/UBSan with `-gc none -manualfree` passes 40 multi-cycle G13/G17 cases
  and 96 delayed/ready/null/mixed dependency cases, including failure shutdown,
  later message delivery, manager lock release and first dependency errors.
  These are extracted production loops with host stubs, not native scheduler
  or firmware execution.
- Eight compiled negatives reject the three original calls, three omitted
  handoffs, missing shutdown and swallowed dependency errors. Nine C-checker
  mutations are rejected. All 67 focused test files and the existing sanitized
  G13 failure suite pass. Source guards cover both returning scheduler APIs and
  preserve terminal teardown; the orphan-resource guard rejects the old call.
- Both isolated kernel builds pass. ARM generated C differs in the three worker
  bodies only by the intended calls after resolving interned strings by value
  and normalizing numeric path hashes in discard-variable names. Nine scheduler,
  fence, termination, service and cleanup bodies match. The original strict
  checker confirms whole x86 C matches the predecessor after path-hash
  normalization; these workers are absent from the default x86 kernel.
- Allocation sites and source counts match the predecessor: ARM 379 sites /
  834 files, x86 289 / 813. Per-file/per-kind counts and existing allocation
  allowance failures remain unchanged. No allowance was edited.

The fresh source audit still reports **not_equivalent** against packaged Asahi
`bed544bdf93a496ebf70ba180923bab12b6e01cf`. This corrects Vinix's use of its
scheduler API; it does not establish native fairness, timing, firmware lifecycle
or full driver parity. Eager teardown/allocation-pressure GC, allocator
backing/accounting, modern UAPI/Mesa integration, remaining stage backing/event
destruction, firmware/cache teardown, timestamps, fences/timelines, wire
defaults, topology and power/reset remain incomplete or unqualified.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-worker-reschedule-20261117/`.
Baseline revision is `1d6a2f2ee12e2519e475328df6579773ff15fdc8`; only the three
production source overlays differ in the isolated kernel worktree. The complete
bundle retains sources, binaries, generated C, native inventories, baseline
inputs, negative cases, source audit and lifetime review. It also preserves
initial diagnostic failures and their corrected final runs. The original
inventory checker verifies both the canonical bundle and its full archive
restoration. `completion.txt` binds the commit to the sealed evidence. Raw
results remain outside Git.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `1fcba8ea51c199dd504350bf7fe07fb84fb301b0fc8a30d4564f90dd7f68a0b6` |
| `bundle.tar.gz` | `a6499bc8f7efb06b87bc771fa5c4b02ec1a2d82fde47c5c27269fe128adc98ea` |
| `bundle/vinix-aarch64` | `a596256831a90efc9488d9acbc77496fd465d1ee03a27b1ce29d258add25828c` |
| `bundle/vinix-x86_64` | `01ff8298636dcf92ba411c9af87a43b2f4ff610ad1b269efdcaff50a51fcf160` |
| `bundle/blob-aarch64.c` | `f7ad53f8925128c33b666f12e82980de4dbfbd2e46120ddafaf590d0dd9b2033` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
