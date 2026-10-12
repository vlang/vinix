#ifndef VINIX_CORE_VM_ABI_H
#define VINIX_CORE_VM_ABI_H
/* SDK types and constants only. The controller and retirement live in V. */
#include <signal.h>
#include <sys/wait.h>
#include <poll.h>
#ifdef __APPLE__
#include <util.h>
#else
#include <pty.h>
#endif
typedef siginfo_t vinix_core_child_info;
#endif
