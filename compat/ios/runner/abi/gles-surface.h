/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_IOS_GLES_SURFACE_H
#define VINIX_IOS_GLES_SURFACE_H
#include <stdint.h>
static uint32_t ios_surface_load(const uint32_t *location) {
    return __atomic_load_n(location, __ATOMIC_ACQUIRE);
}
static void ios_surface_store(uint32_t *location, uint32_t value) {
    __atomic_store_n(location, value, __ATOMIC_RELEASE);
}
#endif
