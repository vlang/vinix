/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_RWSEM_V_PRIMITIVES_H
#define VINIX_LINUXKPI_RWSEM_V_PRIMITIVES_H
#include <stdint.h>
#include "linuxkpi_wait_v_primitives.h"

/* Data-only view: checked against the unchanged original in the facade. */
struct vrs_rwsem {
    long count;
    long owner;
    unsigned int wait_lock;
    struct vkw_list wait_list;
};

void vrs_init(void *);
int32_t vrs_down_read(void *, uint32_t);
int32_t vrs_down_write(void *, uint32_t);
int32_t vrs_try_read(void *);
int32_t vrs_try_write(void *);
void vrs_up_read(void *);
void vrs_up_write(void *);
void vrs_downgrade(void *);
#endif
