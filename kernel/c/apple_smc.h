/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_APPLE_SMC_H
#define VINIX_APPLE_SMC_H

#include <stddef.h>
#include <stdint.h>

/* No libc, allocation, MMIO, interrupts, or locks inside the protocol core.
 * The caller owns the opaque state, the mailbox, and serialization.
 * send: 1=sent, 0=failed. recv: 1=message, 0=empty, -1=failed.
 * clock returns a free-running, unsigned 64-bit counter at frequency Hz.
 * None of the callbacks may sleep waiting for an interrupt/event.
 */
typedef int (*vinix_smc_send_fn)(void *, uint64_t, uint8_t);
typedef int (*vinix_smc_recv_fn)(void *, uint64_t *, uint8_t *);
typedef uint64_t (*vinix_smc_clock_fn)(void *);
typedef void (*vinix_smc_relax_fn)(void *);

enum {
    VINIX_SMC_IO = -1,
    VINIX_SMC_TIMEOUT = -2,
    VINIX_SMC_PROTOCOL = -3,
    VINIX_SMC_NO_KEY = -4,
    VINIX_SMC_UNSUPPORTED = -5,
    VINIX_SMC_RANGE = -6,
    VINIX_SMC_NOT_READY = -7
};

size_t vinix_smc_state_size(void);
int vinix_smc_boot(void *state, void *context,
                   vinix_smc_send_fn send, vinix_smc_recv_fn recv,
                   vinix_smc_clock_fn clock, vinix_smc_relax_fn relax,
                   uint64_t frequency, uint64_t sram_base, uint64_t sram_size);
/* Service asynchronous RTKit traffic; bounded by both count and time. */
int vinix_smc_poll(void *state, unsigned budget);
/* Refresh at most once per second, including unsuccessful completed reads. */
int vinix_smc_refresh(void *state);
/* No hardware access; errors and samples older than two seconds are rejected. */
int vinix_smc_cached_capacity(void *state);
/* Timestamp of the last completed sample; serialize access with refresh. */
uint64_t vinix_smc_sample_time(const void *state);
/* Produces "0\n" through "100\n", without a NUL terminator. */
int vinix_smc_format_capacity(int percent, uint8_t output[4]);
const char *vinix_smc_error(int result);

#if defined(__aarch64__)
/* Accessible at EL1 on the same ARM generic-timer setup Vinix already uses. */
static inline uint64_t vinix_smc_counter(void)
{
    uint64_t counter;
    __asm__ volatile("isb; mrs %0, cntvct_el0" : "=r"(counter) : : "memory");
    return counter;
}
#endif

#endif
