/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "x86_mitigations.h"
#if defined(__x86_64__)
#include <stddef.h>
#include <stdlib.h>

/* These records and their one boot allocation live as long as the CPUs.
 * No allocation, lock, or C call is made on entry/return/switch paths. */
struct vinix_x86_mitigation_policy *vinix_x86_mitigation_policies;
static uint64_t mitigation_cpu_count;
_Static_assert(sizeof(struct vinix_x86_mitigation_policy) == 32, "assembly stride");
_Static_assert(offsetof(struct vinix_x86_mitigation_policy, flags) == 16, "assembly flags");

struct mitigation_caps {
    uint32_t intel, amd, leaf7_edx, leaf7_2_edx, amd_ebx;
    uint64_t arch_caps;
};

static void mitigation_cpuid(uint32_t leaf, uint32_t subleaf,
                             uint32_t *a, uint32_t *b, uint32_t *c, uint32_t *d) {
    __asm__ volatile("cpuid" : "=a"(*a), "=b"(*b), "=c"(*c), "=d"(*d)
                     : "a"(leaf), "c"(subleaf));
}
static uint64_t mitigation_rdmsr(uint32_t msr) {
    uint32_t a, d;
    __asm__ volatile("rdmsr" : "=a"(a), "=d"(d) : "c"(msr) : "memory");
    return ((uint64_t)d << 32) | a;
}
static void mitigation_wrmsr(uint32_t msr, uint64_t value) {
    __asm__ volatile("wrmsr" :: "c"(msr), "a"((uint32_t)value),
                     "d"((uint32_t)(value >> 32)) : "memory");
}

static struct mitigation_caps mitigation_capabilities(void) {
    struct mitigation_caps caps = {0};
    uint32_t a, b, c, d, max_leaf;
    mitigation_cpuid(0, 0, &max_leaf, &b, &c, &d);
    caps.intel = b == 0x756e6547 && d == 0x49656e69 && c == 0x6c65746e;
    caps.amd = b == 0x68747541 && d == 0x69746e65 && c == 0x444d4163;
    if (max_leaf >= 7) {
        mitigation_cpuid(7, 0, &a, &b, &c, &d);
        caps.leaf7_edx = d;
        if (a >= 2) {
            mitigation_cpuid(7, 2, &a, &b, &c, &d);
            caps.leaf7_2_edx = d;
        }
        /* ARCH_CAPABILITIES is only read when its MSR is enumerated. */
        if (caps.intel && (caps.leaf7_edx & (UINT32_C(1) << 29)))
            caps.arch_caps = mitigation_rdmsr(0x10a);
    }
    if (caps.amd) {
        mitigation_cpuid(0x80000000, 0, &a, &b, &c, &d);
        if (a >= 0x80000008) {
            mitigation_cpuid(0x80000008, 0, &a, &b, &c, &d);
            caps.amd_ebx = b;
        }
    }
    return caps;
}

/* Select only controls explicitly enumerated by this logical CPU. An
 * unfamiliar vendor does not inherit Intel/AMD MSR semantics. */
static struct vinix_x86_mitigation_policy mitigation_select(struct mitigation_caps caps) {
    struct vinix_x86_mitigation_policy policy = {0};
    bool ibrs = false, enhanced = false, stibp = false, ssbd = false;
    if (caps.intel) {
        ibrs = (caps.leaf7_edx & (UINT32_C(1) << 26)) != 0;
        enhanced = ibrs && (caps.arch_caps & (UINT64_C(1) << 1));
        stibp = (caps.leaf7_edx & (UINT32_C(1) << 27)) != 0;
        ssbd = (caps.leaf7_edx & (UINT32_C(1) << 31)) != 0;
        if (ibrs) policy.flags |= VINIX_SPEC_IBPB;
        if (caps.leaf7_2_edx & (UINT32_C(1) << 4)) {
            policy.user_control |= UINT64_C(1) << 10;
            policy.flags |= VINIX_SPEC_BHI;
        }
        if (caps.leaf7_2_edx & (UINT32_C(1) << 2)) {
            policy.user_control |= UINT64_C(1) << 6;
            policy.flags |= VINIX_SPEC_RRSBA;
        }
        /* MD_CLEAR covers MDS and current firmware's documented buffers.
         * RFDS_CLEAR independently requires VERW, even on MDS_NO parts. */
        if ((caps.leaf7_edx & (UINT32_C(1) << 10)) ||
            (caps.arch_caps & (UINT64_C(1) << 28)))
            policy.flags |= VINIX_SPEC_CLEAR;
    } else if (caps.amd) {
        ibrs = (caps.amd_ebx & (UINT32_C(1) << 14)) != 0;
        enhanced = ibrs && (caps.amd_ebx & (UINT32_C(1) << 16));
        stibp = (caps.amd_ebx & (UINT32_C(1) << 15)) != 0;
        /* AMD's architectural SSBD uses SPEC_CTRL. VIRT_SSBD and the
         * older family-specific LS_CFG mechanism are different MSRs. */
        ssbd = (caps.amd_ebx & (UINT32_C(1) << 24)) != 0;
        if (caps.amd_ebx & (UINT32_C(1) << 12)) policy.flags |= VINIX_SPEC_IBPB;
    }
    if (stibp) {
        policy.user_control |= UINT64_C(1) << 1;
        policy.flags |= VINIX_SPEC_STIBP;
    }
    if (ssbd) {
        policy.user_control |= UINT64_C(1) << 2;
        policy.flags |= VINIX_SPEC_SSBD;
    }
    if (enhanced) {
        policy.user_control |= UINT64_C(1) << 0;
        policy.flags |= VINIX_SPEC_EIBRS;
    } else if (ibrs) {
        policy.flags |= VINIX_SPEC_LEGACY;
    }
    policy.kernel_control = policy.user_control | (ibrs ? UINT64_C(1) : 0);
    if (policy.flags & VINIX_SPEC_IBPB) policy.flags |= VINIX_SPEC_PENDING;
    return policy;
}

bool vinix_x86_mitigations_setup(uint64_t count) {
    if (!count || count > SIZE_MAX / sizeof(*vinix_x86_mitigation_policies)
        || vinix_x86_mitigation_policies) return false;
    vinix_x86_mitigation_policies = calloc((size_t)count, sizeof(*vinix_x86_mitigation_policies));
    if (!vinix_x86_mitigation_policies) return false;
    mitigation_cpu_count = count;
    return true;
}

bool vinix_x86_mitigations_initialise(uint64_t number) {
    if (number >= mitigation_cpu_count) return false;
    struct mitigation_caps caps = mitigation_capabilities();
    struct vinix_x86_mitigation_policy policy = mitigation_select(caps);
    uint64_t requested = policy.kernel_control;
    if (requested) {
        uint64_t original = mitigation_rdmsr(0x48);
        policy.kernel_control |= original;
        policy.user_control |= original;
        mitigation_wrmsr(0x48, policy.kernel_control);
        if ((mitigation_rdmsr(0x48) & requested) != requested) return false;
    }
    vinix_x86_mitigation_policies[number] = policy;
    extern int kprintf(const char *, ...);
    kprintf("security: x86 mitigation CPU %llu flags=0x%llx control=0x%llx cpuid7=0x%x cpuid7.2=0x%x amd=0x%x arch=0x%llx\n",
            (unsigned long long)number, (unsigned long long)(policy.flags & ~VINIX_SPEC_PENDING),
            (unsigned long long)requested, caps.leaf7_edx, caps.leaf7_2_edx,
            caps.amd_ebx, (unsigned long long)caps.arch_caps);
    return true;
}
#endif
