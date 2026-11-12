# Test source and execution artifacts

Keep regression programs, intentional fixtures, runners, checkers and concise
reports in Git. Execution evidence belongs outside the repository: compiled
kernels and probes, generated C, firmware state, boot media, packet captures,
screenshots, logs and complete build-input inventories.

The Linux compatibility runner already accepts `--state-dir /external/fresh-dir`.
Use a fresh directory per architecture and run. Keep the complete bundle,
including its hash manifest, when retaining an audited result. Evidence
checkers accept an explicit directory, for example:

```sh
v run tests/linux-compat/semabi-evidence.v check /external/semabi-evidence
```

Archive bundles by source revision with a checksum in external artifact
storage. CI jobs can upload them as job artifacts; long-lived qualification
evidence needs storage with an appropriate retention period. A short committed
report should identify the source revision, result, archive location and
checksum. The existing `.github/workflows/m1-wifi-build.yml` demonstrates
artifact uploads. Do not remove checks from an auditor to make a partial bundle
pass.

For a large immutable workspace retained in place,
`tests/ios/swift-staging-archive.v check-archive-root ARCHIVE SHA256 ROOT`
decodes every archived payload and compares the complete named root's paths,
types, modes, links, sizes and hashes, including the root mode. Its parent may
contain unrelated workspaces; all members inside the named root must match.
This mode reads logical file contents through libarchive, including sparse
holes. Converting a sparse tar member to mtree can hash only stored extents
on macOS and is insufficient for this comparison. Building the checker needs
libarchive headers (`brew install libarchive` on Apple Silicon macOS); it
links the system libarchive there. Its selftest covers sparse holes, changed
logical bytes and equivalent allocated zero bytes.
The existing restoration and coverage modes keep their original contracts.
`tests/packages/wine-workspace-archive.v SOURCE NEW_ARCHIVE.tar.gz CHECKER`
records the original typed inventory before compression, invokes that check,
and rechecks the full original inventory and archive checksum afterward. It
retains originals and avoids another expanded copy. This does not authorize
retiring expanded evidence or substitute for launch auditors or restoration
requirements before deletion.

For a retained workspace containing symlinks when another compressed copy will
not fit, the same V tool supports `record-inventory SOURCE FRESH_EXTERNAL_JSON`
and `check-inventory SOURCE JSON`. The receipt covers every logical file byte,
size, mode, directory/root mode and link target, and records source/tool hashes.
Recording compares two complete inventories before publishing the receipt;
checking compares the retained workspace again. Keep the canonical original
workspace and pin the receipt checksum in the report. This records integrity
without creating an archive and does not qualify a launch, replace a historical
auditor or authorize removing originals. Its selftest also refuses changed
bytes, links, file/root permissions, hidden additions, missing files, overwrite
and a receipt inside the source workspace.

An optional trailing `--fast` selects gzip level 1 for large workspaces; the
literal compression command is retained. This trades compressed size for CPU
time and preserves the same complete logical-content and metadata checks.

If compression completed but verification failed, preserve the failed audit.
`wine-workspace-archive verify-existing SOURCE ARCHIVE.tar.gz SHA256 CHECKER`
requires an explicit matching archive checksum and fresh qualification
receipts. It records a separate `.verified-audit`, compares every logical
archive member with the complete source, and rechecks the source inventory,
archive and tool identities afterward. It never overwrites an earlier audit
or existing qualification receipts. `selftest FRESH_EXTERNAL_DIR CHECKER`
checks fresh and existing sparse archives, wrong pins, changed source bytes,
changed links and refusal to overwrite receipts.

For a complete diagnostic bundle whose outcome falls outside a historical
auditor's contract, preserve that auditor and its rejection. The V tool
`tests/ios/evidence-delta-archive.v record-inventory BUNDLE EXTERNAL-RECEIPT`
records every file's bytes, size and permissions, directories and root mode;
`check-inventory BUNDLE RECEIPT` compares them again. Pin the receipt's SHA-256
in the report. This protects evidence integrity; it does not certify launch
success or replace the historical qualification checks.

`tests/ios/swift-staging-archive.v check-coverage RETAINED SHA256 RETIRING SHA256`
can prove that a retained archive contains every entry of a redundant backup.
It decodes both complete archives and compares paths, file bytes and sizes,
types, permissions and link targets, binding both inputs to checksums before
and after the comparison. Retained archives may contain additional entries.
Keep the coverage proof, retiring inventory, checksums and retained archive;
establish the retained bundle's complete restoration and unchanged historical
audit separately before retiring a backup. Coverage is not launch qualification
and never permits a partial bundle to pass a historical auditor.

For a large cold-storage candidate, `tests/native-android-ws/cold-archive-estimate.v`
can count a complete gzip archive stream without storing the archive. Pass the
bundle directory, its pinned `sha256.json` checksum and a fresh external JSON
receipt path. The receipt records the byte count, command, source and tool hashes.
This estimates archive size only: APFS clones may share physical extents, so `du`
and archive size do not establish how much removing an expanded tree would free.
Retain a checksum-verified archive, restore the complete bundle, compare its full
typed inventory and run the unchanged auditor before removing expanded evidence.

`tests/native-android-ws/apfs-extent-sample.v` records read-only physical extent
samples for supplied files. `zero-range-scan.v` hashes a file and reports aligned
zero ranges without changing it. Their receipts do not qualify deletion or hole
punching: zero bytes can already be sparse or shared with retained APFS clones.

`tests/**/results/` and `/artifacts/` are ignored. Historical source snapshots
and Markdown reports up to 64 KiB remain tracked where useful. Their links to
raw results refer to archived evidence, which must be restored before auditing.
To restore an original directory from a local history backup:

```sh
mkdir -p /external/evidence
git archive BACKUP_COMMIT tests/linux-compat/results | tar -x -C /external/evidence
```

The cleanup backup directory contains a Git bundle of the unpublished history,
the original tip and base, a commit mapping, removed-path inventory and working
edit snapshots. Keep the bundle outside the repository. It preserves every
historical artifact version, rather than just the final result directory.
`git bundle verify /external/backup/original.bundle` verifies the bundle; its
published base commit is a prerequisite. If its backup ref is no longer local,
`git fetch /external/backup/original.bundle 'refs/vinix-backups/*:refs/vinix-backups/*'`
restores it. Never push backup refs containing artifacts.

Enable the V pre-push check in each clone:

```sh
git config core.hooksPath .githooks
v run tools/git-source-policy.v origin/master HEAD
```

The check examines all outgoing file versions, including files deleted by later
commits. It rejects generated result files, compiler-generated C in result
directories, result reports over 64 KiB, and any file over 5 MiB. Source snapshots
(`.v`, hand-written `.c`, `.h`, `.s`, `.sh`, `.diff`, `.patch`) and small result
reports remain permitted. Keep new maintained test source outside result trees;
deliberate fixtures belong with the test that uses them. New remote refs exclude
history in known remote-tracking refs; with no known remote refs, the entire
history is checked.

Removing an artifact in a later commit does not remove it from a push. If it
has never been published, archive it and rewrite only the unpublished commits.
Keep the published base unchanged so the cleaned branch remains a fast-forward.
