/* SPDX-License-Identifier: GPL-2.0-only */
/* Minimal Linux AArch64 PID 1 for the disposable PCI configuration guest. */
static long syscall3(long number, long first, long second, long third)
{
    register long x8 __asm__("x8") = number;
    register long x0 __asm__("x0") = first;
    register long x1 __asm__("x1") = second;
    register long x2 __asm__("x2") = third;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory");
    return x0;
}

__attribute__((noreturn)) void _start(void)
{
    static const char passed[] = "PCI ARM GUEST: Linux ABI PID1 PASS\n";
    static const char failed[] = "PCI ARM GUEST: FAIL console write\n";
    long written = syscall3(64, 1, (long)passed, sizeof(passed) - 1);
    if (written != (long)sizeof(passed) - 1)
        syscall3(64, 2, (long)failed, sizeof(failed) - 1);
    /* Keep init alive after the marker; exiting PID1 would hide a subsequent
     * kernel panic. The host owns and stops only this isolated guest. */
    struct { long seconds, nanoseconds; } delay = { 1, 0 };
    for (;;) syscall3(101, (long)&delay, 0, 0);
}
