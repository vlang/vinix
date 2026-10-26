#ifndef VINIX_PEER_BUILD_ABI_H
#define VINIX_PEER_BUILD_ABI_H
/* SDK storage only; process ownership and cleanup are implemented in V. */
#include <signal.h>
#include <sys/wait.h>
typedef siginfo_t vinix_peer_child_info;
#endif
