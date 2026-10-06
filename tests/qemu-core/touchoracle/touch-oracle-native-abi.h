#ifndef VINIX_QEMU_CORE_TOUCH_ORACLE_NATIVE_ABI_H
#define VINIX_QEMU_CORE_TOUCH_ORACLE_NATIVE_ABI_H
#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
int reap_ok(pid_t);
int original_reap_ok(pid_t);
int original_test_anonymous_first_touch(void);
int test_anonymous_first_touch(void);
#endif
