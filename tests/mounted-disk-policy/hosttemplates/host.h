
#ifndef VINIX_HOST_BLOCK_POLICY_H
#define VINIX_HOST_BLOCK_POLICY_H
#include <stdbool.h>
#include <stdatomic.h>
#include <unistd.h>
#define vinix_stack_alloc __builtin_alloca
static _Atomic int host_entered, host_released;
static void host_lock(bool *cell) { while (__atomic_exchange_n(cell, true, __ATOMIC_ACQUIRE)) {} }
static void host_unlock(bool *cell) { __atomic_store_n(cell, false, __ATOMIC_RELEASE); }
static void host_signal_started(void) { atomic_store(&host_entered, 1); }
static void host_wait_started(void) { while (!atomic_load(&host_entered)) usleep(1000); }
static void host_signal_release(void) { atomic_store(&host_released, 1); }
static void host_wait_release(void) { while (!atomic_load(&host_released)) usleep(1000); }
#endif
