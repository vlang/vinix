// The second Vinix kernel reaches this PID 1 only after UEFI, Limine and
// the initramfs have all worked under QEMU running inside the first Vinix.
typedef unsigned long size_t;

static void write_message(const char *message, size_t length) {
    register unsigned long x0 __asm__("x0") = 1;
    register const char *x1 __asm__("x1") = message;
    register size_t x2 __asm__("x2") = length;
    register unsigned long x8 __asm__("x8") = 64; // write
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x1), "r"(x2), "r"(x8) : "memory");
}

void _start(void) {
    static const char message[] = "VINIX NESTED QEMU: PASS\n";
    write_message(message, sizeof(message) - 1);
    struct { long seconds; long nanoseconds; } duration = { 1, 0 };
    register const void *sleep_arg __asm__("x0") = &duration;
    register unsigned long sleep_rem __asm__("x1") = 0;
    register unsigned long sleep_nr __asm__("x8") = 101; // nanosleep
    __asm__ volatile("svc #0" : "+r"(sleep_arg) : "r"(sleep_rem), "r"(sleep_nr) : "memory");

    register unsigned long x0 __asm__("x0") = 0xfee1dead;
    register unsigned long x1 __asm__("x1") = 0x28121969;
    register unsigned long x2 __asm__("x2") = 0x4321fedc; // POWER_OFF
    register unsigned long x3 __asm__("x3") = 0;
    register unsigned long x8 __asm__("x8") = 142; // reboot
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x1), "r"(x2), "r"(x3), "r"(x8) : "memory");
    for (;;) { __asm__ volatile("wfe"); }
}
