# Encrypted ciphertext scrub history qualification

`compare-volume-scrubs BEFORE_REPORT AFTER_REPORT` validates both complete
private reports and their identical embedded references before reporting
stable/new-change/restored/changed-again history. Equal observed digests return
0, different digests return 2, and input/output errors return 1. Stable changed
reports still differ from the reference. Ordering is caller supplied; reports
have no timestamps. See [the contract](../../docs/storage-volumes.md#comparing-encrypted-ciphertext-scrub-history).

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-scrub-compare --work /tmp/scrub-compare-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --scrub-compare --work /tmp/scrub-compare-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --scrub-compare --work /tmp/scrub-compare-x86
```

The scoped host runs the previous authenticated codecs, scrub codec and actual
reader/publisher/probe model alongside new native comparison and model cases
under ASan/UBSan. Eight MBR/GPT, 512/4096-sector and saved-mode profiles cover
all nine pairs of clean/two distinct changed digests, exact independently
formatted output, full-width disk capacities and stable comparisons of the
same pathname. Native cases corrupt every byte on both sides, reject bad
sizes and preserve caller outputs on failure. Independently valid references
with changed capacity, slot, start, length, mode, identity or expected digest
must be refused after repairing their CRCs and fingerprints.

The actual pinned reader handles interrupted/short reads and rejects missing,
wrong-length, nonprivate, wrong-owner, symlink, incomplete and changed inputs.
A malformed second report emits no comparison. Formatting, flush and stream
faults return 1 for stable and changed histories alike. Observers require no
device probes/opens, KDF, entropy, locks, publication, writes or unlinks, and
all opened input descriptors must close. Input bytes remain preserved.

The selected guest first executes the previous complete scrub scenario using
the real CLI/full-profile KDF to create eight genuine historical reports.
New comparison cases test clean/stable changed, new change, restoration,
cross-credential comparison, both saved modes, same paths, different-reference
refusal and an invalid later report. A held live mapping preserves all status
fields and plaintext reads. One hundred warmup and one hundred measured cycles
each execute three comparisons; warmed slab classes and large-page counts must
stay equal after thirteen-second reclamation waits. A second boot reorders
physical devices, repeats the historical matrix without discovery, and then
performs a separate explicit recovery unlock.

The unchanged independent scrub artifact oracle verifies all bytes of the
two references/eight reports and OpenSSL ciphertext/fingerprint digests from
each persisted guest. Complete utility and selected guest C receive allocation
audits and independent lifetime review. Frozen isolated ALLOC_TRACK kernels
stay unchanged. Further changed-to-changed digest transitions and injected
read/output faults are host-model coverage.

## Qualification on 2026-10-13

Final `host-5`, `arm-2` and `x86-2` receipts are zero. The scoped host passed
ASan/UBSan without sanitizer or undefined-behavior errors; all four guest boots
passed. Earlier host and guest attempts stopped on V/C compile errors in the
new mutable-bool signature, Result handling, fixed-array addresses, FIFO binding
and guest nil pointer. Those receipts are retained. The production signature
uses an explicitly borrowed stack bool committed only after validation; final
production and guest sources stayed unchanged during successful qualification.

| Guest | Warmup + measured cycles | Comparison processes | Slab classes with zero delta | Large pages before → after |
| --- | --- | --- | --- | --- |
| ARM64 | 100 + 100 | 600 | 18 | 72 → 72 |
| x86_64 | 100 + 100 | 600 | 14 | 193 → 193 |

Each phase executes one hundred new-change/restored/stable-changed triples and
waits thirteen seconds before measurement. The separate transition, refusal,
same-file and held-mapping scenarios precede these measured cycles. The
unchanged preceding scrub scenario also passes its four warmup and four
measured full-cost VC1/VR1/offline-view cycles on each architecture.

All ten selected independent artifact oracle invocations pass: two scrub
checks, four VC1/VR1 checks on the new persisted media, and preceding ciphertext,
growth, credential rotation and sealed recovery regressions. All three oracle
sources remain unchanged. An initial default sealed-recovery oracle attempt
used direct-unlock media lacking `next.pass`; its partial extraction and reason
are retained, and the corrected sealed-recovery baseline passes. Both new
guests' eight reports and two references match exact independently constructed
bytes and OpenSSL clean/changed ciphertext digests and reference fingerprints.

Independent source/generated-C and lifetime review checks complete validation
before output, exact 128-byte reference equality, transactional disk/row/bool
commit, bounded two-report and formatting workspaces, closed input descriptors,
offline-only operations and output-error precedence. All 283 preceding
production bodies/constants remain identical, including the publisher, reader,
hashing and KDF. Fixture production sources and all eight merged test bodies
match their explicit transformations; 42 normalized model/production C bodies
match. Both complete utility targets and selected guest programs pass allocation
audits. The independent review found no unresolved correctness or lifetime issue.

Retained evidence is under `logs/storage-scrub-compare-work`: successful and
earlier failed receipts, complete generated C, persisted media, oracle outputs,
final sources, frozen kernel/input receipts, independent review and SHA-256
manifests. The V transport copy changes only its private bootloader-cache path
and established QEMU foreground/task-priority wrapper; workload bodies match
the public controller. Its owned temporary RAM compiler volume is released
before archiving evidence.

These are scoped host and disposable QEMU tests; unrelated desktop, full native,
saved-plan and physical hardware qualification remains separate. Stable input
files and trusted references are required. Comparisons describe historical
scans and provide no new snapshot, provenance/plaintext authentication or repair.
