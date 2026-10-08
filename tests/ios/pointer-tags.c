// SPDX-License-Identifier: GPL-2.0-or-later
typedef unsigned long uintptr_t;
extern int puts(const char *);
extern int strcmp(const char *, const char *);

const char pointer_payload[] = "native tagged pointer target";
extern const volatile uintptr_t pointer_tags[4];

// These are address relocations, not runtime integer ORs. The linker encodes
// their high bytes in Mach-O chained pointers (or ordinary legacy rebases).
__asm__(".section __DATA,__data\n"
        ".p2align 3\n"
        ".globl _pointer_tags\n"
        "_pointer_tags:\n"
        ".quad _pointer_payload\n"
        ".quad _pointer_payload + 0x0100000000000000\n"
        ".quad _pointer_payload + 0x8000000000000000\n"
        ".quad _pointer_payload + 0xff00000000000000\n");

int main(void) {
    const uintptr_t tags[] = {0, 1, 0x80, 0xff};
    for (unsigned i = 0; i < 4; i++) {
        uintptr_t tagged = pointer_tags[i];
        uintptr_t address = tagged & 0x00ffffffffffffffUL;
        if ((tagged >> 56) != tags[i] || address != (uintptr_t)pointer_payload ||
            strcmp((const char *)address, "native tagged pointer target"))
            return 1;
    }
    puts("IOS-POINTER-TAGS: relocated addresses and all high bytes preserved");
    return 0;
}
