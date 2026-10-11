#ifndef VINIX_PERF_CONSOLE_ABI_H
#define VINIX_PERF_CONSOLE_ABI_H
/* SDK storage only; PTY draining and child ownership are implemented in V. */
#include <signal.h>
#include <sys/wait.h>
#ifdef __APPLE__
#include <util.h>
#else
#include <pty.h>
#endif
typedef siginfo_t vinix_source_child_info;
#endif
