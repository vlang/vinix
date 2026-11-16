# BIND buffer lookup before VM validation

Native BIND now follows packaged
[Asahi's lookup/validation order](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs)
for the currently supported fields: alignment and flag bits, BO identity/size,
global range and permissions, VM identity, then private reservation checks.
Previously the native VM and private window were checked before the BO.

| Combined failure | Result |
| --- | --- |
| Bad alignment/unknown flag bits and missing BO | `EINVAL` |
| Missing BO and bad global range/zero permissions/missing VM/private hole | `ENOENT` |
| Found BO with invalid size/global range/permissions and missing VM | `EINVAL` |
| Valid BO/range/permissions and missing VM | `ENOENT` |
| Found VM with private-hole or VM-private BO mismatch | `EINVAL` |

The new pure `valid_bind_header` permits zero permissions and globally invalid
but aligned ranges through the early phase; they remain rejected after BO
lookup. Valid mapping admission is unchanged. The file mutation lock stabilizes
both lookups. UNBIND and legacy UNBIND_ALL keep their previous ordering.

The temporary BO reference now spans VM lookup. All eight BIND failures after
acquisition release it once before deferred unlock. Mapping insertion transfers
that same reference; failed invalidation retains it in a retiring mapping.
Independent source and retained ARM C lifetime review approved these paths,
including UNBIND/UNBIND_ALL ownership and release only after invalidation.
The reviewer confirmed stack lookup temporaries and an allocation-free header.
The exact approved source/C hashes are retained in `independent-review.txt`.

Validation passed:

- ASan/UBSan with stack-use-after-return detection: 32,800 new ordering checks
  combine missing/zero/large BO and VM IDs with header, bounds, permission and
  private-window failures. Every refusal returns the temporary reference and
  preserves live mapping/PTE/flush state. Final close returns the object count
  to zero. Existing map/flush failure and private-object cases still pass.
- Earlier 24,200 binding checks, 9,400 lifecycle checks, 12,600 submit-order
  checks, all 167,395 wait/syncobj cases and async/close/mapping/priority/PRIME/
  wire/node/fence regressions pass. Pure VM header/shape/geometry/identity
  sanitizer checks also pass.
- Exact prior GpuFile source with current fixtures fails the new assertion:
  `EINVAL` where a missing BO requires `ENOENT`. Raw source, precise
  single-source adapter, executable and rejection are retained.
- 28 V test files and selected reference/source gates pass. Ordering guards
  require BO-before-VM, temporary-owner cleanup and retained mutation locking;
  mutation tests reject early VM lookup, missing cleanup and early permission
  rejection. The expanded strict ARM C checker covers 97 live helpers and
  negative selftests pass. The existing private-BO guard remains unchanged.
- Isolated ARM and clean x86 builds from
  `7920338370f3fb85ec1e4a9ab85b1e16bc2ca6d2` plus two overlays,
  `kernel/gpu/agx/file/file.v` and `kernel/gpu/agx/vm/vm.v`. Both ELF/C pairs
  and exact inputs were retained before switching architectures. x86 excludes
  AGX. Selected audited/support sources match the isolated inputs.

Native C has no new allocation sites; BIND's get_ref count is unchanged and
three extra explicit unref sites cover new post-lookup errors. The unchanged
global allocation allowance audit **still fails** for baseline and feature,
with identical per-file/kind counts: 383 ARM/289 x86 sites and 827/813 sources.
Host refcount measurements and source/C review do not measure native heap use
or qualify multi-CPU races.

Local Omarchy/package clones were refreshed against GitHub remote heads,
still `4bf10ed28342b597009dcf573ffc0d70b94b31e3` and
`d727707b620c4e6c1c8de0f45c4a843475fa020e`. Pins remain Linux
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Selected gates pass; the full
audit remains `not_equivalent` (exit 1).

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-bind-bo-order-20261116/`.
Canonical `bundle/` and fully restored archive pass the unchanged complete typed
inventory checker. Sources/references, kernels/C, executable tests, negative
baseline, raw logs and independent review are retained. The initial combined
private/window condition passed runtime checks but failed the old private-BO
source guard; it was split into explicit checks, with the initial source,
executable and rejection preserved. Final evidence uses `close-final.log` and
`close-test-final`. `completion.txt` binds eleven source paths and two reports
to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `c3f56fd468883cc0958a0befccdd598265fc7bd29d4a5fd7f035bb82263c7ec3` |
| `bundle.tar.gz` | `20746abc5848deb5b6c875e7df676c57e8378ccb96d78be46675dc747ba1d64f` |
| `bundle/vinix-aarch64` | `0e359c1dfb0f0c93440e26bea705231b18ca51203ecc4fc2f23c0e04ee38dd53` |
| `bundle/vinix-x86_64` | `a1df77dffac5290ce04fd80deb0eaedb1ffd637b215fda74ea28dbfedee58a9c` |

This qualifies ordering for native supported fields, not the entire packaged
binding ABI. SINGLE_PAGE, modern bind batching/formats, mapping replacement/
splitting, complete memory accounting, Mesa integration, cumulative timelines,
fence containers, retained-queue destroy semantics, reclamation and hardware
qualification remain open. No Vinix/QEMU boot, GPU execution, hardware test,
reboot, SSH or deployment occurred.
