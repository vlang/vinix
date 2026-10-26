# ARM audio compiler diagnostics

The frozen audio adapter removes the hardware harness's inherited `-w` for
AArch64 and treats incompatible pointer types as errors. It refuses ARM
`-fpermissive` before compiling. The selected backend's
`-dumpmachine` result selects this behavior; historical x86 argument forwarding
is unchanged. Shared hardware tooling and production audio sources are unchanged.

The maintained input checker supplies the inherited `-w` on real captured-input
probe and current-tone links. It also checks the real compiler's argument trace,
requires warning flags to survive, removes only the existing sockaddr cast from
the generated tone's connect macro, and requires that invalid variant to fail
without an executable even when a caller requests a weaker pointer diagnostic.
An ARM permissive-mode control must fail at the adapter boundary. Test mutations
are performed by V tooling on the actual generated translation unit.

Pinned production host builds passed for the controller, retainer, preparation
checker, evidence checker, adapter and input checker. The input checker passed
41 controls, including both real static AArch64 links and the pointer/permissive
refusals. The preparation checker passed 88 controls and the strict ARM evidence
matrix passed 34. Independent review checked the retained commands, generated C,
binary hashes, specific compiler error, refusal statuses and unchanged input maps.
Historical x86 forwarding received source review; x86 compilation was not run.

Tested source is base `a6ffad1524923a63875b64bd99db931eb4c8cb5a` with this
adapter/checker change. Adapter SHA-256 is
`55589b19507d3463cde7145ac9d373d7d65a3cc2a67d9e53da4b3da1188db3d7`;
checker SHA-256 is
`98ddcefa5b83dbbf7150543af13293f7d65a0d461388eaf6704dffa149628b5b`.
Evidence is preserved under
`/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/pointer-host-01`.
Its `host-build.json` SHA-256 is
`98421f8f7c8daadcb78ee83ba56f26e9ee29b8798a46c63ba7560b9bed0340bd`.
The sibling `pointer-host-validation.json` inventories 23,743 entries, including
bootstrap helpers and preserved failed inventory attempts, with SHA-256
`f5d84dbfe4501cd34f4bd88a6a214df432e5042dc94baae5edc90fd2acef3f6f`.
It records literal symlinks and FIFO declarations without traversing or opening
them. Retained new state is 103.3 MiB, with preexisting captured inputs accounted
separately. Original V,
host Clang/SDK and GCC executable internals are observed and pinned at their
original paths; this is not a hermetic toolchain claim. The host build's recorded
Clang compatibility flag is separate from the strict ARM target invocations.

During final preservation checks, the two edited source leaves were found to
share hardlinks with three older snapshots. Their temporary mutation and inode
scope are recorded in `snapshot-restoration`. The worktree was detached, and
each older leaf was independently detached and restored from separate copies
matching its previously sealed digest. The complete original 22,666-entry
inventory then verified unchanged with SHA-256
`a2b9e1153f1443ecfaf6eefc927abe86f8f0bfd6d3f455aee81a58d63226f209`.
Original logs, receipts and inventories were not rewritten; the new controls kept
their exact tested source bytes.

Target preparation and guest execution remain held. These host checks establish
the compiler prerequisite and do not qualify native audio.
