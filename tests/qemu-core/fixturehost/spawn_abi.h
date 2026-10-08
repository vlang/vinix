#ifndef VINIX_QEMU_SPAWN_ABI_H
#define VINIX_QEMU_SPAWN_ABI_H

/* Bind SDK-owned attribute storage and constants. The imported V os header
 * declares six action/spawn functions through opaque pointers. Rename only
 * their SDK declarations to avoid conflicting prototypes; all called symbols
 * keep the upstream declarations and system ABI. No algorithm lives here. */
#define posix_spawn vinix_qemu_sdk_spawn
#define posix_spawnp vinix_qemu_sdk_spawnp
#define posix_spawn_file_actions_init vinix_qemu_sdk_actions_init
#define posix_spawn_file_actions_destroy vinix_qemu_sdk_actions_destroy
#define posix_spawn_file_actions_adddup2 vinix_qemu_sdk_actions_dup2
#define posix_spawn_file_actions_addclose vinix_qemu_sdk_actions_close
#include <spawn.h>
#undef posix_spawn
#undef posix_spawnp
#undef posix_spawn_file_actions_init
#undef posix_spawn_file_actions_destroy
#undef posix_spawn_file_actions_adddup2
#undef posix_spawn_file_actions_addclose

#include <signal.h>
#ifdef SIGXFZ
#define VINIX_QEMU_SIGXFZ SIGXFZ
#else
#define VINIX_QEMU_SIGXFZ 0
#endif
#ifdef SIGXFSZ
#define VINIX_QEMU_SIGXFSZ SIGXFSZ
#else
#define VINIX_QEMU_SIGXFSZ 0
#endif

#endif
