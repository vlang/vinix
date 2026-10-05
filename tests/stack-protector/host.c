/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include "stack_protector.h"

extern uintptr_t __stack_chk_guard;

__attribute__((noreturn)) void vinix_stack_test_panic(char *message)
{
    assert(!strcmp(message, "stack protector: a stack frame was overwritten past its buffers"));
    _Exit(99);
}

/* A real compiler-protected C frame calls the V failure handler on mismatch.
 * Tampering with the global guard exercises the epilogue without invoking UB. */
__attribute__((noinline)) static unsigned protected_frame(unsigned seed, int tamper)
{
    volatile unsigned char bytes[64];
    unsigned total = 0;
    for (unsigned i = 0; i < sizeof(bytes); i++) bytes[i] = (unsigned char)(seed + i);
    for (unsigned i = 0; i < sizeof(bytes); i++) total += bytes[i];
    if (tamper) __stack_chk_guard ^= (uintptr_t)0x100;
    return total;
}

/* Initialization deliberately replaces the guard, so this caller cannot have
 * saved a guard before it starts. This is the boot entry's contract too. */
__attribute__((no_stack_protector)) int main(void)
{
    assert(__stack_chk_guard == (uintptr_t)UINT64_C(0x595e9fbd94fda700));
    for (unsigned i = 0; i < 1000; i++) {
        uintptr_t old = __stack_chk_guard;
        vinix_stack_guard_init();
        assert(__stack_chk_guard && __stack_chk_guard != old && !(__stack_chk_guard & 0xff));
        unsigned expected = 0;
        for (unsigned j = 0; j < 64; j++) expected += (unsigned char)(i + j);
        assert(protected_frame(i, 0) == expected);
    }
    uintptr_t parent_guard = __stack_chk_guard;
    pid_t child = fork();
    assert(child >= 0);
    if (!child) {
        (void)protected_frame(123, 1);
        _Exit(1); /* The protected epilogue must never return here. */
    }
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 99);
    assert(__stack_chk_guard == parent_guard);
    puts("STACK PROTECTOR PASS: static guard, 1000 unprotected initializations, protected frames and V panic ABI");
    return 0;
}
