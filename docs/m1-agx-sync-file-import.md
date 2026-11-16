# Binary sync-file import validation

Offline increment, 2026-11-16. Full M1 equivalence remains **incomplete**;
see [the parity report](m1-agx-parity.md).

The existing 16-byte, point-zero sync-file import now resolves the fence
descriptor before looking up the destination handle. An invalid or wrong-type
descriptor returns `EINVAL`, including when the destination is also missing.
A valid sync-file with no destination returns `ENOENT`. Successful imports
replace the destination fence without changing the request's handle. This
matches the selected binary path in the
[packaged Linux implementation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_syncobj.c).

The ordering also matters when another thread destroys or reuses the destination
while descriptor lookup is in progress. Import selects the current object at
the later handle lookup, or fails if the name has disappeared. The sync-file
snapshot remains valid after its final descriptor closes because fence metadata
is retained. Existing object/fence retention and allocation policy are unchanged.

Validation passed:

- ASan/UBSan with stack-use-after-return detection: 10,896 import cases. These
  cover invalid/wrong-type descriptor precedence, missing destinations,
  unchanged outputs/fence/timeline membership on error, shared publication
  through aliases, old GPU and first-publication captures, completed error
  identity, final transport close, destination reuse/removal during descriptor
  lookup, and 4,096 repeated imports without allocations or new handles.
- All 47,554 prior synchronization cases, 4,103 geometry probes and 200 capture
  primitive cycles. The unmodified importer from
  `4c0424a3818cecf91e9bd7a30cc1970d6e3b3093` passes those prior cases but is
  rejected by the new fixture: valid fd 1 and missing handle 0 produce `-22`
  instead of `-2`. The negative runner and exact baseline handler are retained.
- Async submission, DRM wire/node and fence sanitizer regressions, eighteen V
  test files, selected source/reference gates, and strict generated-C checks
  requiring all 71 live ARM helpers plus negative selftests.
- Isolated ARM and clean x86 builds from
  `15329dbf41d7ebc7fb9503e1268e47f8c2e41a78` plus one retained overlay,
  `kernel/drm/drm.v`. Selected source hashes match the private inputs. Both
  ELF/C pairs and the overlay were retained before switching architecture;
  x86 includes generic DRM, not AGX.
- Independent final source/ARM C lifetime review found no defect. The fence is
  copied before transport unref, the destination is resolved afterward, and
  its object pointer is copied before namespace unlock. Replacement publishes
  under the object lock without allocation or retirement.

The unchanged global allocation allowance audit **still fails** for baseline
and feature, with identical source and per-file/per-kind counts: 383 ARM and
289 x86 V-reported sites, across 822/808 sources. No auditor or allowances were
relaxed. Native heap/concurrency behavior is not qualified.

Fresh Omarchy `4bf10ed28342b597009dcf573ffc0d70b94b31e3` and packages
`4c0f2901ffb0de0689d6240f807cb43c3a269911` match checked remote heads.
Packages advanced during cloning; the checkout was updated and the final
source audit rerun, preserving the earlier audit as diagnostics. Pins remain
Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`, and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Selected gates pass; the overall
verdict remains `not_equivalent` (exit 1).

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-sync-file-import-20261116/`.
Canonical `bundle/` retains sources, references, executables, C, logs, review,
the baseline regression rejection and the unchanged complete typed inventory
checker. Canonical and fully restored archive inventories are verified.
`completion.txt` binds six non-report paths and two reports to the commit.

The first seal rejected a baseline-source comparison because its command helper
trimmed Git's trailing newline. Byte-preserving capture fixed the comparison;
the rejected `failed-source-copy/` and seal diagnostics remain retained. No inventory or
archive existed before that rejection, and no checker was relaxed.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `2d9d62ff0e6bb5558a0c79b1652cb7248a4989ef6b31d0b84fb49c7a3852f0a7` |
| `bundle.tar.gz` | `91fa5f7c857ebeac7a40eef6782d94f33a8aa1c4ee02c234fd17af3e6667ebf8` |
| `bundle/vinix-aarch64` | `e40ea4f70513d3aaeed449393c160c2901d254a55fe393d38d076f9567480e3d` |
| `bundle/vinix-x86_64` | `7685d140f6a52cc02fdfa7114de035dbc3016b5b3cb4942c77738f3c48951e73` |
| `failed-source-copy.inventory.json` | `652769542ac47d5d4051f8c82fd238c15e621d57f259a605a9950e8dbcc93cba` |

Export reservation/failure precedence, expanded point/flag ABI and matched
Mesa integration, timeline chains, other generic descriptor behavior,
indexing/locking performance, published metadata reclamation, callback waits,
cache/accounting and hardware behavior remain open. No Vinix boot, GPU/firmware
execution, hardware test, reboot, SSH or deployment occurred.
