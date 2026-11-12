# Wine PE loading under W^X, 2026-11-12

Source baseline: `1c80302ca15033d0f8a8276fa6cc015c68394ca7`, plus the maintained
source patch in the external evidence. This continues the
[private NLS checkpoint](wine-nls-check.md).

Fresh signed Win64 console execution and independent retention now pass on
native x86_64 and translated AArch64. The kernel, sandbox grants and bridge's
removal of `VINIX_ALLOW_WX` are unchanged. The native x86 probe also requires
successful RW-to-RX execution and refusal of both W+X allocation and protection
changes. These are local console results, not complete Wine catalog acceptance.

Wine 9.17's [PE mapping path](https://github.com/wine-mirror/wine/blob/wine-9.17/dlls/ntdll/unix/virtual.c)
initially allocates images and maps headers with write and execute access before
populating sections and applying their final protections. Native Vinix refuses
those initial mappings. The existing exact-input patch now composes:

- Three initial view flags change from `0x180002d` to `0x1800029`, removing
  execute during population while retaining read/write-copy and committed pages.
- The PE header mapping changes from Unix protection `7` to `3` (read/write).
- A 25-byte trampoline replays the two overwritten moves, restores only EXEC
  in the logical view's allocation-permission metadata, and returns to the
  existing section loader. This preserves later image-protection checks.
- The trampoline occupies verified zero padding at `0x61ba0`. Only the existing
  RX segment and `.fini` size extend to `0x61bb9`, before the R-only segment at
  `0x62000`. The original `.fini` entry and return remain intact. ELF permissions
  and file length do not change; disassembly confirms both branch destinations.

The original client pin remains
`0d2c95650eb6eff9e7a539d08cb118068b102d812cb505156d3525369dd1ec75`.
The whole input hash is checked before any instruction or ELF metadata is
changed. Instruction sites, segment/section sizes and unused padding have
additional exact checks. Layout admission independently derives the complete
expected runtime bytes from that original input. This is a narrow local binary
patch with incomplete corresponding-source evidence. No trampoline unwind
record is added; asynchronous unwinding and exception behavior at that site are
unqualified, as are general Windows W+X/JIT compatibility and graphical apps.

The strengthened V PE fixture uses the actual Windows memory-information type
through a C alias, with a 64-bit `VirtualQuery` binding. It requires read-only
image headers, RX DLL code, MEM_IMAGE identity, the original allocation-access
metadata and a successful RX image-protection request on both architectures.
Native x86 additionally writes `mov eax,42; ret` into an RW allocation, changes
it to RX and executes it, then requires W+X allocation and transition refusal.
Architecture selection is checked explicitly. The native observer and retainer
require the new exact markers; the retainer also enforces order and uniqueness.

`pe-01` retains a rejected `usize` binding attempt. `pe-02` builds the first
probe; the final `pe-03` rebuilds it with explicit evidence markers. All final
source/compiler/MinGW inventories match before and after compilation. Both
`prepared-*-01` builds, `native-*-01` runs and `retained-*-01` admissions pass.
The established prefix/socket, ordinary identity, outside-write refusal,
observed-process natural exit and lease checks remain required. Existing
Wine initialization warnings remain visible in serial output.

Normal, production and ASan/UBSan host builds pass exact byte composition,
immutable-input checks and 25 input refusals. Leak detection is disabled in the
sanitizer run; no retained-allocation claim is made. The x86 matrix passes all
49 refusal controls across eight shards, each with original and copied passing
baselines. Coverage verifies every unique assignment and baseline input hash.
New controls remove each protection marker and reseal an initial RWX mapping;
each refuses at its intended gate. The collection checker passes its synthetic
baseline/retry and nine refusal controls. The full ARM matrix was not rerun;
its fresh native result and independent retention pass with the new image test.

Raw evidence is retained at
`/Users/alex/.cache/vinix-wine-pe-wx-20261112`, including PE attempts, producer and
controller binaries, generated C, argv, prepared packages, boot images, logs,
full input/output inventories, independent receipts and all mutation trees.
The source baseline and patch accompany the workspace. The unchanged compiler,
MinGW, distribution, translator, sysroot/GCC and kernel trees remain preserved
in the [preceding complete pinned-input bundle](wine-forksafe-retention-check.md).
Keep both bundles. Original auditors still require their original complete
absolute namespaces; archived copies do not silently substitute missing inputs.
The [NLS bundle](wine-nls-check.md) separately retains the previous failed x86
run without rewriting its outcome. Hermetic builds, complete source offers,
publisher enrollment, detached-server lease coverage and release acceptance
remain open. Section 14 remains incomplete.

`wine-host-inputs.v NATIVE_RUN FRESH_OUTPUT` separately preserves selected host
compiler/linker, emulator, firmware and boot-loader bytes against the native
and producer input maps. Conflicting or missing bindings, changed files and
existing outputs refuse. It stores content-addressed bytes, original/resolved
paths, modes and original declaration/inventory snapshots, then rechecks the
sources. Both architectures pass (nine x86 and eight ARM inputs); an existing
output refuses. The initial native-only reader refused `llvm-readelf` before
creating output because that binding belongs to the producer map. Those logs
remain retained. Final captures, tool source and binary are in
`/Users/alex/.cache/vinix-wine-pe-wx-host-20261112`. This preserves selected
bytes; it does not qualify complete host library dependencies or authorize
historical input substitution.

Archives are under `/Users/alex/Library/Caches/vinix-codex/section14/`:

- `wine-pe-wx-20261112-01.tar.gz`: complete execution/control workspace.
- `wine-pe-wx-host-20261112-01.tar.gz`: selected host inputs and preservation tool.

Both archive tools returned 0 after comparing original and restored types,
modes, link targets, sizes and hashes. All original and restored root modes are
`0755`. Both original trees and the corresponding `*-restoration` trees are retained.

| Artifact | SHA-256 |
| --- | --- |
| Execution/control archive | `b930c3823399b65739cfdbf28a4f8d24aee05639b923d3e9efa05e8911c3081b` |
| Execution/control typed inventory | `34d1b7de509aa7264aef706b9f4c6d6d4e378c58ec25e155360409208c6987cf` |
| Host archive | `02ea255a4650f5de4f1a14761bd987e0d758056b188e714e4d43ed5a36557a4d` |
| Host typed inventory | `63bb39d8f01aa1a99d125111cf2cd424d5d08db68525e8fa67efec7d1b86cc2c` |
