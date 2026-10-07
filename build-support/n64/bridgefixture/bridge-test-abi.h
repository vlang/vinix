/* SPDX-License-Identifier: MIT */
/* Unchanged upstream callback globals; no test algorithms in C. */
#ifndef VINIX_N64_BRIDGE_TEST_ABI_H
#define VINIX_N64_BRIDGE_TEST_ABI_H
#include "../bridgecore/native-abi.h"
#include <assert.h>
extern retro_environment_t environ_cb;
extern retro_video_refresh_t video_cb;
extern retro_audio_sample_batch_t audio_batch_cb;
/* Native indirect variadic callee spelling; every argument comes from V. */
extern struct retro_log_callback vinix_n64_fixture_log;
#define vinix_n64_fixture_emit vinix_n64_fixture_log.log
#endif
