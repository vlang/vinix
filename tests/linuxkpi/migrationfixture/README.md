The controller stages actual production V migration APIs, their context
validation, the scheduler release helper, central CPU eligibility, parking,
capacity and placement policy, native wake validation, worker binding/routing,
preemption-release boundaries and the real runqueue scanner/link operations.
All 34 selected production bodies remain byte-for-byte identical between the
staged V generation, selected sanitizer translation unit and separate
production-only translation unit. This authenticates host selection; the full
native kernel's generated C is reviewed separately. Host Thread/Process/Local
records deliberately contain only the fields these functions access.

Only CPU/current-task/IRQ/atomic/IPI, queue-lock, ranking and reschedule transport
are modeled, explicitly in V. Modeled dispatch uses the genuine placement
function. These host observations do not prove real CPU sleep/resume, an idle
CPU waking, native lock ownership or retained kernel allocation recovery.
Those require the separate isolated native actor tests.

Cases cover every supported CPU encoding, high-CPU scalar pins, nesting and
corruption boundaries, failed context/domain checks before pin mutation,
IF/preemption/active-task IRQ preservation, conflicting requested affinity,
deferred outer release, same-CPU task independence, binding EBUSY, rejection of
distinct but value-identical Process owners without mutation, and eight
concurrent scheduler observers while the actual APIs change nesting.

The only compiler helper remapping is metadata macros that redirect native
fixed-array bounds helpers to checked V fixture exports, avoiding allocation
from the V runtime's diagnostic formatting. Production-only objects retain the
original unresolved bounds-helper calls. Their strict import allowlist also
accounts for the genuine C99 inline parking reference, aggregate zeroing and
scalar panic branch that remain at O0. These checks do not establish kernel
allocation recovery.

A deterministic lock-acquisition transport publishes a real migration pin via
the actual API between the scanner's early eligibility check and acquisition.
Additional cases publish death or excluding affinity. The genuine final
scanner rejects the candidate after ownership transfers. An explicitly labeled
historical control, derived solely by removing that post-acquisition check,
incorrectly returns it. No blocking hook is added to native production code.

A second deterministic transport publishes a real, valid worker affinity
change after release placement chooses its destination and before the target's
online revalidation load returns. Across all 24 distinct source/old/new CPU
triples, the actual release helper retains one requested-mask snapshot and
finishes without a false panic. Its stale IPI hint grants no dispatch permission:
genuine current placement and eligibility use the newer mask. A labeled
historical release orchestration control removes that snapshot and restores
independent source/scorer/revalidation observations; it fails in all 24 cases.
Empty or offline-only snapshots still fail before state mutation. The hook
never publishes another task's migration pin.

Run `build-support/run-v-tool.sh tests/linuxkpi/migration.v --keep-dir NEW`.
GNU99/GNU11 ASan/UBSan profiles, exact generated-body checks and production-only
freestanding objects keep compiler/runtime evidence separate. Native asynchronous
affinity requests are not Linux's blocking set_cpus_allowed_ptr contract. NMI,
idle/no-current usage, CPU hotplug, I/O mappings and GPU support remain pending.
