# Wine private child bridges

Source baseline: `dd15ee6ad` (the preceding failed checkpoint, integrated on
main as `c05c4f89d`). The source snapshots and their individual SHA-256 hashes
are in `source/` and `source-sha256.json` in the audit bundle below.

Wine discovers its child loader and server beside `/proc/self/exe`. The
adapter now invokes an ordinary private musl copy beside native
`wine`, `wine64` and `wineserver` bridges, with the raw Wine ELFs moved to
`usr/libexec/vinix-wine`. Arguments, server handoff environment and the
existing runtime sandbox grants are preserved. Admission checks bind all
bridge copies, both loader copies, the raw client and the exact server and
ntdll patches to their producer inputs.

Both architecture producers completed with before/after input verification.
Both independent layout controls admitted the original and copied baselines,
then refused ten executable mutations and a symlinked loader. A probe using
the exact production evidence-checker copy helpers admitted its copied
baseline and checked all eleven private executable paths are ordinary files.
The producer also refused an executable built from stale source.

The fresh x86 native attempt stopped **before boot**: the default-GC host
controller reported `invalid package metadata UTF-8 string` while packing the
runtime. Instrumentation localized this to the 552-byte serialized publisher
manifest, in `StoredReader.quoted` at position 60, after its package ID bytes
were corrupted. The original recipes validate, and exact-environment
`-gc none -manualfree` probes packed both runtime and application. This is
preserved as a failed attempt, not native qualification. The retainer and
full evidence controls refused the incomplete baseline; their mutation
matrix did not run.

The captured compiler environment resolves the adjacent pinned V library.
A direct invocation without those environment overrides resolves a different
checkout and does not describe this attempt. The supported compiler source
dump also revealed an uncaptured transitive `compat/ios/plist/plist.v` input;
the frozen failed attempt does not claim a complete native build inventory.
This requires separate fixture admission work before accepting a later pass.

Audit bundle:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-nested-bridge-2026-10-26`.
`SHA256.json` SHA-256:
`de22b815eed9fb1a08cd8e72bb05e1e5aa183aa83eede3fd059e473a09b4a6dd`.

These host controls establish layout and source binding only. Signed Wine
execution, Calculator UI, AArch64 translated fork, source completeness,
redistribution, normal-init startup and guest poweroff remain unqualified.
The current lease fixture checks READY and retirement after observed PIDs
exit; it does not establish lease retention between client exit and a
detached wineserver's exit. A plain `wineserver -w` success cannot establish
that interval without addressing lock errors, prefix replacement and startup
races.
