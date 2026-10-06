/* SPDX-License-Identifier: MIT */
#ifndef VINIX_PS2_BRIDGE_H
#define VINIX_PS2_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void (*vinix_ps2_video_cb)(const void *, unsigned, unsigned, size_t);
typedef void (*vinix_ps2_audio_cb)(const int16_t *, size_t);
void *vinix_ps2_create(vinix_ps2_video_cb video, vinix_ps2_audio_cb audio);
int vinix_ps2_load(void *core, const char *game, const char *bios, const char *card);
int vinix_ps2_frame(void *core, uint32_t buttons);
int vinix_ps2_reset(void *core);
int vinix_ps2_save(void *core);
const char *vinix_ps2_error(void *core);
void vinix_ps2_destroy(void *core);
#ifdef __cplusplus
}
#endif
#endif
