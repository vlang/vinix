#ifndef VINIX_DOTA_SPAWN_ABI_H
#define VINIX_DOTA_SPAWN_ABI_H

/* SDK storage, constants and system function prototypes. */
#include <spawn.h>
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
