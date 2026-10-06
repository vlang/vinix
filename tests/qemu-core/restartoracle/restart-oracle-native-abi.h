/* SPDX-License-Identifier: BSD-2-Clause */
#ifndef VINIX_QEMU_CORE_RESTART_ORACLE_NATIVE_ABI_H
#define VINIX_QEMU_CORE_RESTART_ORACLE_NATIVE_ABI_H
#include <restartfixture_v_contract.h>
#include <assert.h>
#include <fcntl.h>
int vqr_host_fork(void);
int original_reap_ok(pid_t);
int original_test_syscall_restart(void);
int test_syscall_restart(void);
#endif
