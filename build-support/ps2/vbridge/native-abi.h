/* SPDX-License-Identifier: MIT */
/* Native declarations and layout checks only. Helper algorithms are V. */
#ifndef VINIX_PS2_NATIVE_ABI_H
#define VINIX_PS2_NATIVE_ABI_H
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "ps2.h"
#include "elf.h"

typedef const unsigned char ps2_const_byte;
typedef const char ps2_const_char;
typedef const Elf32_Ehdr ps2_const_elfheader;
struct ps2_runtime_construction { void *storage; const char *message; };

/* EE contains native C++ containers. Copy only these scalar fields through
 * their checked byte offsets; never alias that C++ object as a C structure. */
enum {
    VINIX_PS2_EE_R29 = 616,
    VINIX_PS2_EE_PC = 716,
    VINIX_PS2_EE_NEXT_PC = 720,
    VINIX_PS2_EE_STATUS = 812,
    VINIX_PS2_RUNTIME_ERROR_SIZE = 16
};

#ifdef __APPLE__
#define VINIX_PS2_EH_SYMBOL(s) "_" s
#else
#define VINIX_PS2_EH_SYMBOL(s) s
#endif
#ifdef __cplusplus
#include "ee/ee_def.hpp"
#include <stdexcept>
static_assert(sizeof(void *) == 8 && sizeof(size_t) == 8 && sizeof(long) == 8, "native pointer and file widths");
static_assert(sizeof(int) == 4 && sizeof(unsigned) == 4, "native control words");
static_assert(sizeof(std::runtime_error) == VINIX_PS2_RUNTIME_ERROR_SIZE, "native runtime_error storage");
static_assert(alignof(std::runtime_error) == 8, "native runtime_error alignment");
static_assert(offsetof(ee_state, r) + 29 * sizeof(uint128_t) == VINIX_PS2_EE_R29, "EE r29 low word");
static_assert(offsetof(ee_state, pc) == VINIX_PS2_EE_PC, "EE PC");
static_assert(offsetof(ee_state, next_pc) == VINIX_PS2_EE_NEXT_PC, "EE next PC");
static_assert(offsetof(ee_state, status) == VINIX_PS2_EE_STATUS, "EE COP0 status");
extern "C" {
#else
_Static_assert(sizeof(void *) == 8 && sizeof(size_t) == 8 && sizeof(long) == 8, "native pointer and file widths");
_Static_assert(sizeof(int) == 4 && sizeof(unsigned) == 4, "native control words");
_Static_assert(sizeof(struct ps2_runtime_construction) == 16 &&
               offsetof(struct ps2_runtime_construction, storage) == 0 &&
               offsetof(struct ps2_runtime_construction, message) == 8,
               "stack exception construction record");
_Static_assert(sizeof(Elf32_Ehdr) == 52 && sizeof(Elf32_Phdr) == 32, "MIPS ELF records");
_Static_assert(sizeof(((struct iop_state *)0)->pc) == 4 && sizeof(((struct iop_state *)0)->cop0_r[0]) == 4, "IOP words");
_Static_assert(sizeof(((struct ps2_state *)0)->ee_cycles) == 4 && sizeof(((struct ps2_state *)0)->timescale) == 4, "cycle words");
#endif

int vinix_ps2_unwind_scope(void *, int (*)(void *), void (*)(void *));
void *vinix_ps2_allocate_exception(size_t) __asm__(VINIX_PS2_EH_SYMBOL("__cxa_allocate_exception"));
void vinix_ps2_free_exception(void *) __asm__(VINIX_PS2_EH_SYMBOL("__cxa_free_exception"));
void vinix_ps2_throw_exception(void *, void *, void (*)(void *)) __asm__(VINIX_PS2_EH_SYMBOL("__cxa_throw"));
void vinix_ps2_runtime_ctor(void *, const char *) __asm__(VINIX_PS2_EH_SYMBOL("_ZNSt13runtime_errorC1EPKc"));
void vinix_ps2_runtime_dtor(void *) __asm__(VINIX_PS2_EH_SYMBOL("_ZNSt13runtime_errorD1Ev"));
extern const unsigned char vinix_ps2_runtime_type[] __asm__(VINIX_PS2_EH_SYMBOL("_ZTISt13runtime_error"));

#ifndef VINIX_V_RUNTIME
int vinix_ps2_file_size(FILE *, size_t *);
void vinix_ps2_check_elf(const unsigned char *, size_t, Elf32_Ehdr *);
void vinix_ps2_load_baremetal(struct ps2_state *, const unsigned char *, const Elf32_Ehdr *);
void vinix_ps2_tick(struct ps2_state *);
void vinix_ps2_boot_bios(struct ps2_state *, const char *, size_t);
#endif
#ifdef __cplusplus
}
#endif
#endif
