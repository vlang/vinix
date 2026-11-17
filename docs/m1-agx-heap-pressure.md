# G13 allocation pressure preserves pending ranges

G13's private and GPU-read-only heaps now return allocation failure when no
range fits, without collecting pending releases. Previously a failed or skipped
firmware-cache barrier could be followed by implicit full GC inside allocation,
allowing a pending address to be reused. The packaged Asahi allocator returns
placement failure; its manager explicitly collects captured prefixes after its
cache gates succeed.

A construction-time scalar selects this policy for the two firmware-private
classes. Generic heaps retain their pressure retry; shared classes retain
immediate release. The early failure precedes metadata mutation and uses the
existing deferred heap unlock. The buffer allocator returns its newly reserved
physical pages on failure. Independent review found no lifetime or locking
blocker. No new allocation or owning object is added.

Offline validation passed:

- The actual predecessor's allocator and manager constructor selections fail
  the unacknowledged-reuse host assertion. The regression uses production heap,
  channel, cache-barrier and buffer-allocation control flow with transport and
  physical-memory stubs; it does not execute native firmware.
- ASan/UBSan with `-gc none -manualfree` and fake-stack detection passes 128
  cases across both heaps and supported ABIs, two FIFO release orders, strict
  thresholds, immediate/delayed acknowledgement, failed doorbells, timeout,
  device/fault transitions and full/corrupt rings. Repeated exhaustion preserves
  pending records, byte counts and live addresses. Explicit collection enables
  only eligible reuse. All 336 physical-backing reservations unwind before any
  page-table publication. Generic pressure retry remains intact.
- Six compiled negatives reject the original behavior, either wrong class
  selection, missing/inverted guard and wrong constructor policy. Six C-checker
  mutations are rejected, including a changed temporary alias. All 68 focused
  test files pass, together with the sanitized G13 failure suite, 4,320 heap
  release-policy cases and 20,480 mixed policy/reuse/FIFO steps.
- Both isolated native builds pass. ARM C verifies exactly the pressure guard,
  stack-only policy constructor/default and two manager selections. Fourteen
  heap ownership, backing, barrier and teardown bodies match the predecessor
  after resolving strings and consistently renaming numbered return/array
  temporaries. The original strict x86 checker passes whole-C comparison after
  its existing discard-variable path-hash normalization.
- Allocation sites/source counts remain ARM 379 / 834 and x86 289 / 813.
  Per-file/per-kind counts and existing allowance failures are unchanged;
  no allowance was edited.

Whole-driver audit: **not_equivalent** against packaged Asahi
`bed544bdf93a496ebf70ba180923bab12b6e01cf`. This closes the allocation-pressure
bypass only. Explicit map-failure rollback and eager job/queue/render-buffer
teardown still collect outside the threshold helper. Backing/accounting,
modern UAPI/Mesa integration, remaining stage backing/event destruction,
firmware/cache lifecycle, timestamps, fences/timelines, wire defaults, topology,
power/reset and native performance remain different or unqualified. Host
sanitizers do not establish native slab rates or full driver parity.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-heap-pressure-20261117/`.
Baseline revision: `35958c9d5c3c483f40aa3af77e8e864ca88c5196`, with only the
allocator and GPU manager overlaid in the private kernel worktree. The complete
bundle preserves source snapshots, binaries, C, native input inventories,
baseline inputs, negatives, audit and review. Development diagnostics include
the host page-size name collision, initial C temporary-number differences and
an initial native-runner termination without a saved build log; both final
architecture builds have complete passing logs. Compiler-cache reclamation
receipts verify committed archive hashes and original complete bundles before
removing excluded cache entries. Canonical evidence and archives are retained.
The original inventory checker verifies the bundle and full archive restoration;
`completion.txt` binds its sources and reports to the commit. Raw results stay
outside Git.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `257f5f95ff6c764197f36964a791aa131e6a3e63a6b6ab273d6e2ba201f9afaf` |
| `bundle.tar.gz` | `bfb29aee37e1df71f45c1f603dc892c76e2563dc6b85e188ae8263fc5061c44c` |
| `bundle/vinix-aarch64` | `990eef6b3aa314d10a1bbc76cdbd32469047b0504a45656fb0924712b2dcf2a5` |
| `bundle/vinix-x86_64` | `36715dc892b044f340474bdb7bc04a03d06b6c0801c65c92dd51972751852b92` |
| `bundle/blob-aarch64.c` | `aca135a2c7946a35c2c7c7c136c8eb2e943dad6648b9c515f5cb7a889bec22af` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
