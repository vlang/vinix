#ifndef VINIX_QEMU_SPAWN_ABI_H
#define VINIX_QEMU_SPAWN_ABI_H

/* Bind SDK-owned attribute storage, prototypes and constants. Opaque V
 * parameters call these declarations with the actual system ABI. No algorithm
 * lives here. */
#include <spawn.h>

#include <signal.h>
#ifdef __APPLE__
#include <stdint.h>
#include <mach/machine.h>
_Static_assert(sizeof(cpu_type_t) == sizeof(int32_t), "SDK cpu preference width");
#endif
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
