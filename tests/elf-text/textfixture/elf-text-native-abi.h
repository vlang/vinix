/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_ELF_TEXT_NATIVE_ABI_H
#define VINIX_ELF_TEXT_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <elf.h>
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/auxv.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
struct velf_dynamic_words { volatile uint64_t entries[4]; };
int velf_text_target(void) __attribute__((noinline, used, aligned(16384)));
_Static_assert(sizeof(struct velf_dynamic_words) == 32 &&
               _Alignof(struct velf_dynamic_words) == 8 &&
               offsetof(struct velf_dynamic_words, entries) == 0, "native volatile dynamic table");
_Static_assert(sizeof(Elf64_Ehdr) == 64 && offsetof(Elf64_Ehdr, e_phoff) == 32 &&
               offsetof(Elf64_Ehdr, e_phentsize) == 54 && offsetof(Elf64_Ehdr, e_phnum) == 56,
               "native executable header");
_Static_assert(sizeof(Elf64_Phdr) == 56 && offsetof(Elf64_Phdr, p_type) == 0 &&
               offsetof(Elf64_Phdr, p_flags) == 4 && offsetof(Elf64_Phdr, p_offset) == 8 &&
               offsetof(Elf64_Phdr, p_vaddr) == 16 && offsetof(Elf64_Phdr, p_filesz) == 32 &&
               offsetof(Elf64_Phdr, p_memsz) == 40 && offsetof(Elf64_Phdr, p_align) == 48,
               "native program header");
_Static_assert(sizeof(int) == 4 && sizeof(pid_t) == 4 && sizeof(long) == 8 &&
               sizeof(size_t) == 8 && sizeof(ssize_t) == 8 && sizeof(off_t) == 8,
               "native process, page and transfer widths");
#endif
