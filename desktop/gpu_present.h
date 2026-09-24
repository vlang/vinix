/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Alexander Medvednikov */
#ifndef VINIX_DESKTOP_GPU_PRESENT_H
#define VINIX_DESKTOP_GPU_PRESENT_H

#include <fcntl.h>
#include <stdint.h>
#include <sys/ioctl.h>
#include <unistd.h>

/*
 * Mapping fbdev does not imply ownership of the display: Linux applications
 * explicitly switch their console to KD_GRAPHICS when they are ready to put a
 * frame on it.  Keeping that handoff here lets startup diagnostics remain on
 * the physical panel throughout ELF loading, framebuffer mmap and EGL setup.
 */
static inline void vinix_desktop_set_console_mode(int graphics)
{
    int fd = open("/dev/console", O_RDWR | O_CLOEXEC);

    if (fd < 0)
        return;
    (void)ioctl(fd, 0x4b3a /* KDSETMODE */,
                graphics ? 1 /* KD_GRAPHICS */ : 0 /* KD_TEXT */);
    close(fd);
}

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
