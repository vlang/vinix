# x86 CPU speculation controls

This implements part of SEC11 from the OpenBSD comparison. It adds CPU-local
architectural controls and retpolines; it does not establish that a CPU is
unaffected by every transient execution vulnerability. Real Intel/AMD hardware,
its firmware, and its microcode revision still need validation.

The policy is selected independently on every online logical CPU before it can
run userspace. An unknown vendor gets no vendor-specific MSR programming.
Unenumerated MSRs are never read or written. Requested SPEC_CTRL bits must read
back as enabled; an enumerated but ineffective control fails CPU initialization.
Existing firmware control bits are preserved.

## Hardware capability matrix

| CPU capability | Programmed control or boundary action |
|---|---|
| Intel CPUID.7.0:EDX[26] | Legacy IBRS on every user entry, unless enhanced IBRS is enumerated; IBPB after a thread switch. |
| Intel ARCH_CAPABILITIES.IBRS_ALL plus IBRS | Enable IBRS once and retain it in kernel and userspace. |
| AMD CPUID.80000008:EBX[14], [16] | Legacy IBRS, or persistent IBRS when both support and always-on are enumerated. |
| AMD CPUID.80000008:EBX[12] | IBPB after a thread switch, independently of AMD IBRS. |
| Intel CPUID.7.0:EDX[27]; AMD CPUID.80000008:EBX[15] | Persistent STIBP. |
| Intel CPUID.7.0:EDX[31]; AMD CPUID.80000008:EBX[24] | Persistent architectural SSBD. AMD VIRT_SSBD and older LS_CFG controls are not substituted. |
| Intel CPUID.7.2:EDX[4], [2] | Persistent BHI_DIS_S and RRSBA_DIS_S respectively. Subleaf 2 is read only when supported. |
| Intel CPUID.7.0:EDX[10] or ARCH_CAPABILITIES.RFDS_CLEAR | VERW immediately before a userspace return. RFDS clearing is retained even when MDS_NO is set. |
| No applicable capability | No speculative-control MSR or mitigation VERW is executed; compiler retpolines, entry fences, and RSB overwrite remain active. |

ARCH_CAPABILITIES is read only for Intel CPUs that enumerate CPUID.7.0:EDX[29].
The kernel does not interpret absent enumeration as proof that the corresponding
vulnerability exists, or that it does not exist. This matrix describes available
controls rather than a complete family/model/stepping vulnerability database.

## Entry, switch, and return

Both SYSCALL entry points fence SWAPGS before accessing the thread through GS.
Interrupt entry fences the join of the conditional SWAPGS paths. Thirty-two
forward CALLs overwrite RSB predictions with addresses in PAUSE/LFENCE loops
before the first user-entry C call, and on an actual context switch. The
scheduler performs the overwrite on its original stack, before loading RSP
from the saved Thread frame. No stack write occurs below that frame.
Every entry path fences after the complete conditional policy before its first
C call, so speculatively skipping a capability or user-CS gate cannot bypass
that ordering point.

Each logical CPU has a boot-owned 32-byte policy record. Its pending IBPB bit
starts set where IBPB is supported. Every actual thread selection sets it again,
including selection of a thread stopped inside a syscall. The next user return
consumes it. This also covers a transition from an idle CPU, process replacement
by exec, and CPU migration; ordinary syscalls by the same running thread do not
issue an extra IBPB. No process pointer, PID, or reclaimed CR3 value is retained
as a security-domain identity.

Legacy IBRS stays enabled through handlers, signal processing, and potentially
faulting DS/ES restores. Only after both segment restores succeed does the return
path load the user control value. It then puts the CPU's immutable clearing
capability in the consumed error-code slot. Kernel returns explicitly zero that
slot. After all general registers are restored, the exit tests the slot and
executes VERW if required. IRETQ or SYSRETQ restores the flags changed by that
test. SYSCALL subsequently loads only the user's saved RSP from the thread; this
is a user-known stack value, not additional kernel data processing.

All compiler-generated x86 indirect calls and jumps use external retpoline
thunks, including the compiler runtime and enabled compatibility C sources.
Clang uses `-mretpoline-external-thunk`; GNU CC uses the compatible
`-mindirect-branch=thunk-extern -mindirect-branch-register` options. Handwritten
syscall/interrupt dispatches and the idle tail jump use the same thunks. The
user-controlled syscall-table bounds check is followed by LFENCE. This does not
harden every bounds check or data dependency elsewhere in the kernel.

