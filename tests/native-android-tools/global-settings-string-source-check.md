# Global String writer focused qualification

`framework_settings_global.v` adds
`Settings.Global.putString(ContentResolver,String,String)Z` using the existing
registered-provider adapter. It passes nullable String name/value entries in
fresh `ContentValues` to one virtual resolver insert using Global.CONTENT_URI.
A nonnull URI returns true; null or SQLException returns false. Other runtime
exceptions propagate. The provider owns validation, permissions and storage;
this change adds no persistence, per-user routing or readback cache.

On November 5 the focused driver passed against the exact process-package SDK,
manifest `4a354ead173048b39fb26cce709922f8954e27e53e2d3a5d92ecdf427db0645d`
and JAR `875f854ddf662dcaf55ebe05df06f5833eb5ca1e15f94066ffdf0fef18e829a8`.
Its source checks passed 28 direct refusals, 11 atomic integration refusals,
26 semantic/preservation mutation controls and eight formatting positives.
The private ordinary integration is called through an isolated test-only
adapter; failed validation leaves its input file unchanged. All eleven old
methods, both fields, annotations and original source bytes are preserved.
The earlier putInt generator remains exact.

Baseline and patched API-28 DEX assembly/disassembly passed. Reassembly and
second disassembly are stable; the only new method has the exact String
arguments, namespace, result and SQLException catch range/handler. Global is
excluded from the unchanged 70-class native declaration list. This is focused
host evidence; full SDK/native compatibility and ARM execution remain separate.

Complete evidence is outside Git under
`S=/Users/alex/.local/state/vinix/android`:

- Frozen driver/helper/checker inputs and executable:
  `global-settings-string-source-tools-2026-11-05-r1`.
- Compiler/qualification controls, including both preflight refusals:
  `global-settings-string-source-controls-2026-11-05-r1`.
- Complete compiler-input snapshots, checker results and DEX roundtrips:
  `global-settings-string-source-check-2026-11-05-r1`.

`receipt.json` SHA-256 is
`3ce1fb6339ae28f3635b7a3a8ee6d8968e7cacf57457258b2faec93763af4754`.
The successful `qualify-r2.guard.json` SHA-256 is
`28cb0d04b81d12d6a7e3cf11cb23cb651c0d010539a87f3c517246ce3aae6c2d`:
guard/child0, empty reason, complete cleanup, 11,105 ms, sampled RSS245,760,000
bytes and shared growth15,806,464 bytes. Limits stayed 600 MiB RSS, 300 seconds,
512 MiB growth, 1 GiB reserve and 4 MiB output. The shell file cap was 8 GiB.
Keep these complete bundles and the original SDK/tools; no aggregate seal or
independent aggregate readback is established by this focused run alone.
