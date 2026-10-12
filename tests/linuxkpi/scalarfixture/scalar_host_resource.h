/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Give libc's resource ABI its own names before parsing the original UAPI. */
#ifndef VINIX_SCALAR_HOST_RESOURCE_H
#define VINIX_SCALAR_HOST_RESOURCE_H
#define rlimit vsh_host_rlimit
#define rlimit64 vsh_host_rlimit64
#define rusage vsh_host_rusage
#define timeval vsh_host_timeval
#include <sys/resource.h>
#undef rlimit
#undef rlimit64
#undef rusage
#undef timeval
#undef RLIMIT_CPU
#undef RLIMIT_FSIZE
#undef RLIMIT_DATA
#undef RLIMIT_STACK
#undef RLIMIT_CORE
#undef RLIMIT_RSS
#undef RLIMIT_NPROC
#undef RLIMIT_NOFILE
#undef RLIMIT_MEMLOCK
#undef RLIMIT_AS
#undef RLIMIT_LOCKS
#undef RLIMIT_SIGPENDING
#undef RLIMIT_MSGQUEUE
#undef RLIMIT_NICE
#undef RLIMIT_RTPRIO
#undef RLIMIT_RTTIME
#undef RLIM_NLIMITS
#undef RLIM_INFINITY
#undef RLIM64_INFINITY
#undef RUSAGE_SELF
#undef RUSAGE_CHILDREN
#undef RUSAGE_BOTH
#undef RUSAGE_THREAD
#undef PRIO_MIN
#undef PRIO_MAX
#undef PRIO_PROCESS
#undef PRIO_PGRP
#undef PRIO_USER
#endif
