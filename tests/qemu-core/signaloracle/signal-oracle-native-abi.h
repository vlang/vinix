#ifndef VINIX_QEMU_CORE_SIGNAL_ORACLE_NATIVE_ABI_H
#define VINIX_QEMU_CORE_SIGNAL_ORACLE_NATIVE_ABI_H
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
pid_t vqs_host_fork(void);
int original_reap_ok(pid_t);
int original_test_default_terminating_signals(void);
int original_test_signals_reach_a_busy_loop(void);
int test_default_terminating_signals(void);
int test_signals_reach_a_busy_loop(void);
#endif