The entry/return/switch paths allocate nothing and acquire no new lock. The
policy array is allocated once for the firmware CPU count and retained for the
boot lifetime. CPU hotplug, resume after firmware changes, and late microcode
updates must re-evaluate the policy before an affected CPU resumes userspace;
those lifecycles are not implemented here.

## Remaining coverage

- User page tables still contain the kernel higher half. KPTI and Meltdown/RDCL
  isolation remain missing on affected CPUs.
- Software BHB clearing is absent when BHI_DIS_S is unavailable. User-entry
  RSB isolation also relies on SMEP where it is enumerated and enabled by CPU
  initialization; generic RSB overwrite is not a replacement for every
  processor-specific predictor requirement.
- Ordinary RET instructions are not compiler-hardened; kernel CET/IBT is not
  enabled. Retpoline and a generic 32-entry RSB overwrite do not cover every
  processor's return-prediction behavior, Retbleed, AMD SRSO/TSA, or Intel ITS.
  Model-specific workarounds, updated microcode checks, RSB underflow handling,
  and affected-hardware attack tests remain required.
- Intel CPUs with old microcode that lacks MD_CLEAR/RFDS_CLEAR do not gain
  OpenBSD's model-specific MDS clearing sequences. The absence of a control
  does not produce an enabled-mitigation report.
- Vinix's VMX guest entry/exit paths in `kernel/c/vmx.c` have no corresponding
  RSB, predictor-domain, or VERW transitions. This change does not claim guest
  isolation from transient attacks or handle guest SPEC_CTRL virtualization.
- NMI and machine-check entry still use the existing CS-based interrupt path.
  They do not independently repair GS or restore legacy IBRS if they interrupt
  the final exit window. Those asynchronous entry cases remain outside this
  policy's guarantees.
- Kernel-to-idle transitions do not clear buffers before HLT. Legacy IBRS can
  stay enabled during idle and affect an SMT sibling's performance. The
  existing default SMT restriction remains relevant to shared-core exposure;
  persistent STIBP alone does not establish complete sibling isolation.
- Mitigation latency has not been measured on affected hardware. Emulator
  register/ABI tests do not model the transient attacks or MSR control cost.

## Sources

The source comparison used OpenBSD-current
`3ce1f3f79392ae4d60ce67bea5835d517caaa2ca`, particularly
[`replacemeltdown()` and `replacemds()`](https://github.com/openbsd/src/blob/3ce1f3f79392ae4d60ce67bea5835d517caaa2ca/sys/arch/amd64/amd64/cpu.c),
[`locore.S`](https://github.com/openbsd/src/blob/3ce1f3f79392ae4d60ce67bea5835d517caaa2ca/sys/arch/amd64/amd64/locore.S),
and [`specialreg.h`](https://github.com/openbsd/src/blob/3ce1f3f79392ae4d60ce67bea5835d517caaa2ca/sys/arch/amd64/include/specialreg.h).
Architectural control gates follow Intel's
[CPUID and MSR enumeration](https://www.intel.com/content/www/us/en/developer/articles/technical/software-security-guidance/technical-documentation/cpuid-enumeration-and-architectural-msrs.html)
and AMD's [AMD64 system programming manual](https://www.amd.com/content/dam/amd/en/documents/processor-tech-docs/programmer-references/24593.pdf).
The entry rewrite requirement and RSB sequence are described in Intel's
[IBRS guidance](https://www.intel.com/content/www/us/en/developer/articles/technical/software-security-guidance/technical-documentation/indirect-branch-restricted-speculation.html).
Late register clearing follows Intel's
[RFDS guidance](https://www.intel.com/content/www/us/en/developer/articles/technical/software-security-guidance/advisory-guidance/register-file-data-sampling.html).
The coverage limits include Intel's
[ITS guidance](https://www.intel.com/content/www/us/en/developer/articles/technical/software-security-guidance/advisory-guidance/indirect-target-selection.html)
and AMD's [return-address bulletin](https://www.amd.com/en/resources/product-security/bulletin/amd-sb-7005.html).
