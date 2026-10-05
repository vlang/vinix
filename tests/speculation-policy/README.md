# Initial x86 speculation controls

`python3 tests/speculation-policy/run.py` executes the original helper's V
implementation through independent C callers under ASan/UBSan, with mocked
CPUID and MSR instructions. The active per-CPU policy is tested separately in
[`tests/cpu-mitigations`](../cpu-mitigations/README.md). This helper checks every combination
of IBRS/IBPB, STIBP, architectural-capability, SSBD and BHI control
advertisement, enhanced versus legacy IBRS, BHI_NO, preservation of firmware
controls, and absence of accesses to unsupported CPUID leaves, subleaves and
MSRs. The 6,144 cases include BHI-only control advertisement and unadvertised
architectural-capability values. This tests policy decisions, not resistance
to a side channel attack.

The x86 kernel builds C and generated V C with retpolines. Handwritten syscall
and interrupt dispatch use a return trampoline too, and SWAPGS paths include
LFENCE. Each CPU independently enables enhanced IBRS, STIBP and SSBD when its
CPUID/MSRs advertise them. Every thread dispatch, including from idle, runs
IBPB when available and fills 32 return-stack entries before restoring state.
There is no application opt-out from these controls.

Each CPU also enables IA32_SPEC_CTRL.BHI_DIS_S (bit 10) when CPUID leaf 7,
subleaf 2, EDX bit 4 advertises that control. It checks both the basic-leaf
maximum and leaf 7's subleaf maximum before querying subleaf 2. An advertised
IA32_ARCH_CAPABILITIES.BHI_NO (bit 20) makes setting this control unnecessary;
capability data without CPUID ARCH_CAPABILITIES is ignored. BHI control alone
enumerates IA32_SPEC_CTRL support, independently of IBRS, STIBP and SSBD. All
existing firmware MSR bits are preserved, including BHI_DIS_S. CPU output
reports the control selected by Vinix and the BHI_NO enumeration separately.
This closes the supported hardware BHI-control gap; it supplies no software
branch-history clearing for older CPUs or intra-mode BHI mitigation.

The baseline remains incomplete: legacy IBRS entry programming, AMD-specific
extended controls, KPTI, BHI software sequences, Retbleed, SRSO, MDS/TAA/RFDS
and ARM firmware/CPU workarounds are not implemented by this change.
Retpolines alone are not a complete mitigation on every processor.
Linux maintains a much larger CPU and
microcode policy. Feature output reports enabled controls, never a blanket
"not vulnerable" conclusion.

References: [Intel CPUID/MSR enumeration](https://www.intel.com/content/www/us/en/developer/articles/technical/software-security-guidance/technical-documentation/cpuid-enumeration-and-architectural-msrs.html),
[Linux Spectre guidance](https://docs.kernel.org/admin-guide/hw-vuln/spectre.html),
[Intel BHI guidance and hardware-control enumeration](https://www.intel.com/content/www/us/en/developer/articles/technical/software-security-guidance/technical-documentation/branch-history-injection.html),
[Linux return-stack guidance](https://docs.kernel.org/admin-guide/hw-vuln/rsb.html).
