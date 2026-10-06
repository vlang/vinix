/* Volatile native boot-response and MMIO layouts, without helper algorithms. */
#ifndef VINIX_VERIFIED_BOOT_FIXTURE_ABI_H
#define VINIX_VERIFIED_BOOT_FIXTURE_ABI_H
#include <stdint.h>
struct vvb_response { volatile uint64_t revision, count; void *modules; };
struct vvb_uart_word { volatile uint32_t value; };
_Static_assert(sizeof(struct vvb_response) == 24, "original response prefix");
_Static_assert(sizeof(struct vvb_uart_word) == 4, "original MMIO word width");
#endif
