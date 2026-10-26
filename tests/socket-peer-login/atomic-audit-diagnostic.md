# Atomic peer-login audit refusal, 2026-10-26

The atomic kernel bundle no longer passes its original complete state audit.
Runtime host-controls attempt `controls-01` stopped at the first audit with
actual exit 1, `state inventory mismatch`, after 51,321 ms. The owned checker
leader was reaped and its process group was absent. Input inventory, synthetic
host controls, target compilation and guest execution were never reached.

The original bundle is
`/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-20261026`.
Its original manifest remains
`matched-peer-frame-atomic-20261026-seal-01/complete/inventory.json`, under the
same cache parent, SHA-256
`d7764b47d4c617550ed67af5eee5167392f818ea51e884d1a6abaf3469acf118`.
The unchanged checker is `alloc-track-frame-kernel-20261026-seal-02/frame-page-seal`,
SHA-256 `fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6`;
its maintained source `tests/kernel-allocs/frame-page-seal.v` has SHA-256
`8cd5e58df42e07760d0e1b73c49807b0ee2c7e353412e7d54aca34a7597577d4`.
The refused invocation, actual status and log remain in
`peer-login-atomic-runtime-20261026/controls-01` under that cache parent.
The result SHA-256 is
`f70867b6994d0d59dbb1994af046eed473a6374847e9fc0a9a0c4c4b469192f2`.

A separate read-only diagnostic retained every current regular-file hash,
literal symlink and recorded metadata field without changing the original
bundle or manifest. `state-capture.v` uses the original checker's exact
`Entry`, `Manifest`, `digest` and `visit` implementation, but performs one scan
and writes an explicitly diagnostic inventory outside the bundle. It creates
no seal and supplies no replacement qualification.

The saved and current inventories each contain 5,173 entries, with no missing
or extra paths. File sizes, file hashes, link targets, device numbers, modes,
owners, manifest header and entry order match. There are exactly 60 changed
fields on 30 paths: 17 regular files changed inode and ctime; 13 containing
directories changed mtime and ctime. These include both `build-02` kernel
executables, their generated C and object files, retained input inventories,
and earlier bootstrap generated C. The comparison establishes metadata
changes; it does not establish which process made them.

Diagnostic evidence is outside Git at
`/Users/alex/Library/Caches/vinix-codex/section14/peer-login-atomic-runtime-diagnostic-20261026-01`.
`difference.json` records all 60 before/after fields; SHA-256
`49a57af472993506d15149e9676eafa2bd9b88b4906eecf79f0aab8c45c82ff2`.
`current-inventory.json` has SHA-256
`5e3e44019de0da0ff42b15c603d2c91de36b5829d4f47d94758cf8ffa7d76e6d`.
The maintained comparator is `tests/desktop-perf/state-inventory-diff.v`,
SHA-256 `f6739b47a72c316b36b7f6cc0bf1c6b4330b082c916de294aaa7848ed09d65df`.
Its retained executable has SHA-256
`67b1b0f82d1bb6e498c353fe80283822816a95a5f72d2a797e42d8003ddadafa`.

On source base `eac96710f822bfc10820ff9317884aa107c475c4`, capture source
SHA-256 `610abaa0dfdcc475196af8f36dc6c24cc960329d81a7a1b1b218e04dbc3e7b3e`
compiled with the retained ff75 V compiler, `-prod -nocache -keepc`, LLVM 23
and `-Werror=incompatible-pointer-types`; executable SHA-256
`7059f230736bdd7502045b6ad172c5882e6c45b8fab3085d49860c090feac50c`.
Comparator self-check (11 controls), helper compilation, single scan and full
comparison each returned actual exit 0 within 28,680 ms total, against a
120-second global bound and a 64 MiB allocated/logical evidence limit.
Observed final evidence plus worktree occupied 3,548 KiB allocated and
3,396 KiB logical. Literal argv, environment, actual statuses, logs, source
copies, generated C, link map and budget observations remain in that evidence
directory; `execution-status.json` SHA-256 is
`eb610b15e38ac5a9d3f171eb0b44542625b80344bb271d5d6e80e736eb918882`.
`checksums.sha256` records all 34 diagnostic files retained before that index;
its SHA-256 is
`28f0b689dfcbba4bec7e29c17aa70b071fb0f0630c64f89d91117fde59f72421`.
No diagnostic or checker process remained in the final process listing.

The original audit remains refused. No new host-controls, kernel, guest,
memory, performance or desktop qualification is claimed.
