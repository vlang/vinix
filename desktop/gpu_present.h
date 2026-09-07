/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Alexander Medvednikov */
#ifndef VINIX_DESKTOP_GPU_PRESENT_H
#define VINIX_DESKTOP_GPU_PRESENT_H

#include <stdint.h>

void *vinix_gpu_present_create(int width, int height);
int vinix_gpu_present_frame(void *opaque,
                            const uint32_t *source,
                            int source_width,
                            int source_height,
                            int source_stride,
                            uint32_t *destination,
                            int destination_width,
                            int destination_height,
                            int destination_stride);
void vinix_gpu_present_destroy(void *opaque);

#endif
