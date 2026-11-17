# Firmware-cache barrier and threshold heap collection

Supported G13 kernel-buffer allocation entries now inspect private and
GPU-read-only deferred heaps. If either exceeds 16 MiB or 2,048 objects,
the manager issues a synchronous firmware-cache barrier, then collects each
heap's captured FIFO count. Equality does not trigger collection; heap limits
are independent. Startup and unsupported hardware do not publish a barrier.
Shared and shared-read-only classes retain their immediate-release policy.

The packaged Asahi manager at Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf` implements those thresholds in its
allocator accessor. Its full-cache barrier uses `DestroyContext` with both
context IDs set to `0xff` and no context pointer, then waits for the device-control
token. The 48-byte Vinix command matches the two supported layout variants:

| Firmware ABI | Command tag | Context-ID byte offsets |
| --- | --- | --- |
| v12.3 | `0x17` | `0x14`, `0x15` |
| v13.5 partial | `0x18` | `0x11`, `0x12` |

Upstream inserts an enum variant starting with v13.3, shifting the tag, and
removes padding before the two packed `U32` fields, shifting the IDs. Every other
byte, including the context pointer, is zero. Unsupported ABIs are rejected.

The existing manager lock serializes publication, token polling and collection
with other device-control producers and shutdown. Polling uses hardware time
and memory barriers, with a one-second timeout. It does not hand control to
the dying-thread scheduler path. The stack message is copied synchronously.
Failed publication, a full/corrupt ring, timeout or state/fault change leaves
this helper's pending records reserved. On success, later releases remain
pending and live records keep their addresses. Independent review found no
remaining lifetime or locking blockers after correcting the versioned tag and
polling path during development.

Offline validation passed:

- ASan/UBSan with `-gc none -manualfree` and fake-stack detection checks every
  command byte, unsupported ABIs, 256 threshold boundaries and 528 production
  heap/channel cases. Both trigger heaps, unequal snapshot counts, live pins,
  later releases, immediate/delayed acknowledgements, pointer wrap, failed
  doorbells racing with consumption, full/corrupt rings, timeout and state/fault
  transitions are covered. Retired metadata must be poisoned; live and later
  owners must remain accessible.
- Ten compiled counterexamples fail runtime assertions. Five generated-C
  mutations are rejected. Source contracts check upstream constants, accessor
  ordering, versioned layout and command/token sequence. All 65 focused test
  files and the sanitized G13 failure suite pass. The whole-driver audit still
  reports `not_equivalent`.
- Isolated ARM/x86 builds pass. ARM C verifies stack/scalar-only new operations,
  ten unchanged allocator bodies, nine existing GPU lifetime/flush bodies,
  three channel bodies, nine owning layouts and the exact allocation-entry
  transformation. The historical x86 whole-C check encountered compiler drift;
  a fresh baseline generated with the current compiler passes the original
  strict checker. Both baseline C and `check-x86-current.log` are retained.
- Allocation counts remain 379 ARM / 289 x86 sites. The source graph grows from
  833 to 834 ARM files and stays at 813 x86 files. Per-file/per-kind counts and
  existing allowance-check failures are unchanged; no allowance was edited.

This is **not full collection-scheduling equivalence**. Existing eager job,
queue and render-buffer teardown GC, allocation-pressure retry, backing objects,
accounting and native performance remain different. Continuing allocation after
a failed threshold barrier matches upstream, but a subsequent legacy full-GC
path may still collect; this helper's retention guarantee is not a global policy.
Existing UAT invalidation polling still uses `sched.yield(false)`, whose ARM
semantics need a separate correction. The new cache barrier avoids that path.
Modern UAPI/Mesa integration, remaining stage backing/event destruction,
firmware lifecycle/cache teardown, timestamps, fences/timelines, wire defaults,
topology and power/reset also remain incomplete. No native timing, slab-rate or
firmware-execution claim follows from these fixtures.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-heap-gc-20261117/`.
Baseline revision is `5437c4df994adf5e6a3cf6b2ebea40e3dfd47bd9`; three production
overlays are retained. Test sources, C, binaries, build inventories, source audit,
negative cases and development diagnostics are preserved in the complete bundle.
The historical inventory checker verifies it and the full archive restoration.
`completion.txt` binds the committed feature paths and reports to that evidence.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `9823e661ef6030060bed4478007d6718f5b9f95778c1a7c8ceadccc9e03be629` |
| `bundle.tar.gz` | `9aacb172daa2a45d60895873ba9229096c784a34b0dcec1173cf9fa9bc7f3f07` |
| `bundle/vinix-aarch64` | `4abbef656178e3c57516c395dfa4a643622f405bf0cbc5e6953e41dfe78430f0` |
| `bundle/vinix-x86_64` | `1fc52f8c704dce284626b17b9d43c5e1fbede47f27c790eb2bdd0c5bfdc6dfa3` |
| `bundle/blob-aarch64.c` | `b0e80dbba38356f83809dc3756eac4e5449e8d2a77ec2c9983ea21ffe571021f` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
