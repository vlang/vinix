/* SPDX-License-Identifier: GPL-2.0-only */
/* Original typed declarations and host transport metadata; implementations are V. */
#ifndef VINIX_KASPRINTF_HOST_CONTRACT_H
#define VINIX_KASPRINTF_HOST_CONTRACT_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include "linuxkpi_kasprintf_v_contract.h"
#include "linuxkpi_const_string_v_contract.h"
#include <linux/panic.h>
typedef long long kph_sll;
typedef unsigned long long kph_ull;
void *vkr_kmalloc(size_t,unsigned int);
size_t vkr_ksize(void *);
size_t vkr_page_allocation_size(void *);
int vkr_format_entry(char *,size_t,char *,void *,unsigned int *);
#define kph_map(n) mmap(NULL,(n),PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0)
#define kph_readonly(p,n) mprotect((p),(n),PROT_READ)
#endif
