The scheduler-preemption, scheduler-QoS, TLB and CPU-mitigation host commands
now launch V directly. Their existing extraction, independent templates,
assertions and hardware adapters remain intact. The CPU command also captures
and audits `nm` in V; no interpreter or environment/descriptor JSON bridge is
needed. Captured text uses strict UTF-8 and universal newlines.

Run `tests/scheduler-preemption/policy`, `tests/scheduler-qos/policy`,
`tests/tlb/policy` or `tests/cpu-mitigations/check-policy` from any directory.
`V` selects the compiler; QoS also honors `VEXE` for its generated fixture.
An allocation-free V constructor records whether the caller supplied `VEXE`
and whether it was empty, before V3 inserts its own compiler path. Child
environments restore that original state, including absent/empty overrides.
The three existing generator overrides and extraction/assembly interfaces are
still available. The fixtures use the platform C compiler and an explicit
private output path. The invoking binary selects ARM or x86 for its children.
Set `VINIX_HOST_POLICY_SANITIZE=1` to instrument generated scheduler/TLB fixtures.
CPU mitigation fixtures always retain their original ASan/UBSan flags.

Qualification runs all original assertions on ARM and x86, instruments both
controllers and generated fixtures with ASan/UBSan, and verifies cold launches
outside the checkout. Temporary owners retire after successful and returned
failed commands. These are host checks; no new kernel build or guest/hardware
execution is established. Guest launchers remain part of the Python inventory.

Additional V-only injection checks cover twelve compiler-failure owners, three
generator failures, VEXE precedence and empty-override cleanup. Successful
generator overrides also run all original assertions. The temporary
qualification driver is `/tmp/vinix-policy-check/qualify.v`.
