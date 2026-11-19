# G13 user mappings while jobs run

Vinix used to refuse, or defer until the VM was idle, every operation that
removes a user GPU mapping while the VM had jobs in flight: `VM_BIND` or
`GEM_BIND` over an existing mapping, range unbind, legacy `UNBIND_ALL`, and the
retirement of mappings whose GEM handle was closed. These now proceed at once,
as they do in Omarchy's pinned Asahi driver on G13.

## Why it matters

Omarchy's Mesa (`omacom/mesa` `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`)
frees a buffer by returning its GPU address to its allocator and then closing
the GEM handle; it does not unbind the address first. Another thread can bind
a new buffer at that address immediately. One VM serves a whole context, so
other work is almost always running. Vinix answered such a bind with `EBUSY`,
which fails the allocation in Mesa. The legacy path used by the bundled
Mesa 25.0.5 had the same refusal.

In Asahi, `unmap_range` and `drop_mappings` defer only when the VM's
`lifetime` is blocked. That state exists only for G15 and G17 VMs; on G13
`lifetime` is `None`, so unmaps commit immediately whether or not jobs are in
flight. The remap step removes the leaves and, if the VM is bound to a
hardware slot, invalidates the range for its ASID before the GPUVA releases
its object.
[unmap_range](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs)
· [lifetime](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu/lifetime.rs)

## What changed

Mapping retirement no longer checks the VM's in-flight count. It removes the
PTEs, completes the range TLBI for the bound ASID, checks the device state and
only then drops the mapping's GEM reference. A failed acknowledgement keeps the
record and its reference as before, and the retry runs whether or not the VM
is busy. A destroyed VM still keeps its remaining bindings and its context
until its jobs end; closed-handle bindings on it retire at once. Asahi tears a
destroyed VM's user range down immediately, so Vinix stays more conservative
there.

The change relies on one invariant, which an independent review confirmed:
every prepared, published or quarantined G13 job holds a slot lease, so its VM
stays bound and `unmap` always issues and completes the TLBI under the page
table lock before returning. Jobs reach user memory only through GPU
addresses; result and timestamp objects keep their own references. Like
Asahi, this assumes the UAT has finished accesses through the old translation
when the TLBI completes, and that the uncached user mappings leave no dirty GPU
cache lines.

The review also noted two existing issues that this change does not alter. A
retirement refused outside `GEM_CLOSE` is retried only by a later operation on
that VM or by file close, not by the worker. And `tlb.invalidate_range` does
nothing for a range the planner rejects; no retirement can reach that with a
range that passed bind validation.

## Validation

- The file-close fixture, with the modern ioctl checks, passes under its
  sanitizers. Busy-VM cases now check that unbind, `UNBIND_ALL`, replacement
  and `GEM_CLOSE` remove the PTEs once, drop references and retry a failed
  acknowledgement while the VM stays busy, and that a reimport neither cancels
  nor repeats a pending retirement.
- Two controls fail as intended: restoring the idle gate in retirement fails
  `check_repeated_bindings`, and restoring the busy early return in closed
  cleanup fails `check_mapping_retirement`.
- All four counterexample runners pass. The VM runner had been unable to run
  since an earlier commit made one of its anchors ambiguous; its anchors now
  name unique lines.
- `agx-async`, `agx-native-errors`, `agx-job-dependencies` (host),
  `agx-g13-failure` and `agx-tlb` pass, as do 79 G13 contract test files and
  all 122 pinned reference checks. The contracts now reject a reinserted busy
  gate.
- AArch64 (`LIMINE_MP=1`) and x86_64 `PROD` kernels build. The generated
  AArch64 C retires a mapping as unmap, device-state check, release. The
  allocation scan matches the previous 427 findings.

No hardware test or reboot occurred. Native M1 validation remains open.

Evidence is under
`/Users/alex/.local/state/vinix/omarchy-m1-busy-unbind-20261119/`.
The bundle keeps the change, logs and checksums. Compiled runners and
counterexample mutants were not kept; the runners regenerate them.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `599d0ff4ea4471d3df0d4eaaa39324cea7cfe07f05df17966f0d2d78d2030410` |
| `bundle.inventory.txt` | `345674b6001528d8d705ce7234a069c0929c4bd8b5be3578cab77f79581fb7e6` |
