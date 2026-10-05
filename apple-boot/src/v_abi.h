#ifndef VINIX_APPLE_V_BOOT_ABI_H
#define VINIX_APPLE_V_BOOT_ABI_H
#include <stdint.h>
extern char loader_end[];
void enter_kernel(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
void cache_invalidate_range(uint64_t, uint64_t);
void quiesce_fiq_sources(void);
uint64_t read_id_aa64mmfr0(void);
uint64_t read_current_el(void);
uint64_t read_midr(void);
void halt_forever(void);
void apple_mmio_write32(uint64_t, uint32_t);
#ifdef APPLE_BOOT_FREESTANDING
/* Declarations for unused V assertion printers, discarded by --gc-sections. */
struct apple_v_file;
extern struct apple_v_file *stderr;
int fprintf(struct apple_v_file *, const char *, ...);
#else
#include <stdio.h>
#endif
#endif
