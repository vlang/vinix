# Bind VM lookup and global validation

Well-formed native BIND, UNBIND and UNBIND_ALL requests now return `ENOENT`
for a missing VM. Previously every absent VM returned `EINVAL`. Packaged
[Asahi bind/unbind lookups](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs)
also distinguish absent VMs with `ENOENT`.

The new pure `valid_bind_shape` helper validates current native operation
fields and global VA bounds before lookup. It calls the existing validator
with an empty reservation, which excludes no addresses. After finding the
VM under the mutation lock, the ioctl still checks its actual private
reservation and page table before borrowing a BO or changing PTEs.

| Request | Result |
| --- | --- |
| Invalid operation fields or global VA range | `EINVAL` before VM lookup |
| Valid shape, missing/removed/foreign-file VM | `ENOENT` |
| Found VM, private reservation overlap or missing page table | `EINVAL` |

Validation passed:

- ASan/UBSan with stack-use-after-return detection: 24,200 new binding checks
  cover all three native operations, missing/foreign-file and unsigned boundary
  IDs, eight malformed-field/range cases, deferred private-hole checks and
  invalid present VM state. Every refusal preserves the live mapping, two BO
  references, PTE/flush counts and neighboring VM. Final close retires the
  original mapping and object. The existing VM-destroy-before-BIND race now
  expects `ENOENT`, preserving its page-table/refcount checks.
- Pure VM shape, geometry and identity sanitizer checks pass. A new V runner
  imports the current modules directly from `kernel/` and retains its binary
  through `AGX_VM_TEST_BINARY`. The initial compile used the old launcher's
  obsolete `kernel/modules` path and failed before execution; its log is kept.
- All 167,395 wait/syncobj cases, 12,600 submit-order checks, 9,400 lifecycle
  checks and existing async/close/mapping/priority/PRIME/wire/node/fence
  regressions pass. These remain host checks with injected backend services.
- Exact prior GpuFile source with current fixtures fails the new assertion
  with `EINVAL` where `ENOENT` is required. Raw Git bytes, precise single-source
  adapter, sanitizer executable and rejection are retained.
- 28 V test files and selected reference/source gates pass. The new guard
  rejects missing shape validation, collapsed lookup errors, incorrect empty
  reservation arguments and lost locked private-window validation. The expanded
  strict ARM C checker covers 96 live helpers; negative selftests pass.
- Isolated ARM and clean x86 builds from
  `6b16a2bd8f251b332fd138a27c23d287647d91e5` plus two overlays:
  `kernel/gpu/agx/file/file.v` and `kernel/gpu/agx/vm/vm.v`. Both ELF/C pairs
  and exact overlays were retained before switching architectures. x86 excludes
  AGX. Selected audited/support sources match the isolated inputs.

Bounded ARM C review confirms global validation before locking and the same
deferred VM-lock release. Shape/request/user-range validators allocate or free
nothing; ioctl allocation/free, BO get_ref/unref and container-mutation token
counts match prior C. No native lifetime or owner was added. The unchanged
global allocation allowance audit **still fails** for baseline and feature:
identical per-file/kind counts, 383 ARM/289 x86 sites and 827/813 sources.

Local Omarchy/package clones were refreshed against GitHub remote heads,
still `4bf10ed28342b597009dcf573ffc0d70b94b31e3` and
`d727707b620c4e6c1c8de0f45c4a843475fa020e`. Pins remain Linux
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Selected gates pass; the full
audit remains `not_equivalent` (exit 1).

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-bind-vm-lookup-20261116/`.
Canonical `bundle/` and a fully restored archive pass the unchanged complete
typed inventory checker. Sources/references, kernels/C, executable tests,
negative baseline, raw logs and bounded C review are retained, including
initial tooling diagnostics. `completion.txt` binds thirteen source paths and
two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `ac159456bc33cd976a013d2a2c3012332c912d6ca1b14022999ebf2f199b5ab8` |
| `bundle.tar.gz` | `84880360853ff48070aa25a98fb4545483f98343e5e250872b6c8438da5a10af` |
| `bundle/vinix-aarch64` | `292a441fe7d987496be2f1e77e82d4a6faeb1c1f5a75493fe20ac2739a4fa79b` |
| `bundle/vinix-x86_64` | `d495d4c6519ed17e08637caa2c5e229c0f122f34af7abf3e8301e48832f3f0c4` |

This qualifies the current native request/VM distinction. Native binding still
looks up the VM before the BO; packaged BIND looks up the BO earlier, so complete
combined-failure precedence remains open. UNBIND_ALL keeps the native legacy
contract; modern bind batching/ABI formats differ. Modern ABI/Mesa integration,
cumulative timelines, fence containers, retained-queue destroy semantics,
reclamation and hardware qualification remain open. No native heap/multi-CPU
qualification, Vinix/QEMU boot, GPU execution, hardware test, reboot, SSH or
deployment occurred.
