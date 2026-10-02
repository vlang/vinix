/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "speculation.h"

/* Intel's architectural CPUID/MSR enumeration, also used by AMD CPUs that
 * advertise the same interface. Never access an unadvertised MSR. */
#define CPUID_IBRS_IBPB (UINT32_C(1) << 26)
#define CPUID_STIBP (UINT32_C(1) << 27)
#define CPUID_ARCH_CAPS (UINT32_C(1) << 29)
#define CPUID_SSBD (UINT32_C(1) << 31)
#define ARCH_CAP_IBRS_ALL (UINT64_C(1) << 1)
#define SPEC_IBRS UINT64_C(1)
#define SPEC_STIBP UINT64_C(2)
#define SPEC_SSBD UINT64_C(4)

uint64_t vinix_speculation_select(uint32_t edx, uint64_t arch_caps)
{
    uint64_t policy = 0;
    if (edx & CPUID_IBRS_IBPB) {
        policy |= VINIX_SPEC_IBPB;
        /* Enhanced IBRS may remain enabled across privilege transitions.
         * Legacy IBRS needs entry programming and is not substituted here. */
        if ((edx & CPUID_ARCH_CAPS) && (arch_caps & ARCH_CAP_IBRS_ALL))
            policy |= SPEC_IBRS;
    }
    if (edx & CPUID_STIBP) policy |= SPEC_STIBP;
    if (edx & CPUID_SSBD) policy |= SPEC_SSBD;
    return policy;
}

#if defined(__x86_64__)
#if defined(VINIX_SPECULATION_TEST)
extern uint32_t vinix_spec_test_leaf7(void);
extern uint64_t vinix_spec_test_rdmsr(uint32_t msr);
extern void vinix_spec_test_wrmsr(uint32_t msr, uint64_t value);
#define leaf7 vinix_spec_test_leaf7
#define read_msr vinix_spec_test_rdmsr
#define write_msr vinix_spec_test_wrmsr
#else
static uint32_t leaf7(void)
{
    uint32_t a = 0, b, c = 0, d;
    __asm__ volatile("cpuid" : "+a"(a), "=b"(b), "+c"(c), "=d"(d));
    if (a < 7) return 0;
    a = 7; c = 0;
    __asm__ volatile("cpuid" : "+a"(a), "=b"(b), "+c"(c), "=d"(d));
    return d;
}
static uint64_t read_msr(uint32_t msr)
{
    uint32_t a, d;
    __asm__ volatile("rdmsr" : "=a"(a), "=d"(d) : "c"(msr) : "memory");
    return ((uint64_t)d << 32) | a;
}
static void write_msr(uint32_t msr, uint64_t value)
{
    __asm__ volatile("wrmsr" : : "c"(msr), "a"((uint32_t)value),
                     "d"((uint32_t)(value >> 32)) : "memory");
}
#endif

uint64_t vinix_speculation_init(uint64_t cpu_number)
{
    uint32_t edx = leaf7();
    uint64_t caps = (edx & CPUID_ARCH_CAPS) ? read_msr(0x10a) : 0;
    uint64_t policy = vinix_speculation_select(edx, caps);
    if (edx & (CPUID_IBRS_IBPB | CPUID_STIBP | CPUID_SSBD)) {
        uint64_t old = read_msr(0x48);
        /* Preserve unrelated firmware controls; never clear a protection. */
        write_msr(0x48, old | (policy & UINT64_C(7)));
    }
#if !defined(VINIX_SPECULATION_TEST)
    extern int kprintf(const char *, ...);
    kprintf("security: CPU %llu speculation retpoline=1 eibrs=%u ibpb=%u stibp=%u ssbd=%u\n",
            (unsigned long long)cpu_number, (unsigned)!!(policy & SPEC_IBRS),
            (unsigned)!!(policy & VINIX_SPEC_IBPB), (unsigned)!!(policy & SPEC_STIBP),
            (unsigned)!!(policy & SPEC_SSBD));
#else
    (void)cpu_number;
#endif
    return policy;
}

void vinix_speculation_switch(uint64_t policy)
{
    if (policy & VINIX_SPEC_IBPB) write_msr(0x49, 1);
}
#else
uint64_t vinix_speculation_init(uint64_t cpu_number) { (void)cpu_number; return 0; }
void vinix_speculation_switch(uint64_t policy) { (void)policy; }
#endif
