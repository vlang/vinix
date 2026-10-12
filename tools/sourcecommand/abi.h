#ifndef VINIX_SOURCE_COMMAND_ABI_H
#define VINIX_SOURCE_COMMAND_ABI_H
/* SDK storage only; spawn, stream and retirement algorithms are V. */
#define posix_spawn vinix_source_sdk_spawn
#define posix_spawnp vinix_source_sdk_spawnp
#define posix_spawn_file_actions_init vinix_source_sdk_actions_init
#define posix_spawn_file_actions_destroy vinix_source_sdk_actions_destroy
#define posix_spawn_file_actions_adddup2 vinix_source_sdk_actions_dup2
#define posix_spawn_file_actions_addclose vinix_source_sdk_actions_close
#include <spawn.h>
#undef posix_spawn
#undef posix_spawnp
#undef posix_spawn_file_actions_init
#undef posix_spawn_file_actions_destroy
#undef posix_spawn_file_actions_adddup2
#undef posix_spawn_file_actions_addclose
#include <sys/wait.h>
#if defined(__APPLE__)
#include <mach/machine.h>
#endif
typedef siginfo_t vinix_source_child_info;
#endif
