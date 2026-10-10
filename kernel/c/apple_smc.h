/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_APPLE_SMC_H
#define VINIX_APPLE_SMC_H

#include <stddef.h>
#include <stdint.h>

#ifdef VINIX_V_RUNTIME
#define VINIX_SMC_CONST
#else
#define VINIX_SMC_CONST const
#endif

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
/* Copy `length` bytes at `offset` of the SMC's shared memory from (write 0)
 * or to (write 1) `buffer`. 1=done, 0=failed. The caller maps that memory.
 */
typedef int (*vinix_smc_shmem_fn)(void *, int write, uint32_t offset,
                                  uint8_t *buffer, uint32_t length);

enum {
    VINIX_SMC_IO = -1,
    VINIX_SMC_TIMEOUT = -2,
    VINIX_SMC_PROTOCOL = -3,
    VINIX_SMC_NO_KEY = -4,
    VINIX_SMC_UNSUPPORTED = -5,
    VINIX_SMC_RANGE = -6,
    VINIX_SMC_NOT_READY = -7,
    VINIX_SMC_ARGUMENT = -8
};

/* The longest key value carried: an identity string. */
#define VINIX_SMC_MAX_VALUE 32

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
uint64_t vinix_smc_sample_time(VINIX_SMC_CONST void *state);
/* Read-only battery telemetry. Bits 0/1/2 indicate voltage/current/power.
 * Values are mV, signed mA and signed mW, without estimating missing sensors.
 */
int vinix_smc_refresh_power(void *state, unsigned *flags, int *voltage,
                            int *current, int *power);
uint64_t vinix_smc_power_time(VINIX_SMC_CONST void *state);
int vinix_smc_format_power(unsigned flags, int voltage, int current, int power,
                           uint8_t output[128]);
/* Keys by name. None of these is sent at boot or by the functions above,
 * which send GET_SRAM_ADDR and READ_KEY only. Values longer than four bytes,
 * key descriptions and writes need vinix_smc_set_shmem() first and are
 * refused unsent without it. A key that is absent, answers with another size
 * or is refused fails that one call; only a reply that never comes gives up
 * the channel.
 */
int vinix_smc_set_shmem(void *state, vinix_smc_shmem_fn shmem);
uint64_t vinix_smc_shmem_address(void *state);
int vinix_smc_failure(void *state);
uint64_t vinix_smc_key_writes(void *state);
int vinix_smc_key_info(void *state, uint32_t key, uint8_t *size,
                       uint32_t *kind, uint8_t *flags);
int vinix_smc_read_key(void *state, uint32_t key, uint32_t length,
                       uint8_t *output);
int vinix_smc_write_key(void *state, uint32_t key, uint32_t length,
                        uint8_t *data);
/* Produces "0\n" through "100\n", without a NUL terminator. */
int vinix_smc_format_capacity(int percent, uint8_t output[4]);
VINIX_SMC_CONST char *vinix_smc_error(int result);

#undef VINIX_SMC_CONST

#if defined(__aarch64__)
/* Accessible at EL1 on the same ARM generic-timer setup Vinix already uses. */
uint64_t vinix_smc_counter(void);
#endif

#endif
