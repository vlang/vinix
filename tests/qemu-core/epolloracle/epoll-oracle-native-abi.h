/* SPDX-License-Identifier: BSD-2-Clause */
#ifndef VINIX_QEMU_CORE_EPOLL_ORACLE_NATIVE_ABI_H
#define VINIX_QEMU_CORE_EPOLL_ORACLE_NATIVE_ABI_H
#include <epollfixture_v_contract.h>
#include <assert.h>
#include <poll.h>
#include <fcntl.h>
#include <sys/wait.h>
typedef const void *vqe_const_void_p;
_Static_assert(sizeof(vqe_const_void_p)==8,"borrowed native write pointer width");
int vqe_host_pipe(int *);
int vqe_host_create(int);
int vqe_host_ctl(int,int,int,struct epoll_event *);
int vqe_host_wait(int,struct epoll_event *,int,int);
ssize_t vqe_host_write(int,const void *,size_t);
ssize_t vqe_host_read(int,void *,size_t);
int vqe_host_close(int);
int original_test_epoll_abi_and_count(void);
int test_epoll_abi_and_count(void);
#endif
