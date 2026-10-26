The estimate-only runner `wine-source-archive-estimate.v` (source SHA256
`a6e29c776ffe2acc9531270d1f85df337a696b975cb57d4817d81e23addfb8d9`)
measured the complete preserved `wine-source-2026-10-26` bundle on 2026-10-26.
The unchanged historical verifier passed before and after: 12,305 ordinary
files and five exact literal links. The complete metadata/inode inventory was
identical, including nanosecond modification/change times and link counts.

The full-root gzip stream was 985,866,240 bytes, counted and hashed while
writing to `/dev/null`; no archive was retained. Its receipt and 2.1 MiB inventory
are at `/Users/alex/Library/Caches/vinix-codex/section14/wine-source-archive-estimate-01`.
`completed.json` has SHA256
`a96e798500e2c65b24c96ea869dab29b8faeb8aa17fc4b0cc9509aeacdde1cb7`.
The selected build receipt is in sibling `wine-source-estimate-tools-03/build.json`,
SHA256 `d004408d3c82fadc680b7ece46b3f286633ceb39c73fd6e3c5cbf79400775f59`;
it binds literal argv/environment, source, compiler, Clang and selected os
implementation. It makes no complete header/sysroot/linker or hermetic-build claim.
The default-GC host runner makes no memory-retention claim. Initial two refused
compiles are preserved alongside it. All new external state measured 5,744 KiB,
below the 10 MiB observed budget; this was not a filesystem quota.

The inventory has 12,306 ordinary names (including the original manifest),
121 directories and five links. Of 3,007,721,472 bytes reported by `st_blocks`,
2,408,464,384 belong to 5,130 inodes whose hard links are entirely inside this
root; 7,176 inodes have external hard links. APFS sharing and snapshots may
reduce actual recovered space. These counts are an estimate, with no deletion
or archive qualification performed.

Both `wine-dbg-20261026` and `wine-server-debug-2026-10-26` retain historical
`native-x86/image-builder/build-support/build-amd64-iso.sh` links into this
bundle's `wine-native-check-final`. That controller is 1,340,464 bytes with
SHA256 `0de1bffe66d91842789aba513bc3aa4a3e0cda0b76144f647407e43cdd85849a`.
Current CLI/extras inputs have no observed dependency on this root. Historical
reruns require the full original bundle restored at its literal absolute path,
the unchanged external `wine-source-tools-2026-10-26` checkers, and recorded
external inputs. A small controller copy would preserve bytes but would not
make those old links usable without restoration. Any later reclamation requires
stopped writers, a complete retained archive, independent strict verification,
fresh original checks and root identity checks; this runner provides no removal
operation or adversarial atomic-snapshot guarantee.
