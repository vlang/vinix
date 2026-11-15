# M1 AGX GPU mapping permissions, 2026-11-15

Status: **incomplete driver parity**. Native BIND previously selected GPU
read/write permission whenever the write flag was present, including a
write-only request. It now distinguishes read-only, write-only and read/write,
matching Omarchy's packaged Asahi selection and G13 UAT protection encoding.

The write-only selector uses AP=2 with PXN set and UXN clear. The existing
read-only and read/write selectors retain their encodings. Protection words
below omit physical address, leaf type and non-global bits:

| Access | UAT protection word |
| --- | --- |
| Read-only | `0x0080000000000488` |
| Write-only | `0x00a0000000000488` |
| Read/write | `0x00c0000000000488` |

Offline validation passed:

- The production BIND ioctl selects three distinct modes through an injected
  page-table service. Empty and unknown flags reject before mapping; GEM
  references return after unbind/close. The prior 200 retirement cycles and
  shutdown/VM-destruction regressions still pass under ASan/UBSan.
- The production page-table code produces the exact leaf words, including
  physical address and non-global bits. All nine ordered reprotection pairs
  replace the selector before the recorded ASID invalidation. Host page-table
  allocations return to zero; prior rollback/root/global/TLBI tests pass.
- A source gate compares Asahi's RO/WO/RW constants, bit shifts, `from_bits`,
  `as_pte` and bind selection. Negative tests reject collapsed selectors,
  wrong AP/shift/composition and duplicate declarations. Three V unit suites
  (five test files) and all 36 generated ARM helper/storage checks pass.
- Isolated ARM and clean ordinary x86 cross-builds pass. Ordinary x86 excludes
  AGX. This scalar fix introduces no production allocation or lifetime changes.

Build baseline: `5be3fd4865049949bb791bfd4001645b985510ff`, plus the retained
file and page-table overlays. All AGX/syncobj V inputs match the isolated
checkout; both overlays match the retained architecture inputs and final audit
snapshot. The sibling `completion.txt` binds the feature commit to all 12
non-report snapshots; committed reports are retained and hashed separately.

Omarchy head `d76f364b41ccf01909b1d84ffcc6bd4fbb8cd91d` and package head
`569728f7d3f2ab5b561bdb8c5078fe169110cbab` were rechecked and remain unchanged.
They pin Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf` and Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`. The m1n1 reference is
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

Complete evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-gpu-permissions-20261115/`:
canonical `bundle/`, `inventory.json` and `bundle.tar.gz`. Complete extraction
and restored/canonical inventories passed the unchanged historical checker.
Earlier runs and the earlier source gate remain diagnostic evidence; final
tests reset the source mode before each target to cover all nine ordered pairs.

| Artifact | SHA-256 |
| --- | --- |
| Inventory receipt | `036fef0bd19e54528e8a4a86b31ad23c2c45fcddb63a5cb6d97980b75a90f424` |
| Complete archive | `bb6d1770bb4fb394406fb245fa6d606de401f60186b4b9dbb19806bfa7754d09` |
| ARM ELF | `e9570a049549b145d57d9b871719a1505386501fa5f74e1abe6b27d2810a41ca` |
| x86 ELF | `52de370194ee749b7247d6ed093d8e0b669c3438fd07e7bf01b5212add311239` |

The final audit still returns **not_equivalent** (expected exit 1). Legacy
wire flag values/layouts, modern ABI/VM/GEM/Mesa integration and other
unverified driver behavior remain open. Host fixtures inject privileged
instructions and services; no hardware permission fault, native GPU execution,
whole-kernel leak measurement, Vinix boot, reboot or deployment is claimed.
