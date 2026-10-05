/* SPDX-License-Identifier: GPL-2.0-or-later
 * A bootloader fixture, not the Vinix kernel. Require the module response so
 * Limine must verify the root archive before reporting successful handoff.
 */
typedef unsigned long long u64;
struct response { u64 revision, count; void *modules; };
struct request { u64 id[4], revision; volatile struct response *response; };
__attribute__((used, section(".requests")))
static volatile u64 base_revision[] = {0xf9562b2d5c95a6c8, 0x6a7b384944536bdc, 2};
__attribute__((used, section(".requests")))
static volatile struct request modules = {
    {0xc7b1dd30df4c8b88, 0x0a82e883a194f07b, 0x3e7e279702be32af, 0xca1c4f3bd1280cee}, 0, 0
};
__attribute__((used, section(".requests")))
static volatile struct request hhdm = {
    {0xc7b1dd30df4c8b88, 0x0a82e883a194f07b, 0x48dcf1cb8ad2b852, 0x63984e959a98244b}, 0, 0
};
static void putc(char c)
{
#if defined(__x86_64__)
    __asm__ volatile("outb %0, %1" :: "a"(c), "Nd"((unsigned short)0x3f8));
#else
    volatile unsigned *uart = (void *)(hhdm.response->count + 0x09000000);
    while (uart[6] & (1 << 5)) {}
    uart[0] = (unsigned)c;
#endif
}
void main__kmain(void)
{
    const char *message = modules.response && modules.response->count == 1
        ? "VERIFIED-BOOT: launch accepted\n" : "VERIFIED-BOOT: missing module\n";
    for (const char *p = message; *p; ++p) putc(*p);
    for (;;) {
#if defined(__x86_64__)
        __asm__ volatile("cli; hlt");
#else
        __asm__ volatile("wfi");
#endif
    }
}
