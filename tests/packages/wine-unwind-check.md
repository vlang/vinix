# Wine trampoline unwind metadata, 2026-11-12

Source baseline: `9b706a845e37af1546fd1de9031eb08c9dc12351`, plus the tracked
working-tree patch and explicit new-source snapshots in the external bundle.
This continues [PE loading under W^X](wine-pe-wx-check.md). The preceding
trampoline had no frame descriptor. This change adds its metadata without
changing the existing loader instructions, sandbox grants or kernel policy.

The same exact original ntdll input pin remains required. After the existing
prefix/image patches, `wineadapter/unwind.v` adds a read-only ELF LOAD segment.
It relocates both original notes intact, retains their NOTE/GNU_PROPERTY
headers, and uses the vacated note storage for the twelfth program header.
Program headers remain inside the first ELF page. The original executable code,
ordinary data/globals, relocation targets and existing LOAD addresses remain unchanged; the new R-only
segment starts above the original BSS. No W+X segment is introduced.

The original CIE, all **701 original FDEs** and their index entries are retained.
Only their relative initial-PC/index encodings change when the frame sections
move. Every CFI instruction and expression byte and every original function
range remains identical. A 702nd FDE covers `0x61ba0..0x61bb9`, with constant
`CFA=RSP+4368`, RIP at CFA-8, and saved R15/R14/R13/R12/RBP/RBX at CFA-16 through
CFA-56. The GNU frame header and both section headers point to the new metadata.
LLVM's independent frame and note decoders agree on those records and both
unchanged note payloads. File size grows from `0x82cd0` to `0x8f58c`.

The independent V checker compares all original frame/index identities and
program bytes, validates segment and note relocation, decodes the new CFA and
register rules, and rejects 33 metadata corruptions. It passes normal,
production and ASan/UBSan builds. The existing exact runtime-composition checker
also passes normal, production and sanitizer builds with 25 input refusals;
all original bytes outside the separately checked metadata fields still match
the specified image/prefix patches. Sanitizer leak detection is disabled;
no retained-allocation claim is made.

`wine-unwind-target.v` provides an additional **actual GCC unwinder** check in
an ordinary x86_64 Vinix guest. It maps an instrumented private copy, enters the
real hook/trampoline branches with the compiler's stack layout, and invokes
`_Unwind_Backtrace` from the trampoline. The caller saves six sentinel values;
the callee replaces the live registers with different values. GCC must recover
the actual caller PC and all six original values through the new FDE. The old
metadata fails to reach that caller. Exact `_Unwind_Find_FDE` identity and
post-deregistration absence are checked. Registration ends before unmapping,
and the final marker is printed after deferred cleanup.

This fixture's code generator and test logic are V; `libgcc.h` only declares
foreign ABI entry points. The final callback uses GCC's actual context and
reason-code types through V bindings, without a callback cast shim. The
controller binds its embedded sources, compares discovered/built V closures,
records C/argv/output hashes and checks selected inputs after execution. It
pins the actual libgcc archives/header, compiler, tools, kernel and boot inputs;
this additional target check does not admit a complete host-tool dependency
closure. It exercises an instrumented copy and GCC's registration interface,
not asynchronous delivery through Wine's actual signal/exception paths.

`target-01` retains an image-builder dispatch failure; no guest started.
`target-02` passes the initial frame recovery test. `target-03` retains a
strict C pointer-type refusal while adding retirement checks. `target-04`
passes frame recovery, the missing-FDE control, exact lookup and retirement.
`target-05` repeats those checks with the controller's explicit production
source-binding requirement and exact unique marker check. A non-production
controller refuses before creating output. Final `target-06` uses the exact
typed callback ABI without the earlier cast shim.
Earlier compiler experiments and the relevant intermediate sources remain
retained. Their failed outcomes are not rewritten as successes.

Fresh prepared runtime construction, signed Win64 execution and independent
retention pass on **both x86_64 and AArch64**, using the existing real `pe-03`
receipt against its original complete compiler/MinGW inventories. Native x86
still requires RW-to-RX execution and W+X refusal. The full x86 evidence matrix
passes **51 refusals** across eight shards, including resealed omission of the
new index entry and a resealed one-byte CFA change. Complete unique assignment
and unchanged baseline inputs are rechecked; each shard admits original and
copied baselines. The collection checker's baseline/retry and nine refusals
also pass. The full ARM evidence matrix was not rerun.

Raw evidence is retained at
`/Users/alex/.cache/vinix-wine-unwind-20261112`. It includes both native runs and
receipts, all metadata/target controls and failed attempts, generated C, literal
argv, images, full Wine input/output inventories and source snapshots. Nine
x86 and eight ARM selected host-tool/firmware inputs are copied against their
recorded hashes. Complete unchanged compiler, MinGW, distribution, translator,
sysroot/GCC (including libgcc) and kernel trees remain in the
[preceding pinned-input bundle](wine-forksafe-retention-check.md). Keep both
bundles. Historical auditors still require their original complete absolute
namespaces; these copies do not silently replace missing inputs.

The complete workspace is also preserved at
`/Users/alex/Library/Caches/vinix-codex/section14/wine-unwind-20261112-01.tar.gz`.
Archive SHA-256:
`65366dfed39d072d91ced4a0757eb403cfed174e0976d98c8fca049def686791`.
Its adjacent `.inventory.txt` SHA-256 is
`b87f494935cf1a55894898d0c1c80300e35c3ae589a45229297f424ace0b9663`.
The archive tool exited successfully after restoring and comparing all types,
modes, links, sizes and hashes; original and restored root modes are both 755.
The archived report predates this checksum paragraph to avoid a recursive hash.

Graphical Wine, broad exception/signal compatibility, complete corresponding
source and publisher/release acceptance remain open. Detached-server lease
supervision still has the [separate kernel prerequisites](wine-lease-supervision-plan.md).
This checkpoint neither implements that supervisor nor treats a user-space
waiter as a qualified descendant-retirement barrier. Section 14 remains open.
