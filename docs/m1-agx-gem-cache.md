# GEM WRITEBACK and CPU cache policy

Native AGX now honors `DRM_ASAHI_GEM_WRITEBACK`. The packaged Asahi
[GEM constructor](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gem.rs)
selects `map_wc` when WRITEBACK is absent. Previously Vinix accepted the flag
but used write-back CPU mappings for both cases. Default objects now use ARM
Normal Non-Cacheable backing and CPU aliases; WRITEBACK objects retain normal
write-back mapping. Existing non-AGX constructors retain their original policy.

The direct-map helper validates every existing writable physical leaf and the
active kernel TTBR1 before changing anything. It cleans and invalidates cached
backing using CTR_EL0 line geometry, then retypes each leaf with the existing
break-before-make/TLBI sequence. It does not allocate page tables. Preparation
refusal frees unpublished PMM backing before any mmap offset, metadata or
global handle publication. Final release removes the global handle, restores
write-back direct-map attributes and only then returns backing to the PMM.

Authorized device mappings and PRIME mappings use the same object's policy.
A device VMA must fit within one authorized BO: adjacent BOs with opposite
policies cannot share a VMA, which stores only one policy. Both device callbacks
resolve opaque Handle keys through the file registry. Existing Handle,
authorization and GPU references retain backing until user/shadow mappings and
acknowledged GPU mappings have retired. The independent lifetime review found
no remaining blocker after these callback, range and namespace-order fixes.
Owned GEM metadata retention and the borrowed global lookup API are unchanged.

Validation passed:

- ASan/UBSan executes actual GEM constructors/final release, BO methods,
  direct-map retagging, ARM BBM helper, cache-range loop and PRIME attribute
  method with recorded PMM/page-table/privileged primitives: 240 cache-line
  cases, 320 constructor/final-release cases and 24 refusal/default-policy
  cases. It checks all-leaf preflight, root identity, invalid/RO/wrong physical
  leaves, retained references, WB/NC aliases and WB restoration before reuse.
- The file-close fixture executes the actual ioctl and callbacks with distinct
  opaque keys, adjacent opposite-policy BOs in both orders, authorization after
  GEM_CLOSE, invalid spans and flag forwarding. Four complete-module negative
  variants compile and fail at the expected assertions: ignored WRITEBACK,
  skipped restoration, cross-object VMA acceptance and skipped cache cleaning.
- All 43 V test files, selected primary-source gates, 127 native storage guards
  and their allocation-mutation selftest pass. Wait, wire, fence, asynchronous
  retirement, close, VM, sanitized TLB, layout and render regressions pass.
  Fresh sanitizer checks also pass 12,000 work-command, 14,400 timestamp and
  48,000 start/finalize images.
- Fresh isolated ARM and x86 kernel builds pass. ARM ELF disassembly contains
  CTR_EL0 reads, DC CIVAC, DSB SY and the BBM TLBI instructions. The generated-C
  review confirms unchanged GEM metadata/refcount handling and unchanged G13
  command preparation, cleanup, reapers, publication and firmware converters,
  resolving only generated string identifiers to their exact literals.

Both baseline and changed allocation allowance checks still exit 1 at the same
381 ARM / 289 x86 sites, with identical per-file/per-kind counts. ARM source
count increases from 828 to 830; x86 remains 813. No allowance or historical
checker changed. These are compiler allocation-site checks, not native heap
measurements. Privileged cache behavior and physical coherence still require
hardware validation; host substitutes and emitted instructions cannot prove it.

Fresh heads are Omarchy `e25a57bf974b11a2a8fff17dc9e69cec4b689c6b` and packages
`c4f2ef76ce5d48a9c82ccba5d98b9a7ef7310fcb`. Pins remain Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. The complete fresh audit still
reports **not_equivalent** (exit 1); selected source gates pass. ABI and matching
Mesa migration, reservation fences, cumulative timelines, queue ownership,
initialization/topology and power/reset gaps remain. This is no 100% sign-off.

Source baseline: `cda5c36000f87cc7cde49aa3149c22eb275f74d3` plus the 29 source
paths retained in
`/Users/alex/.local/state/vinix/omarchy-m1-gem-cache-20261116/bundle/source/`.
The complete bundle retains both native C/ELFs, six overlays for each build,
reference inputs, source gates, test/runner binaries, negative sources and
failures, initial build failures, independent review and disassembly. Only
eight unchanged host runner binaries are reused with source/binary receipts;
native builds and the new/dependent fixtures are fresh. The original preceding
bundle and current canonical/restored bundles pass the unchanged typed
inventory checker. `completion.txt` binds the 29 sources and two reports to the
feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `93da02f75bf8c9ca581f96e8f7416735b6e3cc61af67276afdb386c0430826e2` |
| `bundle.tar.gz` | `a5914789bd06c60991b94f7911ca747be03c318f0251277941717d5ac9c72ab8` |
| `bundle/vinix-aarch64` | `ee90d0b5a9422a1bbbde141fca6f7cd490fa8f90856803bdbc0790690fe38b34` |
| `bundle/vinix-x86_64` | `01e4a54e665b01ed8aa3a4bf57594f23ca7c1928d34207358b6cd4672c41c305` |
| `bundle/blob-aarch64.c` | `3cf873cd02503ad8628ba0efe672def2488763b1bd8e065bf6293c79edfef687` |

No hardware test, GPU workload, Vinix/QEMU boot, reboot, SSH or deployment
occurred. The broader parity status remains [incomplete](m1-agx-parity.md).
