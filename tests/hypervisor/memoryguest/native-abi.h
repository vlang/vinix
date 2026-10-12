#ifndef VINIX_HV_MEMORY_NATIVE_ABI_H
#define VINIX_HV_MEMORY_NATIVE_ABI_H
#include "../guestfixture/hypervisor-guest-native-abi.h"
#include <pthread.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <grp.h>
#include <inttypes.h>
#define VINIX_HV_SLAB_INPUT "size-%" SCNu64 " %" SCNu64 " %" SCNu64
#define VINIX_HV_SLAB_OUTPUT "HYPERVISOR MEMORY SLAB class=%d before=%" PRIu64 " after=%" PRIu64 "\n"
_Static_assert(VINIX_HV_MAX_GUEST_MEMORY == 1024UL * 1024UL * 1024UL, "1 GiB public bound");
#endif
