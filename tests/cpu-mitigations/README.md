# CPU mitigation validation

See [the policy contract and hardware limits](../../docs/x86-cpu-mitigations.md).

`check-policy.py` compiles the actual production C policy under ASan/UBSan,
replacing only the CPUID/RDMSR/WRMSR ports. It checks 12,288 vendor, leaf, subleaf,
and feature combinations, independent MSR capability gates, persistent and
legacy control values, preservation of firmware bits, RFDS with MDS_NO, separate
AMD IBPB/IBRS and architectural SSBD, invalid CPU indices, setup bounds, and an
ineffective MSR write. It allocates and frees its own host policy array.

`check-assembly.py` assembles and links the production x86 macros and thunks as
ELF, then executes their instruction bytes under Rosetta. Only privileged ports
and the final scheduler's DS/ES loads, SWAPGS, and IRETQ have host adapters. The
instruction stream is not rewritten into Mach-O macro syntax. The host C checks
run under ASan/UBSan. The cases cover 1,024 per-CPU flag combinations, control
halves, one-time pending barrier consumption, clearing, all 15 thunk registers,
RSB stack balance, and the actual scheduler epilogue's saved register restoration,
user/kernel CS checks, adjusted error marker, and unchanged memory below the
saved frame. This helper requires macOS/Rosetta and Homebrew LLVM tools.

`check-linked.py` scans the final x86 production ELF for raw indirect CALL/JMP,
verifies the compiler actually uses external thunks, and checks the final
scheduler stub is present. It also covers linked C dependencies and handwritten
assembly, which compiler flags alone would not rewrite.

```sh
python3 tests/cpu-mitigations/check-policy.py
python3 tests/cpu-mitigations/check-assembly.py
python3 tests/cpu-mitigations/check-linked.py build-amd64-kernel/bin/vinix
VINIX_VM_RUNNER_ROOT=/Users/alex/code/vinix \
VINIX_AMD64_KERNEL="$PWD/build-amd64-kernel/bin/vinix" \
python3 tests/cpu-mitigations/run.py --cpu max
```

The guest checks syscall register preservation, periodic timer/signed signal
returns, thread switches, migration across online CPUs, fork/exit/wait, and
retained slab pages across 30,000 further syscalls. It also clears the TLS
segment descriptor currently loaded into DS and ES, forcing the kernel's
recoverable segment-reload faults on the syscall return path. The guest uses
the kernel's existing `/proc` mount; remounting the same procfs view produced a
self-mount ELOOP on both the unchanged baseline and the feature kernel during
initial fixture development. Those diagnostic logs are preserved separately.

Both tracked production architecture builds pass. The capability helper and
assembly helper pass, and the final ELF has no raw indirect CALL/JMP. A GNU CC
14.2 smoke compilation of the production C policy with the GNU mitigation flags
also passes; the full production builds here use Apple Clang 21.

QEMU TCG filters requested `spec-ctrl`, `stibp`, `ssbd`, `md-clear`, and
`arch-capabilities` bits. Tests using `max` and `qemu64` exercise the actual
unsupported-feature fallback and the live retpoline/fence/RSB paths. The host
hardware-port adapters test the supported MSR decisions without advertising
that an emulated CPU implements their effects. Neither test establishes real
transient attack resistance.

`run.py --cpu max --segments` additionally runs the unchanged core suite’s
TLS/LDT/compatibility group, including stale DS on interrupts and scheduler
resumption, signed signal frames with LDT code, forged segment rejection, and
the AMD 32-bit CSTAR refusal path.

Final production-source results:

| Check | Result |
|---|---|
| Tracked x86-64 and AArch64 production builds | PASS |
| Production C policy under ASan/UBSan | PASS, 12,288 capability cases |
| Production assembly and scheduler epilogue adapters | PASS, 1,024 flag/CPU cases and all 15 thunk registers |
| Linked x86 ELF | PASS, 755 thunk branches and zero raw indirect CALL/JMP |
| `--cpu max` guest | PASS, retained Slab 1080 to 1080 KiB |
| `--cpu qemu64` guest | PASS, retained Slab 1064 to 1064 KiB |
| `--cpu max --segments` guest | PASS, unchanged core TLS/LDT/32-bit suite |

The final run logs are `/tmp/vinix-cpu-mitigations-{policy,assembly,linked}.log`
and `/tmp/vinix-cpu-mitigations-amd64-{max,qemu64,segments}-final.log`.
