#ifndef VINIX_SOURCE_COMMAND_ABI_H
#define VINIX_SOURCE_COMMAND_ABI_H
/* SDK storage only; spawn, stream and retirement algorithms are V. */
#include <spawn.h>
#include <sys/wait.h>
#if defined(__APPLE__)
#include <mach/machine.h>
#endif
typedef siginfo_t vinix_source_child_info;
#endif
