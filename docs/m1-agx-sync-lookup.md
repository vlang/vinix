# Submission syncobj lookup errors

Asahi submission staging now returns `ENOENT` for an absent syncobj handle in
either an input or output array. Previously Vinix returned `EINVAL` for both
absent objects and unusable input fences. This follows the packaged
[Rust syncobj lookup](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/rust/kernel/drm/syncobj.rs)
and its propagation through
[Asahi sync-item parsing](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs).

| Trigger | Staging result |
| --- | --- |
| Missing, deleted or foreign-owner handle | `ENOENT` |
| Existing empty binary input | `EINVAL` |
| Existing timeline input with no satisfying point | `EINVAL` |
| Existing empty output object | Accepted |
| Invalid item shape before lookup | `EINVAL` |
| Fault copying the affected item before lookup | `EFAULT` |

Every failure returns an empty staged aggregate. Earlier valid entries in an
array remain private staging; no output fence or GPU work is published.
The real submit ioctl propagates the error and releases its command storage.
Existing command-storage allocation still precedes sync lookup.

Validation passed:

- ASan/UBSan with stack-use-after-return detection: 18,600 new staging checks
  covering binary/timeline inputs and outputs, first/middle/last failures in
  64-entry arrays, copy/validation precedence, empty aggregates, unchanged
  output fences and released object locks. All 148,795 earlier checks pass.
- 800 new real submit-ioctl checks verify lookup errors, empty inputs,
  allocation precedence, returned request storage, unchanged result bytes and
  zero published jobs. Existing async, wire/node and fence regressions pass.
- The exact prior staging source passes earlier scenarios, then fails the new
  assertion with `-22` instead of `-2`. Its raw Git bytes, single-source runner
  adapter and rejection are retained.
- 25 V test files, selected reference/source gates, strict allocation checks
  for 94 live ARM C helpers and negative storage-checker selftests pass.
  The new source guard rejects collapsed error codes and dropped caller
  propagation; packaged `rust/kernel/drm/syncobj.rs` is required clean and
  retained as an audit input.
- Isolated ARM and clean x86 builds from
  `bfab7ab63a4abd10d67a5eb644a0f96f7e80079c` plus one overlay:
  `kernel/gpu/agx/submission/submission.v`. Both ELF/C pairs and exact overlays
  were retained before architecture switch. x86 excludes AGX. Selected audited
  and support sources match the private worktree inputs.

Native generated ARM C confirms stack arrays and a zero aggregate on failure,
with `ENOENT` only at missing-object lookup and `EINVAL` at missing input
fences. The production change adds no allocation, free or lifetime.
The unchanged global allocation allowance audit **still fails** for baseline
and changed source. Their complete logs are byte-identical: 383 ARM/289 x86
allocation sites and 827/813 sources. No allowance or historical checker changed.

Fresh Omarchy `4bf10ed28342b597009dcf573ffc0d70b94b31e3` and packages
`d727707b620c4e6c1c8de0f45c4a843475fa020e` match checked remote heads. Pins
remain Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Selected gates pass; the full
audit remains `not_equivalent` (exit 1).

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-sync-lookup-20261116/`.
Canonical `bundle/` and the fully restored archive pass the unchanged complete
typed inventory checker. Source/reference snapshots, kernels/C, executable
tests, raw logs and bounded C review are retained. Initial fixture compile and
checker-option failures remain in diagnostics. `completion.txt` binds ten
source paths and two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `1f0a5df381691602f83f40ddff0984fd18a30a1984be394218c8c689932556bd` |
| `bundle.tar.gz` | `3569763781b034f146a63e43745cb3aeab3c848324b778e2f1a17899dca56122` |
| `bundle/vinix-aarch64` | `7aa30027aee5222f585f66a07b4a166847d6ee8e1eb4d8b12e969eff30c03f96` |
| `bundle/vinix-x86_64` | `78908c73be2050201b9414f5bef74715ba4769c26bd4e3bc29703141c4a2a61b` |

This qualifies the lookup error distinction, not the complete parser or driver.
Merge/containers, cumulative chains, timeline waits, scheduler wrappers,
modern ABI/Mesa integration, indexing performance, reclamation and hardware
qualification remain open. Host fixtures do not measure native heap usage or
multi-CPU races. No Vinix/QEMU boot, GPU execution, hardware test, reboot, SSH
or deployment occurred.
