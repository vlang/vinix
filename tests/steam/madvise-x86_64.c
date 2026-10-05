typedef unsigned long u64;
static long sc6(long n, long a, long b, long c, long d, long e, long f) {
    register long r10 __asm__("r10") = d;
    register long r8 __asm__("r8") = e;
    register long r9 __asm__("r9") = f;
    long result;
    __asm__ volatile ("syscall" : "=a"(result) : "a"(n), "D"(a), "S"(b), "d"(c), "r"(r10), "r"(r8), "r"(r9) : "rcx", "r11", "memory");
    return result;
}
int main(void) {
    volatile unsigned char *p = (void *)sc6(9, 0, 16384, 3, 0x22, -1, 0);
    if ((long)p < 0 && (long)p >= -4095) return 10;
    for (u64 i = 0; i < 16384; i++) p[i] = (unsigned char)(i / 4096 + 1);
    if (sc6(28, (long)(p + 4096), 4096, 4, 0, 0, 0) != 0) return 11;
    for (u64 i = 0; i < 16384; i++) {
        unsigned char want = (i >= 4096 && i < 8192) ? 0 : (unsigned char)(i / 4096 + 1);
        if (p[i] != want) return 20 + (int)(i / 4096);
    }
    return 0;
}
__attribute__((naked, noreturn)) void _start(void) {
    __asm__("andq $-16, %rsp\n"
            "call main\n"
            "movl %eax, %edi\n"
            "movl $60, %eax\n"
            "syscall\n"
            "ud2\n");
}
