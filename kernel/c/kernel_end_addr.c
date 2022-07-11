#include <stdint.h>

// Extern symbol defined in linker script
extern char KERNEL_END_SYMBOL[];

uint64_t get_kernel_end_addr(void) {
    return (uint64_t) KERNEL_END_SYMBOL;
}
