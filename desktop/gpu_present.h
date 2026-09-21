/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Alexander Medvednikov */
#ifndef VINIX_DESKTOP_GPU_PRESENT_H
#define VINIX_DESKTOP_GPU_PRESENT_H

#include <stdint.h>

#ifdef VINIX_GPU_PRESENTER_EXTERNAL

void vinix_gpu_present_startup_stage(const char *stage);
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

#else

/*
 * The software desktop uses the same V translation unit as the GPU build.
 * Keep the optional presenter calls present and satisfy them with tiny inline
 * stubs; the GPU link defines VINIX_GPU_PRESENTER_EXTERNAL and supplies the
 * EGL implementation instead. This avoids translating the whole desktop a
 * second time merely to flip one V compile-time branch.
 */
static inline void vinix_gpu_present_startup_stage(const char *stage)
{
    (void)stage;
}

static inline void *vinix_gpu_present_create(int width, int height)
{
    (void)width;
    (void)height;
    return 0;
}

static inline int vinix_gpu_present_frame(void *opaque,
                                          const uint32_t *source,
                                          int source_width,
                                          int source_height,
                                          int source_stride,
                                          uint32_t *destination,
                                          int destination_width,
                                          int destination_height,
                                          int destination_stride)
{
    (void)opaque;
    (void)source;
    (void)source_width;
    (void)source_height;
    (void)source_stride;
    (void)destination;
    (void)destination_width;
    (void)destination_height;
    (void)destination_stride;
    return 0;
}

static inline void vinix_gpu_present_destroy(void *opaque)
{
    (void)opaque;
}

#endif

#endif
