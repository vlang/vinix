# Pending G13 timestamp ownership

Copied modern packets now produce the same canonical command array used by
legacy submission. Shared staging resolves timestamp objects, supplies their
addresses to native compute/vertex/fragment preparation, and transfers the
captures to the accepted pending node. The worker releases them after the final
callback, before dropping its file/VM pins. Forged output fences cannot release
the mappings. Modern public ioctl registration remains incomplete.

This follows packaged Asahi's retained `UserTimestamps` work owners in
[compute](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/compute.rs)
and [render](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/render.rs).
Vinix currently retains all captures until the entire batch retires. This is
conservative relative to individual work-owner retirement; resource release
timing and cross-command allocation/error ordering are not certified equivalent.

Capture storage uses one bounded fallible allocation, omitted for legacy input
with zero timestamp handles. Failure unwinds prepared jobs under the file lock,
drops that lock, then releases captures. Successful registration transfers
ownership once; the submit caller never reads the node or captured storage
afterward. Release runs outside the GPU manager lock. Missing-manager mapping
retries retain their existing behavior. Independent lifetime review found no
remaining blocker in this change.

Offline validation passed:

- Real packet decoding, capture helpers, shared staging and the pending worker
  run under ASan/UBSan with injected GPU services. Cases cover waits, backpressure,
  forged fences, callback completion, GPU fault, shutdown, all 64 command lookup
  failure positions, 42 allocation/preparation/callback/barrier failure cases,
  and 64 repeated maximum batches. The existing legacy async suite also passes.
  Four complete source mutations compile and fail their designated ownership
  assertions. Existing close/unbind capture regressions remain separate.
- All 52 focused V test files pass. Four new host/native generated-C storage
  guards reject hidden allocations, with 12 injected allocation counterexamples
  each. The 145 historical native guards and their three selftests pass;
  packet and timestamp-capture guards remain enabled. Generated C and independent
  review caught two implicit V heap copies during development. The final scan
  indexes command storage directly and keeps owner headers as small values.
- Fresh isolated ARM/x86 builds pass. Nine native preparation, cleanup,
  retirement and publication bodies, file close, queue capture/release,
  timestamp reaping and all four completion helpers match the preceding ARM C
  after resolving generated string IDs. The x86 C matches after normalizing
  compiler discard-variable path hashes. All six overlays match both snapshots.
- Wait, wire, fence, close, async, CPU-cache, VM, sanitized TLB, layout, render,
  packet-reader and source-derived model fixtures pass: 12,000 work images,
  14,400 timestamp images, 48,000 microsequence images, 30,375 tiling results,
  16,384 packet commands and 24,576 resolved destination images. All 12 packet
  adapter source mutations still compile and fail their designated assertions.

Allocation-site counts remain 381 ARM / 289 x86, with unchanged per-file/kind
counts and the existing allowance-check failure. ARM source count grows from
832 to 833 for the owner helper; x86 stays at 813. Native heap rates remain
unmeasured.

Fresh heads: Omarchy `dceae1857bc5df80eedbba07ff8a03c2dc428fdd`, packages
`48d5518a286d3af5a50703670ac53da98b836f99`. Selected package definitions are
unchanged. Linux remains `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`, m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. The full audit still reports
**not_equivalent**. Modern UAPI/Mesa integration, per-work release timing,
timestamp publication/units, mapping ownership across manager/UAT replacement,
firmware teardown, reservation fences, timelines, remaining wire/default
coverage, topology and power/reset behavior remain open.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-pending-timestamps-20261116/`.
Baseline is `e561faa23127be9406741182026f68fc9df8cfaa` plus 18 retained source
paths, including six native overlays. Nine independent unchanged runner binaries
are checksum-verified against the preceding complete bundle; dependent model and
async/packet runners are fresh. The unchanged typed inventory checker verifies
the preceding complete bundle, this complete bundle and its full restoration.
`completion.txt` binds the sources and reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `f6cb5a64fa1303c0c6c8d78a3befe3906d8c90e6f3fd4fd0ec1409bd07596e07` |
| `bundle.tar.gz` | `a1bdfc0f2ad61709858e4bf921be6604dba58095f2362faac5af9cee99f6c80e` |
| `bundle/vinix-aarch64` | `70493dfa912e93ca72584931a869f70e34356e6f6ef2d0aa6ab38ab73c093bfd` |
| `bundle/vinix-x86_64` | `393bd07c70bafe5c797e57010612df15ad23a4602593dfc368b56093f81f5181` |
| `bundle/blob-aarch64.c` | `107905a0b8415c0340b86ff45d94665f65e0ba2917e0390fd9f79887132b96a1` |

No GPU workload, hardware test, Vinix/QEMU boot, reboot, SSH or deployment occurred.
