// SPDX-License-Identifier: GPL-2.0-or-later
#include "brcm_m1.h"
struct bw_m1_state {
    struct bw_m1_plan p;
    struct bw_device dev;
    uint64_t endpoint, bar0, bar2;
    uint32_t bar0_len, bar2_len, dart_error;
    int prepared, attempted, endpoint_valid;
    uint8_t frames[64][BW_MAX_FRAME];
    uint16_t length[64],head,tail;
    uint64_t drops;
    size_t total[4],used[4];
    uint8_t firmware[4u*1024u*1024u],nvram[65536],clm[1024u*1024u],txcap[1024u*1024u];
};
void *vinix_m1_core_state(void);
#define host (*(struct bw_m1_state *)vinix_m1_core_state())
#define dart_prepare(...) vinix_m1_core_dart_prepare(__VA_ARGS__)
int dart_prepare(void);
#define bar_size(...) vinix_m1_core_bar_size(__VA_ARGS__)
int bar_size(unsigned, uint64_t *);
#define stop_dma(...) vinix_m1_core_stop_dma(__VA_ARGS__)
void stop_dma(void *);
#define bus_read(...) vinix_m1_core_bus_read(__VA_ARGS__)
uint32_t bus_read(void *, unsigned, uint32_t, unsigned);
#define bus_write(...) vinix_m1_core_bus_write(__VA_ARGS__)
void bus_write(void *, unsigned, uint32_t, unsigned, uint32_t);
