/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_MODULESTREAM_SPAWN_ABI_H
#define VINIX_MODULESTREAM_SPAWN_ABI_H
/* Keep SDK-owned action storage while V supplies its opaque function
 * declarations. Renaming declarations preserves the native ABI and symbol. */
#define posix_spawnp vinix_modulestream_sdk_spawnp
#define posix_spawn_file_actions_init vinix_modulestream_sdk_actions_init
#define posix_spawn_file_actions_destroy vinix_modulestream_sdk_actions_destroy
#define posix_spawn_file_actions_adddup2 vinix_modulestream_sdk_actions_dup2
#define posix_spawn_file_actions_addclose vinix_modulestream_sdk_actions_close
#include <spawn.h>
#undef posix_spawnp
#undef posix_spawn_file_actions_init
#undef posix_spawn_file_actions_destroy
#undef posix_spawn_file_actions_adddup2
#undef posix_spawn_file_actions_addclose
int posix_spawnp(pid_t *, const char *, const void *, const void *, char *const [], char *const []);
int posix_spawn_file_actions_init(void *);
int posix_spawn_file_actions_destroy(void *);
int posix_spawn_file_actions_adddup2(void *, int, int);
int posix_spawn_file_actions_addclose(void *, int);
#endif
