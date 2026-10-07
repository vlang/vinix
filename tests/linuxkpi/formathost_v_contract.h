/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_FORMAT_HOST_V_CONTRACT_H
#define VINIX_FORMAT_HOST_V_CONTRACT_H
#include "host_model_v_contract.h"
#include "varargs_abi.h"
#define u64 vmh_linux_u64
#include <vinix/format.h>
#include <linux/ioport.h>
#include <linux/printk.h>
#undef u64
typedef va_list vmf_native_va;
#if defined(__APPLE__) && defined(__aarch64__)
_Static_assert(sizeof(vmf_native_va)==8, "Darwin native va_list pointer");
#elif defined(__aarch64__)
_Static_assert(sizeof(vmf_native_va)==32, "AAPCS64 native va_list");
#elif defined(__x86_64__)
_Static_assert(sizeof(vmf_native_va)==24, "SysV64 native va_list array");
#endif
_Static_assert(_Alignof(vmf_native_va)<=_Alignof(uint64_t), "native va_list copy alignment");
typedef long long vmf_sll;
typedef unsigned long long vmf_ull;
#ifdef __APPLE__
extern int vmf_libc_vsnprintf(char *,size_t,const char *,va_list) __asm__("_vsnprintf");
#else
extern int vmf_libc_vsnprintf(char *,size_t,const char *,va_list) __asm__("vsnprintf");
#endif
int vkr_format_entry(char *,size_t,char *,void *,unsigned int *);
void vmf_golden_bytes(const char *,size_t,const char *,...);
void vmf_nested(const char *,...);
int vmf_metadata(char *,size_t,unsigned int *,const char *,...);
void vmf_nested_invalid(const char *,...);
void vmf_public_va(const char *,...);
void vmf_libc(const char *,...);
void *vmf_key_reader(void *);
#endif
