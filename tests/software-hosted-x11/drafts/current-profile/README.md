# Current metadata consumption profile: unvalidated draft

`current.v` is an additive, source-only draft. It has not been compiled or
executed. These files stay outside the active `compactproof` package so normal
imports cannot include them. Future qualification must first copy them beside
the independently retained historical module, then compile the fixed entry.
On 2026-11-05 execution admission stopped after free space fell below the
required 2 GiB floor. A brief recovery did not admit a new producer, and free
space fell below 1 GiB again. Compilation, controls, complete consumption checks,
imports and native Launch options acceptance remain pending.

The historical `admit.v`, `source()`, record scope and APIs remain byte-for-byte
unchanged at SHA-256
`558e3d949d310b54d8550bb8d51bbabfab395655f58afdb6167bf1f42fc58f80`.
The new private `CurrentAudits` wrapper uses the same existing callback, ready
token, 30-minute lifetime, exact original checker marker and canonical five-field
record format. Its distinct record scope and `source_current()` binding prevent
cross-acceptance with the historical profile. The 64 KiB record limit remains.

The draft fixes the fresh complete manifests from the separately qualified
[inventory comparison](../../compactdiagnosis/QUALIFICATION.md). It retains both
original refusal records, fresh seal and separate-check records, full difference
reports, owner result/cleanup/qualification, bootstrap source/executable/argv and
environment, compiler identity and source-preserver provenance. The owner result
retains all 87 sampled df outputs and cleanups; this draft does not replay the
raw helper files or introduce a process owner.

Historical mutable source roles resolve through the preserved mapping at
`native-consumer-tools-01/source-before-current-01`. All 32 captured files must
remain ordinary independent copies with their exact bytes and modes. The old
absolute path/hash association stays in the pinned as-run maps and mapping;
returned input paths refer to the preserved copies. This makes no claim that
those original mutable paths remain unchanged after later profile edits.

The explicit entry points are `check_current_audits`, `current_import_build`,
`current_assembled` and `recorded_current_assembled`. Pre/post checks still pass
the complete original target/bootstrap roots to the unchanged original checker,
using the fixed fresh complete inventories. Current imports receive a distinct
method and current complete-manifest hash. Existing historical receipts cannot
be relabelled. Static retention still requires expected producer pre/post record
hashes from the actual qualification and complete input maps.

`current_controls.v` and `currentcheck/main.v` prepare the existing eight
historical control categories plus seven current-profile categories. They use
explicit refusals and synthetic callback receipts; they are not audit execution.
The encoded record size is checked against the unchanged 64 KiB limit and is
reported by the pending controls. The fixed profile has at most 138 input roles,
with bounded role/path lengths and the existing bounded readers. No measured
record size, tool size or test success is claimed before execution. Fixed inputs
are limited to 138 roles and six callback receipt roles; keys are at most 32
bytes and ordinary literal ASCII paths at most 300 bytes. This leaves the
existing 64 KiB record limit intact. The 24 KiB supervisor binding limit is
unchanged and must be checked against the later actual binding plan.

Static table accounting gives 132 fixed inputs and six runtime receipt roles.
The enforced maximum is 138 plus six. With two copies of each role key, a
300-byte path, a 64-byte digest and JSON punctuation, the worst case is 440
bytes per role: 63,360 bytes for 144 roles, plus a fixed header below 512 bytes.
This conservative bound fits 64 KiB without increasing it. It is not a measured
encoded record or a substitute for the pending explicit control.

The isolated uncompiled package is preserved outside Git at
`/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02/native-consumer-tools-01/current-profile-draft-01`.
It contains ordinary copies of the complete host-qualified `compactproof`
package from `be6c728ed`, with the three additive draft V files overlaid beside
the unchanged historical source. `preparation/` retains the separate uncompiled
binder and preparation generator. This package is not a new qualified tool or
evidence of consumption, imports or native execution.

| Source within that package | SHA-256 |
| --- | --- |
| `compactproof/admit.v` | `558e3d949d310b54d8550bb8d51bbabfab395655f58afdb6167bf1f42fc58f80` |
| `compactproof/current.v` | `57f1742d2fd89ea4d1d3f21ef0bc60249aa3f5c793566de4b705ddd0623c8c56` |
| `compactproof/current_controls.v` | `f0ecb7d30f5f899439bc127a89ad962f0da0b362d5b6ae504110aeda1f82cf34` |
| `compactproof/currentcheck/main.v` | `2f79a191c7cb551f49bd7ca9b5279ec85447531e53f05cbd8a7355a591e14730` |
| `preparation/bind-options-compact.v` | `4ae43bc0e197ea15ecbfde302a0d4105299f628e23ffc09b43f8286023423a4b` |
| `preparation/prepare-options-compact.v` | `5cdd0c865e905ea9af9d71495655a5da80ff0e92aa6abb0484c8d200ab09e4c1` |

Remaining gates are independent source review, fresh resource admission,
production compilation and explicit controls, actual encoded-size checks,
reviewed integration into the isolated fixture, both whole-root consumption
checks and imports, fresh consumer-tool qualification, and both native guests.
No compiler, producer, auditor or guest was launched for this draft.
