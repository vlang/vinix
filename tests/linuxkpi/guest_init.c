/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Tiny static Linux-ABI PID 1. Run only in the disposable test guest. */
static long syscall3(long nr, long a, long b, long c)
{
    long result;
    __asm__ volatile("syscall" : "=a"(result) : "a"(nr), "D"(a), "S"(b), "d"(c)
                     : "rcx", "r11", "memory");
    return result;
}

__attribute__((noreturn)) void _start(void)
{
    static const char device[] = "/dev/com1";
    static const char success[] = "LINUXKPI GUEST: PASS\n";
    long fd = syscall3(2, (long)device, 1, 0);
    if (fd >= 0) syscall3(1, fd, (long)success, sizeof(success) - 1);
    struct { long seconds, nanoseconds; } delay = { 1, 0 };
    for (;;) syscall3(35, (long)&delay, 0, 0);
}
