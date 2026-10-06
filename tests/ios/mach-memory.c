// SPDX-License-Identifier: GPL-2.0-or-later
// This binary runs as original iOS ARM64 instructions, exercising 11-argument
// Mach remap calls and genuine shared storage through independently mapped VAs.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mman.h>

typedef uint32_t task_t;
extern task_t mach_task_self_;
extern unsigned long vm_page_size;
extern int vm_allocate(task_t, uint64_t *, uint64_t, int);
extern int vm_deallocate(task_t, uint64_t, uint64_t);
extern int vm_remap(task_t, uint64_t *, uint64_t, uint64_t, int,
    task_t, uint64_t, int, int *, int *, int);

static void check(int valid) { if (!valid) abort(); }
int main(void) {
    uint64_t page = vm_page_size;
    for (unsigned iteration = 0; iteration < 64; ++iteration) {
        uint64_t original = 0, alias = 0, second = 0;
        int current = 0, maximum = 0;
        check(vm_allocate(mach_task_self_, &original, page + 1, 1) == 0);
        volatile unsigned char *bytes = (void *)original;
        check(bytes[0] == 0 && bytes[page * 2 - 1] == 0);
        bytes[page + 17] = 0x5a;
        check(vm_remap(mach_task_self_, &alias, page, 0, 1,
            mach_task_self_, original + page, 0, &current, &maximum, 1) == 0);
        check(current == 3 && maximum == 7 && alias != original && alias != original + page);
        volatile unsigned char *shared = (void *)alias;
        check(shared[17] == 0x5a);
        shared[19] = 0xc3;
        check(bytes[page + 19] == 0xc3);
        check(vm_remap(mach_task_self_, &second, page, 0, 1,
            mach_task_self_, alias, 0, &current, &maximum, 1) == 0);
        uint64_t rejected = original;
        current = 0x1234; maximum = 0x5678;
        check(vm_remap(mach_task_self_, &rejected, page, 0, 0,
            mach_task_self_, alias, 0, &current, &maximum, 1) == 3);
        check(rejected == original && current == 0x1234 && maximum == 0x5678 && bytes[page + 19] == 0xc3);
        check(vm_remap(mach_task_self_, &rejected, page * 2, 0, 1,
            mach_task_self_, alias, 0, &current, &maximum, 1) == 1);
        check(vm_remap(mach_task_self_, &rejected, page, 0, 1,
            mach_task_self_, alias, 1, &current, &maximum, 1) == 46);
        check(vm_allocate(mach_task_self_ + 1, &rejected, page, 1) == 4);
        check(vm_deallocate(mach_task_self_, original, page * 2) == 0);
        check(shared[17] == 0x5a && shared[19] == 0xc3);
        check(vm_deallocate(mach_task_self_, alias, page) == 0);
        volatile unsigned char *survivor = (void *)second;
        check(survivor[17] == 0x5a && survivor[19] == 0xc3);
        check(vm_deallocate(mach_task_self_, second, page) == 0);
        check(vm_deallocate(mach_task_self_, second, page) == 1);
        // Fixed mappings must also preserve an unrelated native mmap region.
        void *occupied = mmap(NULL, (size_t)page, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
        check(occupied != MAP_FAILED);
        *(volatile unsigned char *)occupied = 0xa7;
        rejected = (uint64_t)occupied;
        check(vm_allocate(mach_task_self_, &rejected, page, 0) == 3);
        check(*(volatile unsigned char *)occupied == 0xa7 && rejected == (uint64_t)occupied);
        check(munmap(occupied, (size_t)page) == 0);
    }
    puts("IOS-MACH-VM: aliases, offsets, occupied targets, real errors and independent mapping lifetimes");
    return 0;
}
