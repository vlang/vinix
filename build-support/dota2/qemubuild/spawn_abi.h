#ifndef VINIX_DOTA_SPAWN_ABI_H
#define VINIX_DOTA_SPAWN_ABI_H

/* SDK storage and constants only. Imported V os declares these six functions
 * through ABI-compatible opaque pointers; rename the SDK declarations only. */
#define posix_spawn vinix_dota_sdk_spawn
#define posix_spawnp vinix_dota_sdk_spawnp
#define posix_spawn_file_actions_init vinix_dota_sdk_actions_init
#define posix_spawn_file_actions_destroy vinix_dota_sdk_actions_destroy
#define posix_spawn_file_actions_adddup2 vinix_dota_sdk_actions_dup2
#define posix_spawn_file_actions_addclose vinix_dota_sdk_actions_close
#include <spawn.h>
#undef posix_spawn
#undef posix_spawnp
#undef posix_spawn_file_actions_init
#undef posix_spawn_file_actions_destroy
#undef posix_spawn_file_actions_adddup2
#undef posix_spawn_file_actions_addclose
#include <signal.h>
#ifdef __APPLE__
#include <mach/machine.h>
#endif

typedef posix_spawn_file_actions_t vinix_dota_spawn_actions;
typedef posix_spawnattr_t vinix_dota_spawn_attributes;
typedef sigset_t vinix_dota_signal_set;
#define vinix_dota_sigemptyset sigemptyset
#define vinix_dota_sigaddset sigaddset

#ifdef POSIX_SPAWN_CLOEXEC_DEFAULT
#define VINIX_DOTA_CLOEXEC_DEFAULT POSIX_SPAWN_CLOEXEC_DEFAULT
#else
#define VINIX_DOTA_CLOEXEC_DEFAULT 0
#endif
#ifdef SIGXFZ
#define VINIX_DOTA_SIGXFZ SIGXFZ
#else
#define VINIX_DOTA_SIGXFZ 0
#endif
#ifdef SIGXFSZ
#define VINIX_DOTA_SIGXFSZ SIGXFSZ
#else
#define VINIX_DOTA_SIGXFSZ 0
#endif
#endif
