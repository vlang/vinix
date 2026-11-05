# Full V observer adapter host qualification

Both maintained architecture adapters now generate the complete V slab observer
through `perfproducer` and retain its generated V, legacy and combined C files.
The legacy operation probes remain byte-identical. The full snapshot schema,
strict observer target links and allocation-free parser review are qualified
separately in [`heap-qualification.md`](heap-qualification.md).

The x86 adapter now requires an explicitly selected canonical Clang executable,
sysroot, GCC support tree and literal `ld.lld` alias. Its init and measure links
use `--no-default-config`, the explicit x86_64-musl target, `-nostdinc/-nostdlib`,
named musl/GCC headers, CRT objects and libraries, and strict pointer/format
diagnostics. This avoids the retained GCC refusal for the unchanged legacy
`scanf` source without suppressing warnings. Init generation keeps no collector,
backtrace or native signal handler, adds `-nocache`, and uses `-O2` for both
fresh paired images. ELF admission requires the expected machine and no
interpreter or shared-library dependency. Complete literal sysroot/GCC manifests
are retained and checked before and after execution. The owner selects and
inventories those directories through its typed preparation profile.

The source base is `96c472840`, the local integration of validated observer
component `353b2914855abba27a0c9bfbb9970e3cbaf7d789`. Source hashes:

| Source | SHA256 |
| --- | --- |
| `run-x86.v` | `d0f582e95d39091e36e3a816f4e594e8a97682a8b6e309707b57d5e82e09ef72` |
| `run-arm.v` | `07373463f469231e0714bf8f23806336316721b27c78d474db7fe9f38e351308` |
| `foreground-supervise.v` | `413a2e8b540169cbcf6a7728105b38044260d5548722cfb40f2d5c4ec523eb1d` |

On 2026-11-05 the source-bound owner rebuilt both adapters in normal and
production modes using the independently qualified compiler `v-next`, SHA256
`53debcfe66952ba952d64b2b94dbb2408bed6992453d1ac6bad5889e4bd1ec7e`.
Each x86 executable passed all 37 selfchecks, including 22 refusals, and all
18 independent-clone controls. The five new cases check exact strict link argv,
canonical tool selection and exact alias/missing-directory/driver refusals.
Each ARM executable passed all 18 controls. Independent source/ABI review passed.

Both complete before/after input maps matched independently, SHA256
`b449d762ae7907a2d01b8377d05c9d271431bd3a29ee05d47c14b5226bb67206`.
The maps cover the complete selected compiler, maintained source trees and
recorded host compiler/SDK metadata. The host SDK/loader closure is not hermetic.
Actual outer exits were zero, with the exact final qualification markers.
All code remained frozen through both comparisons; this report was added later.

Raw evidence remains outside Git at
`/Users/alex/Library/Caches/vinix-codex/section14/perf-runtime-host-20261105-01`:

| Artifact | SHA256 |
| --- | --- |
| `adapter-x86-01/qualification.json` | `364a105c9276187e1ee73fa048164a9f9f6f4e695efb47b90f84449666ad5b66` |
| `adapter-arm-01/qualification.json` | `4ee461b5c953ed4ee3f540ead236c2ea6b672215385416b46139bd08c2596819` |
| x86 production executable | `3d4da77977e0eb3cb3fc6bee6f1d49f4edf72807403d8657764c2787ee03718d` |
| ARM production executable | `1664797a97799c3e76397931d572431c719bc0b037c6fb1c56302f0e0593b6db` |

The whole host directory has not been sealed. Qualification used private
compiler cache/module/temp directories, coherent cleared compiler environments,
300-second outer bounds and the existing bounded process/budget owner. Fresh
admission and endpoint observations kept the shared worktree and complete host
state below the 512 MiB allocated/apparent allowance and above the 2 GiB
admission/1 GiB continuation free-space floors.

These are host adapter checks. New init target links, complete original-kernel
audits, actual image preparation, guest measurements and current-main kernel
integration remain separate gates. No native memory/performance pass is claimed.
