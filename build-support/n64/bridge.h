/* SPDX-License-Identifier: MIT */
#ifndef VINIX_N64_BRIDGE_H
#define VINIX_N64_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void (*vinix_n64_video_cb)(const void *, unsigned, unsigned, size_t);
typedef void (*vinix_n64_audio_cb)(const int16_t *, size_t, unsigned);
void *vinix_n64_create(vinix_n64_video_cb video, vinix_n64_audio_cb audio);
int vinix_n64_load(void *core, const char *game, const char *save);
int vinix_n64_frame(void *core, uint32_t buttons);
int vinix_n64_reset(void *core);
int vinix_n64_save(void *core);
int vinix_n64_loaded(void *core);
const char *vinix_n64_error(void *core);
void vinix_n64_destroy(void *core);
#ifdef __cplusplus
}
#endif
#endif
