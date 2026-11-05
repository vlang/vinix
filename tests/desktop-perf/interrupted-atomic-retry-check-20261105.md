# Interrupted atomic runtime retry, 2026-11-05

The prepared x86 atomic retry produced all ops/churn measurements and the cache
measurement, then stopped without the three desktop measurements or DONE.
This is an incomplete diagnostic. Atomic runtime qualification, exact memory
flatness, paired performance, current-main kernel qualification and Section 14
remain open. The cause of interruption is not established.

Artifacts are retained outside Git. Let `C` be
`/Users/alex/Library/Caches/vinix-codex/section14`,
`R2=C/perf-six-x86-retry-20261105-01`, and
`S=C/perf-runtime-host-20261105-01`.
The [prepared image and its independent handoff review](retry-image-preparation-check-20261105.md)
selected the unchanged runtime worktree at
`984fdc1897c7da4b166e2d93baa548cbe8c48e2d`, retained old atomic kernel
`2a7973b2dcb21c7b40aa4fb0fd1de6c9c29c8c6c246a4353445f5698b5150eac`,
and full original kernel manifest
`e82671ca13c4d46b18d1d9762d661f4f392be0ee888d0fb20d1de21f540c54f0`.
This run does not exercise the separately staged current-main integration.

Fresh admission and executable pins passed before the launch. The fixed
six-scenario workload, deadlines (2400/2520 seconds), 32 MiB output cap,
2/1 GiB free-space floors and inclusive four-root 4.5 GiB ceiling were unchanged.
All earlier failures remained charged. The live process record identified
owner 76676, adapter 76965 and QEMU 77174, each with its own corresponding
process group, exact executable spelling and reviewed argv. Optional compiler
admissions were asked to pause before the cache/desktop tail.

On resumption, all three exact PIDs and groups were absent (`ps` and `pgrep`
each returned 1). This present-day absence is separate from original ownership,
wait/reap and cleanup evidence. No terminal owner or adapter receipt, actual exit
status, after-input map, adapter serial log or adapter result status survived.
The outer log is empty. The native journal retains 1,267 rows, ending at sample
start 1,297.331594666 seconds without a final completion record. No successful
deadline enforcement, final sample gap, typed cleanup or equal runtime input
maps are inferred.

The preserved live stream `run-owner-atomic-01/command.log` ends after cache
MEMINFO. Literal text counts are 36 ops rows, four churn rows, one cache row,
80 snapshot beginnings and 640 emitted delta rows. The unchanged strict full
checker, legacy emitted-delta checker and diagnostic observation consumer each
returned actual status 1: idle/apps/drag account for the three missing
measurements out of 44, and DONE is absent. These counts are not an accepted
complete observation document. Six emitted rows have nonzero backing-page
deltas (memfd/tmp size-256 -1; file/tmp size-64 +1; unlink_open/tmp size-256 -1;
hardlink/tmp size-256 +1; rename/root size-256 -1; unlink_open/root size-256 +1).
No cause or flatness acceptance follows from those partial observations.
Before/after hashes of the three consumers and stream matched.

The post-interruption original full kernel audit returned actual
status 0. Exact markers matched; original source/manifest pins and complete
before/after audit input map remained unchanged. Its 23 samples had maximum
start gap 1.021637458 seconds and complete window 0.362068666 seconds; the
original audit child group was absent and waitpid reported ECHILD. This closes
the kernel-input check only; it cannot recover missing runtime receipts.

Read-only media checks found the ISO, initramfs, observer ELF and init ELF still
equal to their prepared pins. The writable ext2 digest changed during execution.
The current owner refuses the existing results directory; the adapter also
refuses the retained stale QMP socket. It offers no independent new result
directory for a retry. No results/socket deletion, receipt rewriting, image
reset, fresh staging or further VM execution was performed. Reusing immutable
boot media would require a separately reviewed implementation/profile, a fresh
writable workload disk and new admission; this report grants no reuse authority.

The complete R2 literal inventory is stored outside R2 at
`S/retry-runtime-inventory-01/primary.tsv`: 3,582 entries, 470,803 bytes,
root mode 16877. R2 is left unchanged after that capture, including all missing
receipts and the failed stream. The inventory preserves literal content, paths,
modes and link targets; it does not supply runtime acceptance.
Root independently captured the complete unchanged R2 tree to
`S/retry-runtime-inventory-01/root-independent.tsv`; it matched the primary
map byte for byte with the same entry count, byte count, root mode and checksum.
Root also independently observed ESRCH for all three former process groups;
this is present-day absence only. No files were written into R2 after capture.
The complete older failed R inventory was also recaptured after closure and
still matched its frozen `03ce6150f13b2f25454f5fc163d82b1ad8483006372b7261cc0a9a4cfd92ff93`
map byte for byte (7,162 entries, 937,758 bytes).

| Artifact relative to R2 unless prefixed S | SHA256 |
| --- | --- |
| run-atomic-01.json | `dddf11423c01efa170b5d775305b6c457fd9728353c1a9541c2e2c2933394a45` |
| run-owner-atomic-01/command.log | `04383136f8ebfc7231a0e3ca41e57033d24e58caee82945d9db3d8590ee61d43` |
| run-owner-atomic-01/inputs-before.json | `09727e27234420271bc56b463ff8a999ff44992fc7f04e721b6e493089e9de12` |
| run-owner-atomic-01/budgets.jsonl | `30cfe98fbf64074294c24c4a6fe66a307de404f427686d2b8f0170c4854a40b3` |
| retired-checks-01/status.json | `3d9cf0bd3d257a79b0476219a7322beb14a01338c498c9ae6ce8d5c073d1f81f` |
| retired-checks-01/full.log and legacy.log | `66e5125a44d65f7aea1d093ba0062ffbb2e7c2753d482e0f1e8df3d16e839fe5` |
| retired-checks-01/observations.log | `3e7011e385ae70d19fa2235816288522cf6a014c83f92dd38f5265fc549cfea5` |
| retired-checks-01/pins-before.sha256 and pins-after.sha256 | `e1ceaf91e0e43d5d82772bb27af104ec88e9bd3f125aaa65337dec4559241bf1` |
| retired-checks-01/media-after.sha256 | `bde59d3ea3a750b4e6eeb0c45d83ba52d0121df4091ce7490dd5f4fcbec12b20` |
| audit-atomic-after-interruption-01/audit.json | `220c93657cbe7acea3a94d15dd8eb128c8152dcd23444e5c9c538c19836d61aa` |
| S/retry-runtime-inventory-01/primary.tsv | `c1bb658176983b19d8c2f907f85a426fa9ac91006ed14e5b9f6ca7a63dd4a763` |

The closure endpoint measured 3,618,877 KiB apparent and 2,706,724 KiB allocated
across the same four roots, with 19,530,836 KiB free. Old R and R2 remain
preserved; no new retry budget is admitted here.
