/* SPDX-License-Identifier: BSD-2-Clause */
#ifndef VINIX_QEMU_CORE_POLL_ORACLE_NATIVE_ABI_H
#define VINIX_QEMU_CORE_POLL_ORACLE_NATIVE_ABI_H
#include <pollfixture_v_contract.h>
#include <assert.h>
#include <fcntl.h>
#include <string.h>
#include <sys/wait.h>
typedef const void *vqp_const_void_p;
_Static_assert(sizeof(vqp_const_void_p)==8,"borrowed native write pointer width");
int vqp_host_pipe(int *);
int vqp_host_poll(struct pollfd *,nfds_t,int);
ssize_t vqp_host_write(int,const void *,size_t);
ssize_t vqp_host_read(int,void *,size_t);
int vqp_host_close(int);
int original_test_pollfd_abi(void);
int test_pollfd_abi(void);
#endif
