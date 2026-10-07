/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LOG_HOST_V_CONTRACT_H
#define VINIX_LOG_HOST_V_CONTRACT_H
#include "host_model_v_contract.h"
#define u64 vmh_linux_u64
#include <linux/printk.h>
#include <linux/panic.h>
#include <linux/bug.h>
#include <vinix/printk.h>
#include <vinix/format.h>
#undef u64
typedef va_list vml_native_va;
#if defined(__APPLE__) && defined(__aarch64__)
_Static_assert(sizeof(vml_native_va)==8, "Darwin native va_list pointer");
#elif defined(__aarch64__)
_Static_assert(sizeof(vml_native_va)==32, "AAPCS64 native va_list");
#elif defined(__x86_64__)
_Static_assert(sizeof(vml_native_va)==24, "SysV64 native va_list array");
#endif
struct vml_volatile_scalar { volatile int value; };
_Static_assert(sizeof(struct vml_volatile_scalar)==sizeof(int), "original volatile int width");
_Static_assert(sizeof(struct vinix_linuxkpi_printk_record)==1048, "original record layout");
_Static_assert(offsetof(struct vinix_linuxkpi_printk_record,text)==24, "original record text offset");
_Static_assert(_Alignof(vml_native_va)<=_Alignof(uint64_t), "native captured va_list alignment");
typedef const struct vinix_linuxkpi_printk_record *vml_const_record_p;
void vmh_host_time_advance(vmh_u64);
void *vml_logger_ticks(void *);
void vml_logger_sink(const struct vinix_linuxkpi_printk_record *,void *);
void *vml_logger_produce(void *);
void *vml_logger_flush_thread(void *);
int vml_logger_emit(int,int,const struct dev_printk_info *,const char *,...);
int vml_logger_nested(const char *,...);
void *vml_warn_produce(void *);
#endif
