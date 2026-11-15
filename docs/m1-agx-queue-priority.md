# M1 G13 queue priority and failed-create ownership, 2026-11-15

Status: **incomplete driver parity**. The native G13 queue ioctl now matches
the packaged Asahi priority policy: LOW (0) selects firmware band 3, MEDIUM (1)
selects band 2, and HIGH/REALTIME are refused with EINVAL before allocation.
Previously userspace priority numbers were passed directly to firmware.
Existing pipe-specific defaults, including the compute override, remain in use.

Queue creation holds the file lock from VM lookup through resource construction
and owner publication. This keeps the borrowed VM/page table alive; Asahi uses
reference-counted VM clones for the corresponding lifetime. If failed firmware
invalidation quarantines a partially built queue, the file adopts that graph
before unlocking, even though no userspace queue ID is returned. VM destruction
returns EBUSY; file close retries cleanup before releasing the VM. Adopted IDs
remain reserved across wrap. The manager lookup compares exact VM pointers
under its lock and remains safe across shutdown.

Both GPU-construction failure branches now destroy and free their unpublished
logical WorkQueue. Successful logical/GPU queue metadata retention is unchanged;
this report does not qualify whole-kernel heap behavior or claim that retention
has been eliminated. G17 priority admission and credential/master policy are
outside this G13 increment.

Offline validation passed:

- ASan/UBSan runs the production queue ioctl and actual packed firmware
  priority builders for 600 LOW/MEDIUM render/compute/mixed queues. Unsupported
  priorities refuse before constructor calls or ID allocation. Host/GPU
  constructor failures, quarantined failed-create ownership, repeated close
  failure/retry, retained-ID reservation and VM destruction before the file
  lock pass. Prior mapping/private-BO/PRIME regressions also pass.
- Logical queues use actual heap allocations in the fixture, including the
  production failure-path free. Successful metadata is freed by fixture-only
  cleanup after final close; GPU resources use an injected bounded pool.
  These services establish host ownership and lock behavior, not firmware
  execution or actual invalidation delivery.
- Three V suites (seven test files), selected packaged-source/reference gates
  and all 39 live ARM generated-C helper checks pass. Strict negative storage
  selftests retain missing/duplicate/hidden-allocation rejection. The new
  retained-queue lookup has no temporary allocation or structural VM copy.
- Independent lifetime review approved lock order, failed-graph adoption,
  shutdown interleavings, orphan ID reservation and unpublished queue frees.
  Isolated ARM and clean ordinary x86 builds pass; ordinary x86 excludes AGX.

Build baseline: `fa53e8fe0ba212da363ca543060260b2e7b621f1`, plus three retained
kernel overlays (`drm/ioctl/ioctl.v`, `gpu/agx/file/file.v`, `gpu/agx/gpu/g13.v`).
All AGX/syncobj/GEM/ioctl V sources and generic `drm.v` match the isolated
checkout; overlays match both architecture inputs and the audited snapshot.
The sibling `completion.txt` binds all 13 non-report feature sources to the
commit and retains the committed reports separately.

Omarchy head `d76f364b41ccf01909b1d84ffcc6bd4fbb8cd91d` was rechecked. Fresh
package head `631b8696edc9b351e69cf0b16f2aba0804e1eaf5` still pins Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf` and Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`; m1n1 remains
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

Complete evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-queue-priority-20261115/`:
canonical `bundle/`, `inventory.json` and `bundle.tar.gz`. Complete extraction
and restored/canonical inventories pass the unchanged historical checker.
Earlier fixture compilation failures remain diagnostic logs, separate from
the final passing qualification.

| Artifact | SHA-256 |
| --- | --- |
| Inventory receipt | `63a7c656552ff25dcfd350422a3564a4bb64ffdffdfe31b852697823a3bda034` |
| Complete archive | `b1dfc71f5cb21542fe0a7da7be08b707994bd947e783c6e5e5fbb2d63a455e3b` |
| ARM ELF | `6e4d47c4db95c31b4e928ee418f201e3cde476fc978858a7c866dacf293f344b` |
| x86 ELF | `990724be03695ad38f3b7d15a0c8562b9edb250bf330cfc46dc0b700affbf852` |

The final audit still returns **not_equivalent** (expected exit 1). Modern
ABI/VM/GEM/Mesa integration, Linux reservation-fence/cache/accounting semantics
and other unverified driver behavior remain open. No native GPU execution,
whole-kernel heap measurement, Vinix boot, hardware test, reboot or deployment
was performed.
