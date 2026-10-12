/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Compiler metadata only; implementations remain the pinned originals. */
#ifndef VINIX_MEM_ENCRYPT_POLICY_FIXTURE_H
#define VINIX_MEM_ENCRYPT_POLICY_FIXTURE_H
#ifdef VINIX_MEM_ENCRYPT_PAGE_FIRST
#include <asm/pgtable_types.h>
#include <linux/mem_encrypt.h>
#else
#include <linux/mem_encrypt.h>
#include <asm/pgtable_types.h>
#endif

#ifndef CONFIG_ARCH_HAS_MEM_ENCRYPT
#error "original X86 architecture selection is required"
#endif
_Static_assert(IS_ENABLED(CONFIG_ARCH_HAS_MEM_ENCRYPT),
               "original architecture selection is enabled");

#ifdef VINIX_MEM_ENCRYPT_CONFIGURED
#ifndef CONFIG_AMD_MEM_ENCRYPT
#error "configured-encryption control requires the original AMD branch"
#endif
#ifndef CONFIG_X86_MEM_ENCRYPT
#error "configured-encryption control requires original X86 initialization"
#endif
#ifdef sme_me_mask
#error "configured encryption must retain its original external mask"
#endif
#ifdef sev_status
#error "configured encryption must retain its original external state"
#endif
_Static_assert(__builtin_types_compatible_p(__typeof__(sme_me_mask), u64),
               "original configured SME type");
_Static_assert(__builtin_types_compatible_p(__typeof__(sev_status), u64),
               "original configured SEV type");
/* Relocations retain genuine unresolved runtime ownership; no success stub. */
u64 *const vinix_original_sme_reference = &sme_me_mask;
u64 *const vinix_original_sev_reference = &sev_status;
void (*const vinix_original_mem_init_reference)(void) = mem_encrypt_init;
bool (*const vinix_original_cc_reference)(enum cc_attr) = cc_platform_has;
#else
#if defined(CONFIG_AMD_MEM_ENCRYPT) || defined(CONFIG_X86_MEM_ENCRYPT) || \
    defined(CONFIG_ARCH_HAS_CC_PLATFORM)
#error "native memory encryption services must remain disabled"
#endif
_Static_assert(sme_me_mask == 0ULL && sev_status == 0ULL,
               "original disabled encryption masks");
_Static_assert(__builtin_types_compatible_p(__typeof__(sme_me_mask), unsigned long long),
               "original disabled SME mask type");
_Static_assert(__builtin_types_compatible_p(__typeof__(sev_status), unsigned long long),
               "original disabled SEV status type");
_Static_assert(_PAGE_ENC == 0 && _ENC == 0,
               "original disabled page-table encryption mask");
_Static_assert(__sme_set(0ULL) == 0ULL && __sme_clr(~0ULL) == ~0ULL &&
               __sme_set(0x8000000100000000ULL) == 0x8000000100000000ULL,
               "original disabled address mask identity");
_Static_assert(__builtin_types_compatible_p(__typeof__(__sme_set((u8)1)), u8) &&
               __builtin_types_compatible_p(__typeof__(__sme_clr((u32)1)), u32),
               "original disabled mask preserves operand type");
const unsigned long long vinix_original_disabled_masks[2] = {sme_me_mask, sev_status};
#endif
#endif
