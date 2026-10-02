# Initial x86 speculation controls

`python3 tests/speculation-policy/run.py` executes the production C policy on
the host with mocked CPUID and MSR instructions. It checks every combination
of IBRS/IBPB, STIBP, architectural-capability and SSBD advertisement, enhanced
versus legacy IBRS, preservation of firmware controls, and absence of accesses
to unsupported MSRs. This tests policy decisions, not resistance to a side
channel attack.

The x86 kernel builds C and generated V C with retpolines. Handwritten syscall
and interrupt dispatch use a return trampoline too, and SWAPGS paths include
LFENCE. Each CPU independently enables enhanced IBRS, STIBP and SSBD when its
CPUID/MSRs advertise them. Every thread dispatch, including from idle, runs
IBPB when available and fills 32 return-stack entries before restoring state.
There is no application opt-out from these controls.

The baseline remains incomplete: legacy IBRS entry programming, AMD-specific
extended controls, KPTI, BHI, Retbleed, SRSO, MDS/TAA/RFDS and ARM firmware/CPU
workarounds are not implemented by this change. Retpolines alone are not a
complete mitigation on every processor. Linux maintains a much larger CPU and
microcode policy. Feature output reports enabled controls, never a blanket
"not vulnerable" conclusion.

References: [Intel CPUID/MSR enumeration](https://www.intel.com/content/www/us/en/developer/articles/technical/software-security-guidance/technical-documentation/cpuid-enumeration-and-architectural-msrs.html),
[Linux Spectre guidance](https://docs.kernel.org/admin-guide/hw-vuln/spectre.html),
[Linux return-stack guidance](https://docs.kernel.org/admin-guide/hw-vuln/rsb.html).
