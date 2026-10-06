// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VINIX_PS1_ABI_H
#define VINIX_PS1_ABI_H
#include "libretro.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdint.h>
static inline uint32_t ps1_surface_load(const uint32_t *p) {
    return __atomic_load_n(p, __ATOMIC_ACQUIRE);
}
static inline void ps1_surface_store(uint32_t *p, uint32_t v) {
    __atomic_store_n(p, v, __ATOMIC_RELEASE);
}
static void ps1_log(enum retro_log_level level, const char *format, ...) {
    (void)level;
    va_list args;
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
}
// Const-qualified callback pointers and the C field named "log" cross the
// V/C boundary here without relying on V's generated identifier spelling.
static inline void ps1_set_video(void *callback) {
    retro_set_video_refresh((retro_video_refresh_t)callback);
}
static inline void ps1_set_audio_batch(void *callback) {
    retro_set_audio_sample_batch((retro_audio_sample_batch_t)callback);
}
static inline void ps1_set_log(void *data) {
    ((struct retro_log_callback *)data)->log = ps1_log;
}
#endif
