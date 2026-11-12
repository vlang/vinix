# ARM translated shared-file page diagnostic, 2026-11-12

Source baseline: `235d1e3cd`, plus `wine-shared-pages-check.v` and
`wine-shared-pages/main.v`. This follows the passing
[native x86 graphical calculator](wine-gui-check.md) and its failed ARM attempt.

The unchanged retained ARM kernel uses 16 KiB pages. The exact fork-safe
x86 translator reports 4 KiB pages to its guest. A small V probe now measures
private and shared file mappings at both lengths, on native ARM and through
that translator. Both executables start as uid/gid 1000, with empty
supplementary groups; the translator starts ordinary before allocating its
JIT. No W+X environment waiver is present. This is not a pledge/unveil or
package launch test.

The fixture sizes each file to 64 KiB and replaces a 64 KiB-aligned portion
of a 128 KiB private reservation with `MAP_FIXED`. This isolates mapping
length from file EOF and address alignment. Atomic memory observations avoid
compiler reuse of earlier loads. Writable mappings check fork visibility,
private isolation and backing-file contents; read-only shared mappings check
whether subsequent `pwrite` updates are visible.

`run-03` passes all **twelve native/translated cases**:

| Case | Native ARM | Translated x86 |
| --- | --- | --- |
| 4 KiB private RW | Fork isolation | Fork isolation |
| 4 KiB shared RW | Coherent fork/backing bytes | Refused with `EINVAL` |
| 4 KiB shared R | Coherent file updates | Later file updates remain invisible |
| 16 KiB private RW | Fork isolation | Fork isolation |
| 16 KiB shared RW | Coherent fork/backing bytes | Coherent fork/backing bytes |
| 16 KiB shared R | Coherent file updates | Coherent file updates |

The expected translated 4 KiB limitations are diagnostic observations, not
successful support for those operations. The initial attempts failed during
V generation on a reserved identifier and conflicting/missing C bindings;
their sources and logs remain preserved. The final source builds real static
ARM and x86 ELF probes through the pinned V and explicit target Clang commands.
The controller binds selected executables/firmware, actual parsed V sources,
generated files and inputs before/after the guest. It retains literal commands
and an uninterrupted passing diagnostic outcome. It does not inventory the
complete C headers/libraries/compiler closure or claim a hermetic build.

[QEMU 9.1.2 `mmap_frag`](https://github.com/qemu/qemu/blob/v9.1.2/linux-user/mmap.c#L309)
rejects partial-host-page writable shared-file mappings. Its partial read-only
path copies file data into another mapping. This agrees with both measured
limitations. Wine's failed shared user-data view is 4 KiB; the diagnostic
isolates a concrete translator constraint consistent with that failure, not a
trace of every Wine syscall or a repaired ARM Wine runtime. A correct ARM
continuation needs coherent host-page-compatible shared views and fresh Wine
execution; allocation success alone does not establish shared-data semantics.

Raw evidence remains at
`/Users/alex/.cache/vinix-wine-shared-pages-20261112`, separate from the frozen
graphical evidence workspace. The exact selected translator SHA-256 is
`21bbd59fb9be632214a1c0fcc73624bf568ea525dd11762513a1faa0334eca83`.
The kernel identity, selected tool hashes, source lists and generated output
inventory remain in `run-03`. Original namespaces and the complete pinned
dependency bundle remain required. No kernel, Wine, translator or sandbox
policy change is introduced by this diagnostic. ARM graphical acceptance and
the remaining section 14 work stay open.

The diagnostic result SHA-256 is
`0d8ce26f721653573279b0a9232392e79d1e849f1d2ca57023926d0be49f4640`;
the verified selected-input inventory SHA-256 is
`3f6d91fb98aea2407acc39db3d227ad3ec93d694e475c631a5629425c7af9cfa`.
