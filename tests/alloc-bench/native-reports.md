# Native saved-campaign analysis

The v4, v5 and v6 allocation campaigns use V for their comparators,
recomputation, negative integrity fixtures and historical evidence recovery.
The retired ten Python implementations contained 149,927 bytes. Their original
paths, hashes and Git provenance are in [native-translation.json](native-translation.json).

Each campaign directory provides `compare`, `recompute` and `check-recompute`
shell entry points. They compile the maintained V source outside the checkout
through the repository's compiler selector. For example:

```sh
tests/alloc-bench/results/2026-10-03-userspace-v6/recompute
tests/alloc-bench/results/2026-10-03-userspace-v6/recompute --json
tests/alloc-bench/results/2026-10-03-userspace-v6/check-recompute --output /tmp/report-findings.json
tests/alloc-bench/materialize-evidence verify
tests/alloc-bench/test-native-reports
tests/alloc-bench/test-evidence-owner
```

The three byte-identical historical comparators share the already maintained
[comparison core](comparecore/core.v). The [report core](reportcore/report.v)
keeps separate campaign kernel, loader, static libc, patch and v6 plan pins.
Every declared capture, raw observation, outlier, build manifest, driver exit,
explicit UTC timestamp and actual QEMU argument participates in validation.
Slower complete data remains a failed parity result. JSON retains exact raw
integer tokens, including integers above 2^53 and the distinction between an
integer driver exit and a Boolean.

The saved `source-snapshots.json` files still describe the original benchmark
and comparator, and all saved inputs/reports remain unchanged. Recomputation
checks the original comparator bytes directly in the pinned Git commit;
those bytes are never imported or executed. It separately pins the current V
comparison policy and CLI. Changes to that policy require an intentional
update of its native pins and qualification. Missing benchmark C evidence is
read through the native [evidence reader](evidencearchive/archive.v), whose
historical C archive continues to receive zero translation credit.

The [fixture suite](reportfixture/integrity.v) retains all 170 original checks
and adds native CLI tampering: 171 checks per campaign. It copies unchanged
actual v3 captures into private temporary directories, substitutes synthetic
configuration and timestamps, checks all 14 observations independently, and
rejects each integrity violation. It never saves fixture timings as new
campaign measurements and creates no Python fixture scripts.

Qualification compares each saved JSON report exactly by typed numeric value
and each Markdown report body byte for byte. The published v4/v5 documents
have an extra title; their original recomputation CLI printed the body alone.
All 145 archive records verify against immutable Git objects and retained
third-party bytes. Recovery checks binary payloads and modes, duplicate
recovery, refusal to overwrite changed evidence, noncanonical paths, symlink
escapes and destinations inside the checkout. Git protocol fixtures cover
malformed headers, missing objects, incomplete frames, oversized and
overflowing lengths, binary data, large replies and stderr backpressure.

The reader owns Git's process group and pipes. It detects EOF without reaping
the leader, then kills the owned group before waiting: this also retires a
surviving descendant after Git exits. Repeated failed reads keep the measured
descriptor set flat; SIGINT/SIGTERM return 130/143 and retire Git and its
descendant. Recovery uses exclusive file creation and removes incomplete
owned files on interruption.

Fresh builds and these behavior/resource checks run on ARM, Rosetta x86 and
ARM ASan/UBSan. Private retained logs, original-source hashes, fixture findings
and build hashes are under
`~/.cache/vinix-benchmark-native-20261011`. Temporary build executables are on
the task's RAM scratch directory and are not durable evidence. No Python is
run, benchmark timing is recaptured, or kernel is rebuilt for this port.
