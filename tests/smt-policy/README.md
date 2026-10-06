# x86 SMT boot policy

`vinix.smt=0` on the kernel command line starts one logical CPU per physical
core. The BSP always remains online as logical CPU zero. The topology comes
from CPUID extended topology leaf 0x1f or 0x0b; package/die bits remain part of
core identity. When neither leaf supplies valid SMT information, disabling SMT
starts only the BSP rather than guessing which CPUs are siblings. Invalid
`vinix.smt=` values also select that restriction. The default and
`vinix.smt=1` keep all firmware-reported CPUs for existing workload compatibility.

This partially addresses SEC13: it is an administrator boot policy, not a
runtime CPU hotplug switch or a complete heterogeneous-CPU topology interface.
Changing the policy requires rebooting. Disabled APs remain parked by Limine.

Run `V=/path/to/v tests/smt-policy/run-host.sh` for production topology/token
checks. After `./scripts/build-amd64.sh --no-userland --no-iso`, run
`python3 tests/smt-policy/run.py` to boot QEMU with one socket, two cores and two
threads per core, first restricted and then enabled, checking the actual
scheduler affinity mask. `VINIX_AMD64_KERNEL` and `VINIX_VM_RUNNER_ROOT` allow
an isolated kernel checkout to use the original checkout's cached boot support.
The independent guest is V in `guestfixture`; CPUID and affinity macros remain
the unmodified native SDK operations. Set `VINIX_V_COMPILER` and `CC_AMD64`
to verified V and musl compilers. The original 39-line C fixture is recoverable
at `3d667aebfe6c35dc78f0f56713c02a40432d86ae:tests/smt-policy/guest.c`.
