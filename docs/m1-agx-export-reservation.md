# Descriptor reservation during syncobj export

Sync-file export now reserves a descriptor number before looking up its source
and constructing the private wrapper. Opaque export resolves its object first,
then reserves before construction. This follows the packaged
[Linux DRM implementation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_syncobj.c).
Outputs remain unchanged on failure; failed construction returns the reserved
number for reuse.

| Trigger | Sync-file export | Opaque export |
| --- | --- | --- |
| Missing source, number available | `ENOENT` | `EINVAL` |
| Valid empty object | `EINVAL` | Exports the mutable object |
| Full table, valid source | `EMFILE` | `EMFILE` |
| Full table, missing source | `EMFILE` | `EINVAL` |
| Private creation OOM after reservation | `EINVAL` | `ENOMEM` |

Flags/padding validation precedes reservation. A full table wins over
sync-file source lookup and private allocation failures. Linux maps a null
`sync_file_create` result to `EINVAL`; three existing private-creation failure
expectations were corrected accordingly. The public sync-file constructor
retains its ordinary installation path for virtio callers.

Reservations occupy numbers without installing a descriptor pointer, matching
the observable distinction in
[Linux's descriptor table](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/fs/file.c).
They remain invisible to lookup, close, `/proc` and fork's installed-FD snapshot.
Ordinary creators and pairs skip them; specific duplication to a reserved
number returns `EBUSY`. An owned reservation can still install after its limit
is lowered. Installation removes and clears borrowed links before publishing
the FD under the table lock. Failure cleanup releases the FD after unlocking.

Each caller supplies a stable node and defers cancellation. Nodes allocate no
storage; the existing table-growth helper is used when capacity is needed.
The Process head adds metadata whose native slab cost was not measured.
Independent source and retained ARM C review found no unresolved lifetime or
locking issue for current DRM callers. Both reservation locals remain stack
values; all reachable exits after successful reservation cancel them. Fork
uses fresh Process objects, and exec/exit wait for kernel siblings to unwind.
Future explicit-process callers must retain their target and exclusively own
their reservation node through installation/cancellation.

Validation passed:

- ASan/UBSan with stack-use-after-return detection: 15,800 reservation checks
  and 10,600 export checks. These cover invisible slots, all unlink positions,
  node reuse, competing create/specific-dup/pair selection, growth failure,
  exhaustion, lowered limits, branch-specific source errors, full-table/OOM
  precedence, unchanged outputs, failed adoption and complete owner/slot recovery.
- All 122,395 earlier scenarios pass with the corrected private sync-file
  creation errors. The runner executes native reservation and number-creation
  functions against a Process table fixture. Table growth/budget failure is
  modeled. Primitive descriptions are borrowed stack test values, explicitly
  removed before scope exit; DRM cases use real fixture wrapper/box/FD owners.
- Two negative baselines: the exact prior DRM source fails the corrected
  private-creation error assertion; the prior descriptor-create functions pass
  earlier scenarios, then select reserved slot zero where slot eight is required.
  Original sources, precise single-source adapters and failures are retained.
- Async, DRM wire/node and fence sanitizer regressions, 24 V test files,
  selected reference/source gates, strict checks for 94 live ARM C helpers and
  negative allocation selftests.
- Isolated ARM and clean x86 kernel builds from
  `cea71a192c87f706ab0430808f2241d55c0dc1b3` plus five overlays: DRM dispatch,
  opaque transport, file table, reservation helpers and Process definition.
  ELF/C pairs and overlays were retained before architecture switch; x86
  excludes AGX. Selected sources and reviewed support match the private inputs.

The unchanged global allocation allowance audit **still fails** for baseline
and feature: identical per-file/per-kind counts, 383 ARM/289 x86 sites. One new
source gives 827/813 sources versus 826/812. No auditor or allowance changed.
This does not measure native heap use, leaks, multi-CPU or fork/exec races.

Fresh Omarchy `4bf10ed28342b597009dcf573ffc0d70b94b31e3` and packages
`d727707b620c4e6c1c8de0f45c4a843475fa020e` match checked remote heads. Pins
remain Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`, and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Exact `fs/file.c` is now required
clean and retained; native reservation/file/Process sources are selected audit
inputs. Selected gates pass; the full verdict remains `not_equivalent` (exit 1).

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-export-reservation-20261116/`.
The canonical `bundle/` and fully restored archive pass the unchanged complete
typed inventory checker. Sources/references, kernels/C, executable tests, raw
logs and independent review are retained. `completion.txt` binds nineteen source
paths and two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `64494c7c30c87e7f021a08d899e12766640282969e37b2da5b091d95a5024312` |
| `bundle.tar.gz` | `e5ff63e0becd84f65a008a269fbb41ff75bd6db65ebf547fd3d0c64832da6419` |
| `bundle/vinix-aarch64` | `c26b44b92f13f99c89f14eb2a095d72a47f4023abc58f276f652de6c6630ecf9` |
| `bundle/vinix-x86_64` | `5fec8b87c13f36b3d79a4f66f1023089116bf8188f5c76e62a716b209086df91` |

Merge/containers, cumulative chains, timeline waits, scheduler wrappers,
modern ABI/Mesa integration, indexing performance, reclamation and hardware
qualification remain open. No Vinix boot, GPU/firmware execution, hardware test,
reboot, SSH or deployment occurred.
