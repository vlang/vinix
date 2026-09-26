#include <stdint.h>

#ifdef __AARCH64__
/* Limine enters with a 4 KiB granule. There must be no context
 * synchronization between installing the 16 KiB tables and TCR. */
void vinix_arm64_switch_granule(uint64_t mair, uint64_t root, uint64_t tcr) {
    __asm__ volatile (
        "dsb ishst\n"
        "tlbi vmalle1is\n"
        "dsb ish\n"
        "isb\n"
        "msr mair_el1, %0\n"
        "msr ttbr0_el1, %1\n"
        "msr ttbr1_el1, %1\n"
        "msr tcr_el1, %2\n"
        "isb\n"
        "tlbi vmalle1is\n"
        "dsb ish\n"
        "isb\n"
        : : "r" (mair), "r" (root), "r" (tcr) : "memory");
}
#endif
