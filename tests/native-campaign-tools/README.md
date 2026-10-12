# Native saved allocation campaigns

The 45 saved Python campaign programs are replaced by `campaignhost` and
native V entrypoints beside the retained captures. Their names lose `.py`;
`campaignhost/entries.json` declares every mapping. Frozen commands and source
hashes remain evidence, while newly executed native commands and producers
are recorded separately. Interpreter commands are never executed.

From the repository root:

```sh
tests/native-campaign-tools/run COMMAND ORIGIN --root "$PWD" --state-dir NEW_STATE
tests/alloc-bench/results/2026-10-03-userspace-v6/validation/campaign-complete/useralloc-v6-verify-readiness
```

Use the original arguments at each saved entrypoint. x86 verification accepts
`prepare` or `run KERNEL`; desktop performance takes `STATE SCENARIOS KERNEL`;
the verification collector takes `x86_64` or `aarch64`; production packaging
accepts `--arch amd64|aarch64|both`. Optional `--root` and `--state-dir` isolate
new attempts. Historical missing builder paths, protected failed states,
immutable kernel/libc pins, compile flags, guest deadlines and marker counts
remain meaningful prerequisites. A saved source is not a promise that today's
checkout still contains the private tree from its original execution.

Core and PTY supervisors compile separately to keep their SDK process owners
independent. Every child leader remains reserved through process-group
retirement and the sole reap. Socket probes check complete serial lines,
capture actual QEMU process arguments, and retain shutdown output. Diagnostic
receipts preserve signed emulator exits on successful and failed collections.
Cohorts validate completed prefixes, recheck frozen inputs before each launch,
and record native source and executable identities; changed producers cannot
resume a retained prefix. Existing captures are not overwritten by qualification.

The cold qualification matrix uses native ARM, Rosetta x86 and ARM ASan/UBSan.
It compiles 21 programs per profile and checks retained ARM/x86 correctness,
all three core modes, every missing/duplicate source marker, paging boundary
policies, both core USTAR byte identities, all 168 hot samples, all 24 reviewed
objects, sixteen readiness gates, actual ordered child execution, cohort
resume/failure protection, native signed-status cleanup, real PTY/probe/log
owners, interrupt paths, cached package admission and all four saved desktop
profiles. Shared source, guest, core-VM and desktop-runner regressions run on
each profile. Allocation-checker root selection is compared with its unchanged
shell oracle using a native controlled compiler and copier.

Separate real GNU qualification prepares x86 v3/v4/v6 and ARM v5/v6 roots,
cross-compiles both static core executables, proves diagnostic and original
linker flags produce identical bytes, and independently extracts the completed
core ISO's kernel, init, initramfs and image identity. The full object collector
reviews the four real retained libc builds and the evidence audit checks all
three complete immutable core captures in a private directory. These checks
do not claim a new kernel build, fresh guest allocator execution or a complete
production desktop/userland rebuild.

Immutable originals, build logs, receipts, controlled state directories and V
qualification/review helpers are retained under
`~/.cache/vinix-campaign-tools-native-20261012`. Exact provenance and completed
checks are in `native-translation.json`. Python is never run or used as a
wrapper. This stage retires 140,552 Python bytes in 45 files (1,829 lines);
the repository-wide zero-Python migration remains in progress.
