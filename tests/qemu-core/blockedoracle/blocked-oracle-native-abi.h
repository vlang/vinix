/* SPDX-License-Identifier: BSD-2-Clause */
#ifndef VINIX_QEMU_CORE_BLOCKED_ORACLE_NATIVE_ABI_H
#define VINIX_QEMU_CORE_BLOCKED_ORACLE_NATIVE_ABI_H
#include <blockedfixture_v_contract.h>
#include <assert.h>
#include <fcntl.h>
#include <string.h>
#if defined(__APPLE__)
#define AT_PAGESZ 6
#define AT_RANDOM 25
unsigned long getauxval(unsigned long);
#else
#include <sys/auxv.h>
#endif
typedef const char *vqb_const_char_p;
typedef char *const *vqb_const_argv_p;
typedef const pthread_attr_t *vqb_const_attr_p;
_Static_assert(sizeof(vqb_const_char_p)==8 && sizeof(vqb_const_argv_p)==8 && sizeof(vqb_const_attr_p)==8,"borrowed native pointer width");
int vqb_host_fork(void);
int vqb_host_pipe(int *);
int vqb_host_pthread_create(pthread_t *,const pthread_attr_t *,void *(*)(void *),void *);
int vqb_host_execv(const char *,char *const []);
pid_t vqb_host_waitpid(pid_t,int *,int);
int vqb_host_probe_open(const char *,int);
unsigned long vqb_host_getauxval(unsigned long);
int original_reap_ok(pid_t);
int original_exec_probe(char **);
int original_test_exit_takes_down_blocked_threads(void);
int test_exit_takes_down_blocked_threads(void);
#endif
