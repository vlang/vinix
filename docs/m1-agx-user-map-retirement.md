# M1 AGX user mapping retirement, 2026-11-15

Status: **incomplete driver parity**. The comparison found that Vinix released
a mapping's GEM reference even when firmware invalidation failed. A failed
BIND could expose backing before returning EIO, and UNBIND, UNBIND_ALL and
closed-handle cleanup could free backing while firmware retained a translation.
The packaged Asahi implementation retains GEM ownership through deferred/error
cleanup; this fix brings Vinix's selected ownership paths closer to that rule.

Mappings now retain their existing object reference after invalidation failure.
A retiring record reserves its VA and records that its PTEs have already been
removed. Retry invalidates the range without unmapping twice; only successful
invalidation or completed firmware shutdown permits deletion and one unref.
File close keeps the VM alive until every mapping can retire. New submit ioctls
retry pending cleanup before preparing jobs or replacing output fences.

Independent review found two related races, both fixed before qualification:
the manager sets `stopped` before halting firmware, so file flushes now acquire
the manager lock before checking that state or accessing transport. The lock
remains held until shutdown completes. BIND still fails on a stopped manager.
VM/page-table and GEM lookup now remain under the file mutation lock, preventing
a concurrent VM destroy from invalidating BIND's borrowed page table.

Offline validation passed:

- ASan/UBSan exercises the production mapping ioctls, retirement, GEM-close,
  VM-destroy and file-close paths with the real BO table and VM validation.
  Two hundred repeated failure/retry cycles return dynamically allocated GEM
  objects to zero. Failed binds, partial UNBIND_ALL, busy VM pins, replacement
  refusal, one-time unmap and successful/stopped cleanup pass.
- Deterministic scheduling at the exact manager/file lock checks shutdown
  overlap, refusal of a racing stopped bind, and VM destruction before BIND
  acquires its mutation lock. Page-table and firmware services are injected;
  these checks do not execute actual firmware or measure hardware races.
- The real-ioctl async fixture injects mapping cleanup refusal and verifies
  no prepared/pending ownership or staging allocation remains, original input
  and output fences remain intact, and retry completes. Existing scheduling,
  backlog, failure and shutdown sanitizer regressions pass.
- Selected source/reference gates, three V unit suites (four test files),
  strict generated-C negative tests and all 36 live ARM helper checks pass.
  The three new mapping helpers contain no hidden temporary allocations.
  Independent lifetime re-review approved the final ownership and lock order.
- Isolated ARM and clean ordinary x86 cross-builds pass. Ordinary x86 excludes
  AGX. No whole-kernel leak measurement, native GPU execution, Vinix boot,
  hardware test, reboot or deployment was performed.

Build baseline: `0d796d280190662107b04597ea77146f14b42992`, plus retained
`kernel/gpu/agx/file/file.v` and `kernel/gpu/agx/gpu/gpu.v` overlays. All AGX and
syncobj V sources match the isolated checkout; both overlays match the retained
architecture inputs and audit snapshot. The sibling `completion.txt` binds the
feature commit to all 18 non-report source snapshots; these reports are retained
and hashed separately after commit.

Fresh Omarchy head `d76f364b41ccf01909b1d84ffcc6bd4fbb8cd91d` and package head
`569728f7d3f2ab5b561bdb8c5078fe169110cbab` still pin Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf` and Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`. The m1n1 reference remains
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

Complete evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-user-map-retirement-20261115/`:
canonical `bundle/`, `inventory.json` and `bundle.tar.gz`. Complete extraction
and restored/canonical inventories passed the unchanged historical checker.
Earlier test-only compilation failures and pre-review runs remain diagnostics.

| Artifact | SHA-256 |
| --- | --- |
| Inventory receipt | `44c89e5cc739ad1cf0ee2a8678d1f875c742a746d57c2031821611e65154fc9f` |
| Complete archive | `711ab9e83ba30503b7082d3710b6b05aa06bca9eff02e6e918f852d1ac001cdc` |
| ARM ELF | `758b0bba4564e16f94a56a4a9f73e4ca5b8566d35a7bd55f54173f0a60ebb3db` |
| x86 ELF | `faf2bb8a8ca19aa3b22fbb0ac2e8b5e24a0957e1ab1106125159a75233a6c436` |

The final audit still returns **not_equivalent** (expected exit 1). Complete
modern ABI/VM/GEM/Mesa integration, replacement/splitting, reservation-fence
semantics and other unverified driver paths remain open. This fixes selected
mapping teardown and borrowing behavior; it does not establish full equivalence.
