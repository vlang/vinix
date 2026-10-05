/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_X86_MITIGATIONS_H
#define VINIX_X86_MITIGATIONS_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
/* Keep the assembly offsets in speculation.h synchronized. */
struct vinix_x86_mitigation_policy {
    uint64_t kernel_control;
    uint64_t user_control;
    uint64_t flags;
    uint64_t reserved;
};
_Static_assert(sizeof(struct vinix_x86_mitigation_policy) == 32, "assembly stride");
_Static_assert(offsetof(struct vinix_x86_mitigation_policy, flags) == 16, "assembly flags");
#define VINIX_SPEC_IBPB    UINT64_C(1)
#define VINIX_SPEC_LEGACY  UINT64_C(2)
#define VINIX_SPEC_EIBRS   UINT64_C(4)
#define VINIX_SPEC_CLEAR   UINT64_C(8)
#define VINIX_SPEC_STIBP   UINT64_C(16)
#define VINIX_SPEC_SSBD    UINT64_C(32)
#define VINIX_SPEC_BHI     UINT64_C(64)
#define VINIX_SPEC_RRSBA   UINT64_C(128)
#define VINIX_SPEC_PENDING UINT64_C(256)
extern struct vinix_x86_mitigation_policy *vinix_x86_mitigation_policies;
bool vinix_x86_mitigations_setup(uint64_t count);
bool vinix_x86_mitigations_initialise(uint64_t number);
#endif
