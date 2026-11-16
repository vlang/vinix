# GEM-create size errors

Native GEM-create now matches the size errors in packaged
[Asahi checked_object_size](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gem.rs)
and its [ioctl validation order](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs).
Previously both malformed sizes reached the fallible GEM constructor and
returned ENOMEM.

| Request | Native result |
| --- | --- |
| Zero size | `EINVAL` |
| Size above `0xffffffffffffc000`, overflowing 16 KiB rounding | `EOVERFLOW` |
| Valid size with refused backing allocation | `ENOMEM` |
| VM-private request naming a missing VM, including an invalid size | `ENOENT` |
| Invalid native header/flags or non-private request with a VM ID | `EINVAL` |

A shared scalar `bo.create_size_error` checks zero and the maximum safe input.
Native validation runs after private-VM lookup and before either GEM constructor.
The existing file lock protects lookup through publication; the new error return
releases it through the existing defer. Successful requests retain constructor
rounding, private reservation identity and handle publication behavior. The fake
software backend uses the same size validator before allocation; its other
identity semantics are outside this change, and no fake guest runtime test ran.

Validation passed:

- ASan/UBSan with stack-use-after-return detection: 16,200 new ioctl cases
  across 200 cycles cover zero/overflow, the maximum safe size and adjacent
  boundary, 1-byte/16 KiB rounding boundaries, shared/private and writeback flags,
  header/VM precedence, allocator refusal and unchanged request outputs on error.
  Invalid sizes cause zero constructor calls; injected OOM causes exactly one.
  Every successful fixture object is removed and released exactly once, returning
  the live count to zero. Huge successful fixture objects contain metadata only;
  this does not qualify real physical-memory admission or accounting.
- Existing 12,800 SINGLE_PAGE, 32,800 BIND-order, 24,200 binding-VM, 9,400
  identity, 12,600 submit-order and 167,395 wait/syncobj cases pass. Async,
  retirement, private BO/PRIME, priority, VM geometry, repeated PTEs, wire/node
  and fence regressions also pass.
- Exact prior GpuFile bytes with the current fixture fail: zero size returns
  `ENOMEM` where the new assertion requires `EINVAL`. Raw source, the precise
  single-source adapter, executable and rejection are retained.
- 29 V source/contract test files plus the allocation-tool test file pass.
  Primary-source gates and mutation tests enforce error values, rounding bound,
  VM-before-size ordering and validation before allocation. The native ARM C
  storage checker passes all 100 live helpers and its negative selftest.
- Isolated ARM and clean x86 kernel builds from
  `54cef1d8d9968295a70caba6477bc1cce2e09f35` plus three overlays:
  `kernel/gpu/agx/bo/bo.v`, `kernel/gpu/agx/file/file.v` and
  `kernel/gpu/agx/fake/driver.v`. Both ELF/C pairs and exact inputs are retained;
  selected audited/support sources match the isolated inputs.

Source/native ARM C review confirms the helper has no allocations, references,
locks or interface boxes. Both callers retain the same constructor, allocation,
reference and adoption sites as the prior sealed C. The native early refusal
unlocks before returning. No native ownership/reclamation lifetime changed.
These checks do not measure native heap use or qualify multi-CPU execution.
The unchanged global allocation allowance audit **still fails** for isolated
baseline and feature, with identical per-file/kind counts: 383 ARM/289 x86 sites,
827/813 sources. No allowance or allocation rule was relaxed.

Local Omarchy/package clones were refreshed against remote heads, still
`4bf10ed28342b597009dcf573ffc0d70b94b31e3` and
`d727707b620c4e6c1c8de0f45c4a843475fa020e`. Reference pins remain Linux
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Selected gates pass; the full
audit remains `not_equivalent` (exit 1).

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-gem-size-20261116/`.
Canonical `bundle/` and a full archive restoration pass the unchanged complete
typed inventory checker. Sources/references, kernels/C, executable tests, negative
baseline and raw logs are retained. Diagnostics preserve initial allocation runs
that used an unrecognized root variable and the storage checker's native-signature
rejection; authoritative allocation runs select the two isolated worktrees with
`VINIX_KERNEL_ALLOCS_ROOT`, and the final checker requires the native `i64`
signature. `completion.txt` binds twelve source paths and two reports to the commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `a84309f89061176d592547e2e8d5556b4a0f6f84ad440e15a9c127cf378104be` |
| `bundle.tar.gz` | `26b5a4a774fabf8c65f43c92790cde208bbf40a1fa18ed08a2da6044473ac156` |
| `bundle/vinix-aarch64` | `015ab6812c6373fadb7af4fa8eb10c9465c14896ac6f11cf918c4b2e90df06e4` |
| `bundle/vinix-x86_64` | `c5576c52d757b11e07c7aca92c688bce55f85cf4d8db6649a4a727aae768df59` |

Overall Omarchy equivalence remains incomplete: modern ABI/Mesa integration,
mapping replacement/splitting, memory accounting, cumulative timelines, fence
containers, retained-queue destruction, reclamation and hardware qualification
remain open. No GPU execution, native hardware test, Vinix/QEMU boot, reboot,
SSH or deployment occurred.
