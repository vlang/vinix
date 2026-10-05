/* SPDX-License-Identifier: GPL-2.0-only */
/* The native SVC register convention and signal-return trampoline only. */
#include "syscall_abi.h"
volatile int32_t vinit_power, vinit_reload;
void vinix_init_power_signal(int);
void vinix_init_child_signal(int);
#ifndef VINIX_INIT_HOST_TEST
int64_t vinit_syscall(uint64_t nr, uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4) {
    register uint64_t x8 __asm__("x8") = nr;
    register uint64_t x0 __asm__("x0") = a0;
    register uint64_t x1 __asm__("x1") = a1;
    register uint64_t x2 __asm__("x2") = a2;
    register uint64_t x3 __asm__("x3") = a3;
    register uint64_t x4 __asm__("x4") = a4;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4) : "memory");
    return (int64_t)x0;
}
__attribute__((naked)) static void signal_restorer(void) {
    __asm__ volatile("mov x8, #139\nsvc #0\nbrk #0\n");
}
#else
static void signal_restorer(void) {}
#endif
void *vinit_power_callback(void) { return vinix_init_power_signal; }
void *vinit_child_callback(void) { return vinix_init_child_signal; }
void *vinit_restorer(void) { return signal_restorer; }
int vinit_wifi_enabled(void) {
#ifdef VINIX_WIFI_BUNDLE
    return 1;
#else
    return 0;
#endif
}
int vinit_echo_enabled(void) {
#ifdef VINIX_BUSYBOX_ECHO_TEST
    return 1;
#else
    return 0;
#endif
}
