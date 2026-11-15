# M1 AGX VM-private buffer isolation, 2026-11-15

Status: **incomplete driver parity**. Vinix previously accepted `VM_PRIVATE`
without recording its owning VM or enforcing its binding/export restrictions.
Native private GEM objects now carry an immutable, non-reused VM identity,
matching the selected Asahi private-object isolation policy.

Creation holds the file lock across VM lookup and handle insertion. The GEM
constructor installs the identity before publishing its global handle. A
private object binds only into that original identity; a recreated VM with the
same numeric context ID is refused. Import, kernel timestamp binding and PRIME
export are refused. PRIME returns EINVAL and drops the exporter's temporary
reference through its matching custom/default put before creating an fd.
Owner CPU mmap authorization and ordinary shareable objects remain available.

The private global identity pool serializes allocation across managers and
context creation. It permanently exhausts at zero instead of wrapping. An
object retains a scalar identity, with no pointer to its former VM.

Offline validation passed:

- ASan/UBSan exercises real creation/bind/special-object/close and core PRIME
  refusal with injected GEM/VM/fd services. Owner, foreign and recreated VMs,
  CPU authorization, import/timestamp refusal, shared operation, invalid flags,
  private allocation failure and a create/destroy lock race pass. Four hundred
  PRIME refusals balance both custom and default puts. Prior 200 mapping
  retirement cycles and permission/shutdown/VM-destruction regressions pass.
- A separate sanitizer fixture executes the complete production GEM module.
  Two hundred private identities are correct at first global handle lookup;
  size alignment, references, backing release, invalid identity/size/OOM and
  normal/external defaults pass. The fixture explicitly frees normal metadata
  after final unref; the kernel's existing metadata-retention policy is unchanged
  and is not qualified by this backing/reference check.
- The production identity allocation wrapper and pure pool checks cover
  10,000 identities, the final two identities and permanent exhaustion.
  DRM wire sanitizer regression, three V suites (six test files), selected
  source/reference gates and all 38 live ARM helper/storage checks pass.
- Independent lifetime review approved scalar ownership, lookup locking,
  rejection cleanup and export reference balance. Isolated ARM and clean x86
  builds pass. Ordinary x86 excludes AGX but compiles generic DRM/GEM changes.

Build baseline: `4358ee9ce2fb8adac33dbf86e4d3ab1c01171802`, plus six retained
kernel overlays. All AGX, syncobj and GEM V inputs and generic `drm.v` match
the isolated checkout; overlays match both architecture inputs and the audited
snapshot. The sibling `completion.txt` binds all 28 non-report feature sources
to the commit; the committed reports are retained and hashed separately.

Omarchy head `d76f364b41ccf01909b1d84ffcc6bd4fbb8cd91d` was rechecked. Fresh
package head `b38d5bbd7c449536d55b27666123737d96bc43fa` still pins Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf` and Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`. The m1n1 reference remains
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Audit snapshots now include the
generic DRM/GEM sources used by the new policy gate.

Complete evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-private-bo-20261115/`:
canonical `bundle/`, `inventory.json` and `bundle.tar.gz`. Complete extraction
and restored/canonical inventories passed the unchanged historical checker.
Earlier fixture compilation/atomics failures and the preliminary strict
generated-C name rejection remain diagnostics. The final host atomics compare
scalar snapshots; the final checker requires the compiler's exact two new live
helper names and preserves its missing/duplicate/hidden-allocation rejections.

| Artifact | SHA-256 |
| --- | --- |
| Inventory receipt | `0ce1df4d0982b11cd6424bcd2d945a4ae39e8c46e24dda43bc0f553f9e5b15e6` |
| Complete archive | `31fb3f64b07d2e52f9733173507521a57b6d8e90194a378c49cf207a6f94c70f` |
| ARM ELF | `0f1f29c5d10b5552a8dab20a19b4b533b684aa193e70f2aab63b9906f2c4a151` |
| x86 ELF | `42d86100aca4bb2cc8d7f5b0aedff39439220f61082329d1ed0f26959642592b` |

The final audit still returns **not_equivalent** (expected exit 1). This adds
private-object isolation/export policy; Linux DMA reservation fences, complete
accounting/cache policy, modern ABI/VM/GEM/Mesa integration and other unverified
driver behavior remain open. No native GPU execution, whole-kernel heap
measurement, Vinix boot, hardware test, reboot or deployment was performed.
