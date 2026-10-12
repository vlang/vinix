#ifndef VINIX_ANDROID_PROBE_SPAWN_ABI_H
#define VINIX_ANDROID_PROBE_SPAWN_ABI_H

/* Bind SDK-owned action/attribute storage, prototypes and constants. The
 * compiler's libc declarations come from this header; opaque V parameters
 * still call the SDK symbols with their actual system ABI. No algorithm lives
 * here. */
#include <spawn.h>

#include <signal.h>
#ifdef __APPLE__
#include <stdint.h>
#include <mach/machine.h>
_Static_assert(sizeof(cpu_type_t) == sizeof(int32_t), "SDK cpu preference width");
#endif
#ifdef SIGXFZ
#define VINIX_PROBE_SIGXFZ SIGXFZ
#else
#define VINIX_PROBE_SIGXFZ 0
#endif
#ifdef SIGXFSZ
#define VINIX_PROBE_SIGXFSZ SIGXFSZ
#else
#define VINIX_PROBE_SIGXFSZ 0
#endif

#endif
