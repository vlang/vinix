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
