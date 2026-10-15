/* SPDX-License-Identifier: GPL-2.0-only */
/* Original declarations, host ABI and endpoint metadata; executable code is V. */
#ifndef VINIX_CONST_STRING_HOST_CONTRACT_H
#define VINIX_CONST_STRING_HOST_CONTRACT_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include "linuxkpi_const_string_v_contract.h"
void *vkr_kmalloc(size_t,unsigned int);
size_t vkr_ksize(void *);
#define csh_map(n) mmap(NULL,(n),PROT_NONE,MAP_PRIVATE|MAP_ANON,-1,0)
#define csh_writable(p,n) mprotect((p),(n),PROT_READ|PROT_WRITE)
#define csh_readonly(p,n) mprotect((p),(n),PROT_READ)
#define csh_inaccessible(p,n) mprotect((p),(n),PROT_NONE)
#endif
