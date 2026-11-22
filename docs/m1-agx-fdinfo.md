# Per-client GPU memory in /proc/<pid>/fdinfo

On G13 the packaged Asahi driver reports each client's GPU memory in
`/proc/<pid>/fdinfo/<fd>`, as Linux's DRM core prints it
([G13 reclaim scope](m1-agx-g13-reclaim-scope.md#accounting-totals-only-no-limits)).
Monitoring tools read these lines. Vinix had no `fdinfo` directory at all; it
now has one, with the DRM lines and the AGX totals.

## The generic lines

Every process and thread directory has `fdinfo`, listed and pruned like `fd`.
Each entry is made when the directory is looked at, and its text when it is
read. Reading needs the same inspection right as `maps`. The text starts with
Linux's four lines:

```
pos:	0
flags:	02400002
mnt_id:	2
ino:	9
```

`flags` is the open file's flags in octal, with `O_CLOEXEC` when the descriptor
has it and `O_LARGEFILE`, which Linux always sets on 64-bit, and without the
open-time `O_CREAT`, `O_EXCL`, `O_NOCTTY` and `O_TRUNC`. `mnt_id` is the mount
the file was opened through, as `/proc/<pid>/mountinfo` numbers it. Pipes,
sockets and other anonymous files were opened through no mount; Linux shows its
internal ones there, and Vinix shows 0.

The reader takes the descriptor without blocking under the process table, as
the `fd` scan does, and keeps the open file referenced while it formats the text
with both locks dropped. That reference also keeps a DRM file's driver state
open. It checks the inspection right again under the table lock, so a
process that execs something privileged after the first check is not shown.
Each open file reads one snapshot, as Linux's seq_file does, and an entry for
a descriptor closed since it was listed reads as `ENOENT`.

## The DRM lines

A DRM file adds what `drm_show_fdinfo()` and `drm_print_memory_stats()` print:

```
drm-driver:	asahi
drm-client-id:	3
drm-total-system:	48 MiB
drm-shared-system:	0
drm-resident-system:	48 MiB
```

Sizes take a KiB or MiB suffix only while they divide evenly, as in Linux. A
platform device has no `drm-pdev` line, and Vinix has no client names. An
`O_PATH` descriptor gets no DRM lines.

Vinix assigns each DRM data open an ID from a single atomic counter before
publishing its descriptor, following Linux's DRM file allocation. The ID
lives on the open file description, so dup and fork share it and fdinfo
reads only report it. [Pinned Linux client ID allocation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_file.c#L129-L147)

## What the AGX driver counts

Asahi counts each user object once, against the client that created it, in
`drm-total-system`. It adds the object to `drm-resident-system` once the GPU
holds its pages, which on G13 is from its first VM bind
([gem.rs](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gem.rs#L84-L114)).
The AGX driver now records the creating client on each object it creates, and a
client's total is the size of the objects in its handle table that it created.
Imports count for their creator only.

Two cases differ:

- Vinix allocates an object's backing when it is created, so its resident size
  always equals its total. Asahi reports a created but never bound object in
  the total only.
- Asahi keeps charging an object to its creator after the creator closes its
  handle while another client still holds it. Vinix drops it from the creator's
  total then.

The device-wide `gpu_memory` and `agx_stats` files are described in
[G13 statistics](m1-agx-stats.md).

## Validation

These results cover the original fdinfo implementation, which used an
address-keyed ID table.

- `tests/drm-fdinfo` runs the production formatting and numbering on the host
  under ASan/UBSan: size units, the G13 lines and the full key order, and client
  numbers. Mutants without the MiB cap, with resident before active, or that
  never forget a number fail it.
- `tests/drm-wire` checks that closing a description forgets its number; the
  never-forget mutant fails there too.
- `tests/agx-file-close` checks the AGX totals: created objects resident,
  imports left to their creator, closed handles dropped.
- `tests/procfs-fdinfo` boots both architectures in QEMU. It checks the generic
  lines, listing, closed descriptors and the DRM lines on the guest's
  framebuffer driver, then measures `/proc/slabinfo` around 200 cycles of each
  operation. Every heap class stays flat. Entries made and pruned every cycle
  are freed after the five-second removed-node grace period; measured at once,
  that phase shows 200 objects in four classes, the backlog the measurement is
  sensitive to. That phase warms up for as long as it measures, because the
  removed-node queue grows by two large pages to its high-water mark the first
  time.
- An independent lifetime review found no use-after-free, double release or
  leak. It found the missing locked inspection check, now added, and asked for
  `ENOENT` and snapshot reads, now done. Two differences remain: anyone may list
  `fdinfo`, as with `fd`, where Linux 6.0 and later require the inspection right
  for the listing too; and when the reader holds the last reference to a file
  closed meanwhile, the close runs at the end of its read, where Linux runs it
  on return to user space.
- The G13 failure, async, CPU-cache, native-error, `gem-private` and
  `drm-syncobj-wait` suites pass, as do 79 G13 contract test files and 122
  pinned reference checks. Both `PROD` kernels build and the allocation scan is
  unchanged.

Evidence is under
`/Users/alex/.local/state/vinix/omarchy-m1-fdinfo-20261119/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `f2f0de6a466ebc6631ead7cf6eba4adceba8f15d8b3151b5dd7c391bb16b8cff` |
| `bundle.tar.gz` inventory | `c173d750616d4d4cfd99f30f81afc7e0afd0e450debccea1568d8e3208481fc6` |

## Open-time client ID validation

The ARM64 and x86-64 QEMU guests opened two DRM descriptions and read
fdinfo in reverse. Both reported IDs `1 2` in open order. The same ARM64
guest binary reported `2 1` on the baseline. The updated kernels passed
the dup, fork, descriptor reuse and `O_PATH` checks. Descriptor installation
can fail after ID assignment and leave a gap in the counter.

Both kernels used `-O1` for C compilation and TCG for the guest runs.
The DRM fdinfo and wire sanitizer suites passed. The broad procfs probe
ran 200 cycles per phase and passed on both architectures, with peak
live-object growth of zero on ARM64 and one on x86-64. The allocation scan
reproduced the 150 baseline findings. The ID adds eight bytes to the open
description while keeping it in the 1536-byte slab class on both architectures.
Independent review confirmed that the ID is assigned before descriptor
publication and that closing the description requires no ID cleanup.
Native M1 validation remains open.

The tested base was `92535a8a9c2eeb778304da322fc607f1b25a683a` plus the
archived patches. Evidence is stored at
`/Users/alex/.local/state/vinix/m1-drm-client-ids-20261122.MCVKe0/`.
The `bundle.tar.gz` SHA-256 is
`2ede09358ed7ac01ee796f939a44e9c978da1fc98dcbfe5d1ef1db555cf93af4`.
