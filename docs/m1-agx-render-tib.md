# M1 native fragment TIB sizing, 2026-11-15

Status: **incomplete driver parity**. Native G13 render preparation now
derives both fragment tile-image-buffer block counts as Asahi does:
`ceil(utile_width * utile_height * samples * sample_size / 2048)`.
Previously it trusted the redundant legacy `tib_blocks` input. That field
retains its binary layout but no longer controls native G13 firmware sizing.

The calculation validates geometry, uses 64-bit intermediates and refuses a
result exceeding the firmware's 32-bit word before narrowing. It runs before
the manager lock and job allocation. Both fragment parameter blocks receive
the result before conversion to the selected firmware ABI. The packaged
sample-size field is eight bits; the overflow check also protects the wider
legacy input. Other legacy render fields and fake G17 behavior are unchanged.

Offline validation passed:

- ASan/UBSan executes the actual firmware helper for all 2,304 combinations
  of supported uTile/sample configurations and packaged sample sizes. An
  independent rational-size oracle covers zero, partial and complete blocks;
  additional cases check wide legacy bounds, overflow and invalid geometry.
- The full existing command/layout probe passes. Both TIB field offsets are
  checked, and distinct sentinels survive conversion to firmware 13.5 at
  `0x3f4` and `0x6d0`. The new V runner provides an uncached, monolithic
  sanitizer entry point; set `AGX_LAYOUT_TEST_BINARY` to retain its executable.
- Three V suites (nine test files), packaged-source/reference gates and all
  41 live ARM generated-C helper checks pass. Negative source/storage tests
  reject the old input assignments, missing rounding/overflow checks, changed
  reference units, missing/duplicate helpers and hidden allocations.
- Isolated ARM and clean ordinary x86 builds pass; ordinary x86 excludes AGX.
  No owning pointer, allocation site, free or callback lifetime changed.

Build baseline: `6d03338624563b0532e08faf7044a39cc02d3ea8`, plus retained
`gpu/agx/fw/fragment.v` and `gpu/agx/gpu/g13.v` overlays. All AGX/syncobj/GEM/
ioctl V sources and generic `drm.v` match the isolated checkout. Both
architecture overlays match the audited snapshot. The sibling `completion.txt`
binds all eight non-report feature sources to the commit and retains the two
committed reports separately.

Fresh clones match the checked remote heads: Omarchy
`d920320e65302645ab772748f4d9ba1f32ab5de4`, packages
`d44541f0f71cf2ccaecc3774a54ca2cdd791f41c`. They still select Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf` and Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`; m1n1 remains
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

Complete evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-render-tib-20261115/`:
canonical `bundle/`, `inventory.json` and `bundle.tar.gz`. Complete extraction
and restored/canonical inventories pass the unchanged historical checker.

| Artifact | SHA-256 |
| --- | --- |
| Inventory receipt | `bf4a3599bae97d2669616dc49a4d85f0c1d469a46fe3a8828b132398dbbf06e3` |
| Complete archive | `1d4182e841531dfb5ad6926206920c9261b1a737ca8a3d3425f7cddc5f1eb5cc` |
| ARM ELF | `c3760dd6f0bd30e8ee44b49c2249f4fa9dc30ab531f1e917a5acd8912706ee1c` |
| x86 ELF | `221eb973c913785894508e369351eeb1f912442f3529f72d5c36415d69aa13a2` |

The audit still returns **not_equivalent** (expected exit 1). This establishes
selected sizing and wire behavior, not complete render or driver equivalence.
Modern ABI/Mesa integration, reservation-fence/cache/accounting semantics,
other render defaults and unchecked behavior remain open. No GPU/firmware
execution, Vinix boot, hardware test, heap measurement, reboot or deployment
occurred.
