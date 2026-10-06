// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VINIX_PS2_ABI_H
#define VINIX_PS2_ABI_H
#include "bridge.h"
#include <stdint.h>
// V callback declarations omit C's const qualifiers. Cast them at the ABI
// boundary, as the PS1 frontend does for its libretro callbacks.
static inline void *ps2_create(void *video, void *audio) {
    return vinix_ps2_create((vinix_ps2_video_cb)video, (vinix_ps2_audio_cb)audio);
}
static inline uint32_t ps2_surface_load(const uint32_t *p) {
    return __atomic_load_n(p, __ATOMIC_ACQUIRE);
}
static inline void ps2_surface_store(uint32_t *p, uint32_t value) {
    __atomic_store_n(p, value, __ATOMIC_RELEASE);
}
#endif
