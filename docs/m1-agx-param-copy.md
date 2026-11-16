# Global GET_PARAMS copy behavior

Native and fake GET_PARAMS now follow the bounded-copy behavior in packaged
[Asahi GET_PARAMS](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs):
copy `min(request.size, supported size)` and leave every request field unchanged.
Zero-length queries accept null or invalid pointers. Previously both backends
rejected zero length and wrote the supported size back on success or EFAULT.
One shared checked-copy helper preserves ordinary partial-fault output; bytes
past the copied prefix stay untouched. Invalid headers still precede native
manager lookup, and a missing manager returns ENODEV before formatting/copying.

This matches copy semantics only. The existing response formatters, legacy ABI
and global data fields remain unchanged. Modern response contents/layout,
per-file `params_size` negotiation bookkeeping and crash/device-state checks
remain open. Native checked usercopy is unchanged; its zero-length behavior
and packaged Rust/C usercopy sources were inspected and retained.

Validation passed:

- 33,600 new ASan/UBSan ioctl cases cover zero/null queries, aligned/unaligned
  and oversized bounds, unchanged headers/tails, partial EFAULT prefixes and
  header/device precedence. The production handler/helper execute with injected
  formatting and usercopy, so this does not qualify real page faults or contents.
- Substituting the exact prior ioctl method now builds and fails the zero-length
  case with EFAULT. The baseline source, adapter, binary and rejection are retained.
- Existing lifecycle/BIND/UNBIND/GEM/private-BO/priority/identity regressions,
  167,395 wait/syncobj checks, async submission, wire/node, fence, VM geometry
  and production PTE cases pass. The PTE fixture explicitly uses `--sanitize`;
  sanitizer linkage receipts for it and the lifecycle fixture are retained.
- 33 V source/contract/allocation-tool test files, selected primary-source gates,
  and the strict native ARM C checker for 106 helpers plus its selftest pass.
  Native/fake response values remain stack locals; formatter C bodies match
  the prior bundle exactly. The new helper adds no direct allocation, lock,
  reference transfer or retained borrow. The fake backend is built/source-checked,
  with no fake GPU guest execution.
- Isolated ARM and clean x86 builds use
  `bffea693f7730eb887ee00fcdd310b355a609455` plus three overlays:
  native `file/file.v`, `fake/driver.v` and new `params/params.v` under
  `kernel/gpu/agx`. Both ELF/C pairs and exact inputs are retained. Final x86
  linking uses the repository-supported `LD_X86_64=ld.lld` override.

The unchanged allocation allowance audits **still fail** for baseline and feature,
with identical per-file/kind counts: 383 ARM/289 x86 V-reported sites. The ARM
source count grows 827 to 828; x86 excludes AGX and stays at 813. These are
compiler reports, not native heap-rate measurements. No allowance was changed.

Fresh remote heads are Omarchy `c2e2dd9ad90b5f12a241b2a369e0c58e2412ff05`
and packages `268cc49d44697cf0e7bb627727e3b73df93f4aa2`. Packaged Linux stays
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. The full audit remains
`not_equivalent` (exit 1); selected gates pass.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-param-copy-20261116/`.
Canonical `bundle/` and full archive restoration pass the unchanged complete
typed inventory checker. Initial fixed-array compilation, negative-adapter
import, default x86 linker and incorrect x86 source-count assumptions are retained
as diagnostics; final checks use the corrected tooling without relaxing allocation
or parity checks. `completion.txt` binds thirteen source paths and two reports
to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `4f9eea79c27914775fbd1209b02ca179c8837ea00c3102bf6ff82eb63ebbefa6` |
| `bundle.tar.gz` | `ca9c17d653bdd72c225966ce19c2fef8c21171fa10353c96276acc01604b72c2` |
| `bundle/vinix-aarch64` | `29ceba95dd67486fcd7614d664d637134be99a5b92463f1cfb99d6fa6352bf85` |
| `bundle/vinix-x86_64` | `b4684465251cacabf12ae101515e49f338286d3d787cad07ec062152d672cf7f` |

Overall parity remains incomplete: coordinated ABI/Mesa migration, batched binds,
reservation fences/in-flight mutation, memory accounting, cumulative timelines,
fence containers, retained-queue destruction, reclamation and hardware qualification
remain open. No GPU execution, Vinix/QEMU boot, reboot, SSH or deployment occurred.
