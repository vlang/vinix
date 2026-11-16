# Opaque syncobj descriptor sharing

Offline increment, 2026-11-16. Full M1 equivalence remains **incomplete**;
see [the parity report](m1-agx-parity.md).

The existing 16-byte binary syncobj transport now accepts flags zero. Export
creates a CLOEXEC opaque descriptor, including for an empty object. Import
allocates a new handle in the caller's namespace for the same mutable object.
Repeated imports within a file and imports into other files share later fence
publication, SIGNAL, RESET and timeline state. This follows the selected
[packaged Linux object-sharing path](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_syncobj.c).
Sync-file descriptors continue to hold a snapshot of one fence; descriptor
type checks distinguish the two transports.

Namespace links now name objects independently. Creation embeds its first
entry in the retained object; each import owns one fallible link allocation.
The namespace lock protects insertion, lookup and removal. Lookup returns the
object identity, never a borrowed link. Destroy/file close detaches imported
links before freeing them outside the lock. Other names, exported descriptors
and captured identities survive removal and reuse. Published objects/fences
remain retained; this increment does not implement their reclamation. Indexing
still uses a linear list under one global lock rather than per-file xarrays.

Both opaque and sync-file exports allocate wrapper and interface-box storage
fallibly and preserve constructor/table errors. The file layer owns failure
release after handoff, fixing an existing sync-file failure path that could
free an already released wrapper. A raw pointer-slot store adopts the prepared
interface storage; direct pointer-to-interface casts caused hidden boxing in
an intermediate build and were rejected. Final generated C contains precisely
the two explicit allocations per export constructor and no hidden boxing.

Validation passed:

- ASan/UBSan with stack-use-after-return detection: 11,903 sharing cases,
  including empty export, repeated/cross-file imports, shared SIGNAL/RESET,
  stable sync-file and first-publication captures, type/pad/flag rejection,
  unchanged outputs on failure, both wrapper/box allocation failures, file
  construction and table failures, alias allocation failure, handle reuse,
  source close, duplicated descriptors, last-descriptor close during lookup,
  4,096 aliases and complete link retirement.
- All 35,651 prior synchronization cases, 4,103 geometry probes and 200 capture
  primitive cycles. Explicit fixture accounting returns all owned links,
  wrappers and boxes; fixture-only object/fence retirement follows consumers.
  Darwin leak sanitizer is unsupported and was not used for qualification.
- Async submission and DRM wire/node regressions, 800 fence completion cases
  with 4,000 callbacks, three V suites totaling eighteen test files, selected
  source/reference gates, and strict generated-C checks requiring 71 live ARM
  helpers with negative selftests. The host atomic fixture now returns the
  remaining-reference predicate correctly, using a value snapshot to avoid
  the host compiler comparing a generic mutable parameter's address.
- Isolated ARM and clean x86 builds from
  `f9736208db30d5bc35290ec9a601db6d4a20fede` plus three retained kernel overlays:
  `kernel/drm/drm.v`, `kernel/drm/syncobj/syncobj.v`, `kernel/drm/syncobj_fd.v`.
  Selected source hashes match the private inputs; both ELF/C pairs were
  retained before switching architecture. x86 includes generic DRM, not AGX.
- Independent final source/ARM C lifetime review found no defect in namespace
  traversal/retirement, interface adoption, descriptor lookup or export failure
  cleanup. Native CFLAGS disable strict aliasing for pointer-slot adoption.

The unchanged global allocation allowance audit **still fails** for baseline
and feature. V-reported sites decrease from 384 to 383 ARM and 290 to 289 x86;
the only per-file/per-kind delta is one fewer implicit heap struct allocation
in `drm/drm.v`. Each architecture gains one source file. Explicit fallible
allocations are checked separately in the actual C. No auditor or allowances
were relaxed; this is not a native heap/leak or concurrency qualification.

Fresh Omarchy `29fbc4e2de4e57525acc6195351e86a31773e158` and packages
`f7598ae6d7ea033e9fab9a33c837826bb6a54b33` match checked remote heads.
Pins remain Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`, and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Selected audit gates pass;
the full verdict remains `not_equivalent` (exit 1).

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-syncobj-sharing-20261116/`.
The complete canonical `bundle/` retains sources, references, generated C,
executables, logs, review and the unchanged typed inventory checker. Original
and fully restored archive inventories are verified. Intermediate compile,
boxing and fixture failures are retained as diagnostics. `completion.txt`
binds twenty-four non-report paths and two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `63bb424da0f31805c72758b09e12a19df98b13f0221950f95d8205f7e591cc37` |
| `bundle.tar.gz` | `51da31e8fba1ac82567cacd18cd0ff1c6d658814f5e102bf3b42ea26ec0bac4d` |
| `bundle/vinix-aarch64` | `ec6d83f50307ab860e1d08de7fe2d07dfd6b5fb2757ee1dde1db079171869f7f` |
| `bundle/vinix-x86_64` | `c4cd5724ed8868a34c8bae2d7c721874eca4e638c31a2d178c3e293f6ed7d799` |

Expanded point/flag ABI and matched Mesa integration, timeline chains,
sync-file error precedence, full-namespace exhaustion errno, other generic
descriptor semantics, indexing/locking performance, published reclamation,
callback waits, cache/accounting and hardware behavior remain open. No Vinix
boot, GPU/firmware execution, native heap/concurrency measurement, hardware
test, reboot, SSH or deployment occurred.
