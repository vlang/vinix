/* SPDX-License-Identifier: BSD-2-Clause */
#ifndef VINIX_QEMU_CORE_INT_ORACLE_NATIVE_ABI_H
#define VINIX_QEMU_CORE_INT_ORACLE_NATIVE_ABI_H
#include <intfixture_v_contract.h>
#include <assert.h>
#include <string.h>
#include <sys/wait.h>
typedef const char *vqt_const_char_p;
_Static_assert(sizeof(vqt_const_char_p)==8,"borrowed native syscall path pointer width");
long vqt_host_syscall(long,...);
long vqt_host_syscall_body(long,uint64_t,const char *,int,int);
int vqt_host_close(int);
int original_test_syscall_int_truncation(void);
int test_syscall_int_truncation(void);
#endif
