#ifndef VINIX_QEMU_CORE_SIGNAL_FIXTURE_NATIVE_ABI_H
#define VINIX_QEMU_CORE_SIGNAL_FIXTURE_NATIVE_ABI_H
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
struct vqs_volatile_signal { volatile sig_atomic_t value; };
_Static_assert(sizeof(sig_atomic_t) == 4, "original signal flag width");
_Static_assert(sizeof(struct vqs_volatile_signal) == sizeof(sig_atomic_t), "native volatile signal view");
_Static_assert(_Alignof(struct vqs_volatile_signal) == _Alignof(sig_atomic_t), "native signal flag alignment");
_Static_assert(sizeof(pid_t) == 4 && sizeof(int) == 4, "native signal process/status ABI");
_Static_assert(sizeof(time_t) == 8 && sizeof(long) == 8, "native timespec fields");
int reap_ok(pid_t);
void vqs_busy_loop_handler(int);
#endif
