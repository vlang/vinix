/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_MINECRAFT_SPAWN_ABI_H
#define VINIX_MINECRAFT_SPAWN_ABI_H
/* V's os module declares these entry points with opaque action storage. Bind
 * SDK-owned storage without changing those declarations or their symbols. */
#define posix_spawn vinix_minecraft_sdk_spawn
#define posix_spawnp vinix_minecraft_sdk_spawnp
#define posix_spawn_file_actions_init vinix_minecraft_sdk_actions_init
#define posix_spawn_file_actions_destroy vinix_minecraft_sdk_actions_destroy
#define posix_spawn_file_actions_adddup2 vinix_minecraft_sdk_actions_dup2
#define posix_spawn_file_actions_addclose vinix_minecraft_sdk_actions_close
#include <spawn.h>
#undef posix_spawn
#undef posix_spawnp
#undef posix_spawn_file_actions_init
#undef posix_spawn_file_actions_destroy
#undef posix_spawn_file_actions_adddup2
#undef posix_spawn_file_actions_addclose
/* Keep these opaque declarations local: the V runtime may provide them in a
 * separate object instead of emitting them into the generated program. */
int posix_spawnp(pid_t *, const char *, const void *, const void *, char *const [], char *const []);
int posix_spawn_file_actions_init(void *);
int posix_spawn_file_actions_destroy(void *);
int posix_spawn_file_actions_adddup2(void *, int, int);
int posix_spawn_file_actions_addclose(void *, int);
#endif
