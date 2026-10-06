/* SPDX-License-Identifier: BSD-2-Clause */
#ifndef VINIX_QEMU_CORE_NANOSLEEP_ORACLE_NATIVE_ABI_H
#define VINIX_QEMU_CORE_NANOSLEEP_ORACLE_NATIVE_ABI_H
#include <nanosleepfixture_v_contract.h>
#include <assert.h>
#include <fcntl.h>
typedef const struct sigaction *vqn_const_action_p;
_Static_assert(sizeof(vqn_const_action_p)==8,"borrowed native action pointer width");
int vqn_host_fork(void);
int vqn_host_sigaction(int,const struct sigaction *,struct sigaction *);
int original_reap_ok(pid_t);
int original_test_interrupted_nanosleep_remaining(void);
int test_interrupted_nanosleep_remaining(void);
#endif
