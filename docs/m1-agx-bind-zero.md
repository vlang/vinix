# Zero-length BIND before BO lookup

Native zero-length BIND now returns EINVAL before taking the file lock or
looking up a BO, following packaged
[Asahi operation dispatch](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs).
Previously a missing BO could return ENOENT first. The shared early BIND guard
now requires a nonempty range, including SINGLE_PAGE. Legacy UNBIND_ALL keeps
its distinct zero-range encoding; empty UNBIND remains invalid.

Validation passed:

- 432,600 new ASan/UBSan ioctl cases check existing/missing BO and VM names,
  flags/SINGLE_PAGE, global/private addresses and offsets. Empty BIND performs
  no BO lookup and preserves request fields, mapping owners and PTE/flush counts.
  Nonempty BIND, SINGLE_PAGE and zero-encoded UNBIND_ALL controls pass, with all
  fixture BOs released after close. The pure VM fixture also rejects empty headers.
- An adapter substitutes the complete exact prior VM module, retaining raw
  baseline bytes and verified unchanged companion files. It builds and executes
  earlier regressions, then fails with ENOENT where empty BIND requires EINVAL.
- 35 V source/contract/allocation-tool test files, selected primary-source gates,
  the native ARM C storage checker for 108 helpers and its selftest pass.
  Removing the new scalar predicate from generated C reproduces the prior
  guard byte-for-byte. Native/fake BIND handler and shape/request/backing-size
  helper bodies are unchanged. No new allocation/free or retained-borrow lifetime
  is introduced.
- Earlier timestamp, GET_PARAMS, BIND/UNBIND/GEM/lifecycle/private-BO/identity/
  priority cases, 167,395 wait/syncobj checks and async, wire, fence, VM geometry
  and production PTE regressions pass. PTE tests explicitly use `--sanitize`;
  VM/lifecycle/PTE sanitizer linkage receipts are retained.
- Isolated ARM and clean x86 builds use
  `18a78d0058df22bf63ebffa58470cef5bb5294a9` plus one overlay,
  `kernel/gpu/agx/vm/vm.v`. Both ELF/C pairs and exact inputs are retained.
  Native AGX is ARM-only; x86 uses `LD_X86_64=ld.lld`.

The unchanged allocation allowance audits **still fail** for baseline and feature:
both complete logs are identical, with 383 ARM/289 x86 sites and 828/813 sources.
These compiler counts do not measure native heap rates. No allowance was changed.

Fresh remote heads are Omarchy `35672963760e99da12cd5fed73045904d4b69b94`
and packages `e09236d51c9c9735228a050f99823de48f1f9699`. Pins remain Linux
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. The full audit remains
`not_equivalent` (exit 1), while selected gates pass. The current remaining-VM
documentation now reflects the earlier idle replacement and range splitting.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-bind-zero-20261116/`.
Canonical `bundle/` and full archive restoration pass the unchanged complete
typed inventory checker. `completion.txt` binds eight source paths and two
reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `5706d8ebb719a4d2d0b38b0f40aadc82277ed8afef2843f588b4598cc9a43098` |
| `bundle.tar.gz` | `da1ff59f65c27cbd9488f1cd2f3328799e4bf3fd17ad5a203deeacacde3c9940` |
| `bundle/vinix-aarch64` | `0a7a4dba8f39b95bb961e6ebd93a252bfe430cc44a498703ed0ffc4d5d56b316` |
| `bundle/vinix-x86_64` | `580f84c4048c35b8854e17d40e08fc23863f34c5ad7c2f32050f22a1daf13306` |

Host services replace privileged mapping/firmware behavior. Native heap rates,
multi-CPU races and hardware execution remain unqualified. Modern ABI/Mesa,
batched/in-flight binding, reservation fences, accounting, cumulative timelines,
fence containers and reclamation still differ. The fake backend is unchanged
and no fake guest was executed. No GPU execution, native hardware test,
Vinix/QEMU boot, reboot, SSH or deployment occurred.
