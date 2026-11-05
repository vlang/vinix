# Literal performance-base manifest qualification

`literal-manifest.v create ROOT NEW_MANIFEST` emits the exact sorted, literal
tree manifest consumed by the x86 performance adapter and reports the separate
root mode, entry count and SHA256 as JSON. Regular files are hashed in 64 KiB
chunks; absolute, relative, intermediate and dangling guest links remain literal.
The helper checks descriptor/path metadata during each file read and directory
membership/metadata across traversal. It requires a canonical ordinary root and
an exclusive output under a canonical external parent, with checked writes and
close. Limits are 120 seconds, 250,000 entries, 128 directory levels and 32 MiB
of manifest text; an overrun cannot report success.

This is a trusted, quiescent host-tree observation. Per-node checks use the
selected V library's second-resolution metadata and do not establish a globally
coherent snapshot under concurrent edits. The adapter must still compare the
approved manifest during actual preparation and verify inputs afterward. This
helper neither stages a tree nor executes a guest.

On source base `a32bb0de15123dcced72f1f4b83e18196f607160`, normal and production
builds both exited 0 and passed all 16 explicit controls. They cover exact
legacy rows/modes/order, literal guest links, unchanged source metadata,
exclusive output, freshness/containment and canonical-alias refusals, invalid
path/link characters, unopened FIFO refusal, metadata changes and traversal
limits. Both executables returned actual 1 for usage and an absent source.
Independent source/lifetime review passed. Final source SHA256 is
`f56d39e699660fd7ffb2c0112df962cb0bcacc9168f68e5b1e3a32e4d6d1cef8`.

Raw source copies, generated C, exact final build/control argv and environment
maps, logs, binaries and receipts remain outside Git at
`/Users/alex/Library/Caches/vinix-codex/section14/literal-manifest-host-20261105-01`.
The successful final modes are `normal-02` and `production-02`. The earlier
normal build/control pass is preserved with its earlier source and does not
replace qualification of the final source.

| Artifact | SHA256 |
| --- | --- |
| Normal executable | `a44c94610de93d80c496187c963075785da11235c7c2959773344fb633cbcced` |
| Production executable | `027d1268392b0e21465620136db59bbaf375666495aa005da4b7da98c1672f75` |
| Each final control receipt | `ceb9d4e361c3ad6f110b012f24d63ab61f0a86f397e7ad72038eb3c429b189f2` |
| Complete compiler inventory | `ff729f3d39ad09b0401c2f1e08e69784db5c4781117c1f1480a59ee4ffdd39e9` |
| Equal flat before/after input map | `c2bc2e8bfdeefd644cff198dcd35eb8eb6a35f078b29cad78a824329b0e1afec` |

Both modes used the pinned ff75 V, clang23, `-nocache -keepc` and strict pointer
diagnostics, with cleared coherent compiler markers and private module/cache/
temporary paths. The unchanged original full compiler seal and post-check
both exited 0; owned source, selected compiler/clang and SDK metadata hashes
also matched before/after. The complete mutable worktree was not inventoried.
The final report was written after these comparisons.

Endpoint observations measured 9,612 KiB allocated and 9,082 KiB apparent across
the shared worktree and this complete host state, including prior attempts,
below the 512 MiB allowance. Free space exceeded the 2 GiB admission and 1 GiB
continued-execution floors. No continuous resource-monitoring, complete host
SDK/loader closure, real release-base capture or whole host-bundle seal is
claimed by this host qualification.
