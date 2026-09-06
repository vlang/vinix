/* SPDX-License-Identifier: GPL-2.0-only */
/* Read-only M1 SMC client. Protocol references are recorded in docs/m1-battery.md.
 * This is deliberately a synchronous, SMC-only RTKit client: unlike AGX,
 * the SMC advertises firmware-owned SRAM, not host-allocated DMA buffers.
 * Do not share its mailbox with another RTKit instance.
 */
#include "apple_smc.h"

#define APP_EP 0x20u
#define TYPE_SHIFT 52u
#define EPMAP_LAST (UINT64_C(1) << 51)
#define KEY_BRSC UINT32_C(0x42525343)
#define CMD_READ 0x10u
#define CMD_SRAM 0x17u
#define NOTIFY 0x18u
#define SRAM_WINDOW UINT64_C(0x4000)
/* A second bound protects against a broken/stopped clock callback. */
#define POLL_LIMIT 1000000u

struct smc_state {
    void *context;
    vinix_smc_send_fn send;
    vinix_smc_recv_fn recv;
    vinix_smc_clock_fn clock;
    vinix_smc_relax_fn relax;
    uint64_t frequency, sram_base, sram_size;
    uint64_t buffer_addr[9], buffer_size[9];
    uint32_t endpoints[8];
    uint64_t sample_time;
    int sample, sampled, ready, failed;
    uint8_t next_id;
};

size_t vinix_smc_state_size(void) { return sizeof(struct smc_state); }

static int fail(struct smc_state *s, int error)
{
    s->failed = error;
    s->ready = 0;
    s->sampled = 0;
    return error;
}

static int in_sram(const struct smc_state *s, uint64_t address, uint64_t size)
{
    /* Subtraction, not address+size, avoids wrapping at UINT64_MAX. */
    return size && address >= s->sram_base && size <= s->sram_size &&
           address - s->sram_base <= s->sram_size - size;
}

static int expired(struct smc_state *s, uint64_t start, uint64_t ticks)
{
    return s->clock(s->context) - start >= ticks;
}

static uint64_t command_ticks(const struct smc_state *s)
{
    return s->frequency / 10 + (s->frequency % 10 != 0); /* 100 ms */
}

static int send_msg(struct smc_state *s, uint8_t endpoint, uint64_t word)
{
    if (s->send(s->context, word, endpoint) != 1)
        return fail(s, VINIX_SMC_IO);
    return 0;
}

static int management(struct smc_state *s, unsigned kind, uint64_t payload)
{
    return send_msg(s, 0, ((uint64_t)kind << TYPE_SHIFT) | payload);
}

static int start_endpoint(struct smc_state *s, unsigned ep)
{
    return management(s, 5, ((uint64_t)ep << 32) | 2);
}

static unsigned message_type(uint64_t word)
{
    return (unsigned)((word >> TYPE_SHIFT) & 0xff);
}

static int has_endpoint(const struct smc_state *s, unsigned ep)
{
    return !!(s->endpoints[ep / 32] & (UINT32_C(1) << (ep % 32)));
}

static int accept_buffer(struct smc_state *s, unsigned ep, uint64_t word)
{
    uint64_t address, size;
    if (ep == 8) {
        address = (word & ((UINT64_C(1) << 36) - 1)) << 12;
        size = (word >> 36) & 0xfffff;
    } else {
        address = word & ((UINT64_C(1) << 44) - 1);
        size = ((word >> 44) & 0xff) << 12;
    }
    /* Never hand a firmware request arbitrary RAM, nor touch an unvalidated
     * address. A zero address would require DMA allocation, which this M1
     * SRAM client intentionally does not implement.
     */
    if (!address)
        return fail(s, VINIX_SMC_UNSUPPORTED);
    if ((address & 0xfff) || !in_sram(s, address, size))
        return fail(s, VINIX_SMC_PROTOCOL);
    if (s->buffer_size[ep]) {
        /* A second crashlog buffer message announces a firmware crash. */
        if (ep == 1 || s->buffer_addr[ep] != address ||
            s->buffer_size[ep] != size)
            return fail(s, VINIX_SMC_IO);
        return 0;
    }
    s->buffer_addr[ep] = address;
    s->buffer_size[ep] = size;
    /* Firmware-provided buffers need no allocation reply. We do not read
     * their contents; syslog/IOReport notifications below still get ACKs.
     */
    return 0;
}

static int system_message(struct smc_state *s, uint8_t ep, uint64_t word)
{
    unsigned kind = message_type(word);
    switch (ep) {
    case 0:
        /* A fresh HELLO at runtime is a reset, not a command completion. */
        if (kind == 1)
            return fail(s, VINIX_SMC_IO);
        if ((kind == 7 || kind == 11) && (word & 0xff) != 0x20)
            return fail(s, VINIX_SMC_IO);
        return 0;
    case 1:
        if (kind == 1)
            return accept_buffer(s, ep, word);
        return fail(s, VINIX_SMC_IO);
    case 2:
        if (kind == 1)
            return accept_buffer(s, ep, word);
        if (kind == 5)
            return send_msg(s, ep, word); /* Release the firmware's log slot. */
        return 0; /* Includes syslog INIT, whose text we do not consume. */
    case 4:
        if (kind == 1)
            return accept_buffer(s, ep, word);
        if (kind == 8 || kind == 12)
            return send_msg(s, ep, word);
        return 0;
    case 8:
        if ((word >> 56) == 1)
            return accept_buffer(s, ep, word);
        return 0;
    default:
        return 0; /* Do not enable or interpret unknown application endpoints. */
    }
}

/* A timed-out request poisons the channel until a reboot. With only four
 * message-ID bits, simply retrying could eventually accept a late reply as
 * the result of a different request after ID wraparound.
 */
static int transaction(struct smc_state *s, unsigned cmd, uint32_t key,
                       unsigned length, uint64_t *result)
{
    uint8_t id = s->next_id;
    uint64_t request = ((uint64_t)key << 32) | ((uint64_t)length << 16) |
                       ((uint64_t)id << 12) | cmd;
    s->next_id = (uint8_t)((id + 1) & 15);
    uint64_t start = s->clock(s->context);
    if (send_msg(s, APP_EP, request) < 0)
        return s->failed;
    for (unsigned i = 0; i < POLL_LIMIT; ++i) {
        if (expired(s, start, command_ticks(s)))
            return fail(s, VINIX_SMC_TIMEOUT);
        uint64_t word = 0;
        uint8_t ep = 0;
        int got = s->recv(s->context, &word, &ep);
        if (got < 0)
            return fail(s, VINIX_SMC_IO);
        if (!got) {
            s->relax(s->context);
            continue;
        }
        if (ep != APP_EP) {
            int status = system_message(s, ep, word);
            if (status < 0)
                return status;
            continue;
        }
        if ((word & 0xff) == NOTIFY)
            continue;
        if (cmd == CMD_SRAM) {
            /* This one reply is a raw address, NOT an SMC status/ID header. */
            if (!in_sram(s, word, SRAM_WINDOW))
                return fail(s, VINIX_SMC_PROTOCOL);
            *result = word;
            return 0;
        }
        if (((word >> 12) & 15) != id)
            continue;
        unsigned status = (unsigned)(word & 0xff);
        if (status)
            return status == 0x84 ? VINIX_SMC_NO_KEY : VINIX_SMC_IO;
        if (((word >> 16) & 0xffff) != length)
            return fail(s, VINIX_SMC_PROTOCOL);
        *result = word;
        return 0;
    }
    return fail(s, VINIX_SMC_TIMEOUT);
}

int vinix_smc_boot(void *state, void *context,
                   vinix_smc_send_fn send, vinix_smc_recv_fn recv,
                   vinix_smc_clock_fn clock, vinix_smc_relax_fn relax,
                   uint64_t frequency, uint64_t sram_base, uint64_t sram_size)
{
    if (!state)
        return VINIX_SMC_PROTOCOL;
    struct smc_state *s = state;
    *s = (struct smc_state){0};
    if (!send || !recv || !clock || !relax || !frequency ||
        frequency > UINT64_MAX / 4 || !sram_base ||
        sram_size < SRAM_WINDOW || sram_size - 1 > UINT64_MAX - sram_base)
        return fail(s, VINIX_SMC_PROTOCOL);
    s->context = context;
    s->send = send;
    s->recv = recv;
    s->clock = clock;
    s->relax = relax;
    s->frequency = frequency;
    s->sram_base = sram_base;
    s->sram_size = sram_size;

    uint64_t start = clock(context);
    int hello = 0, map_done = 0, ap_requested = 0, iop_on = 0, ap_on = 0;
    if (management(s, 6, 0x220) < 0)
        return s->failed;
    for (unsigned i = 0; i < POLL_LIMIT; ++i) {
        if (expired(s, start, 2 * frequency))
            return fail(s, VINIX_SMC_TIMEOUT);
        uint64_t word = 0;
        uint8_t ep = 0;
        int got = recv(context, &word, &ep);
        if (got < 0)
            return fail(s, VINIX_SMC_IO);
        if (!got) {
            relax(context);
            continue;
        }
        if (ep) {
            if (system_message(s, ep, word) < 0)
                return s->failed;
            continue;
        }
        unsigned kind = message_type(word);
        switch (kind) {
        case 1: {
            unsigned min = (unsigned)(word & 0xffff);
            unsigned max = (unsigned)((word >> 16) & 0xffff);
            if (hello || min > max || min > 12 || max < 11)
                return fail(s, VINIX_SMC_UNSUPPORTED);
            unsigned version = max < 12 ? max : 12;
            if (management(s, 2, version | ((uint64_t)version << 16)) < 0)
                return s->failed;
            hello = 1;
            break;
        }
        case 8: {
            unsigned group = (unsigned)((word >> 32) & 0x3f);
            if (!hello || map_done || group >= 8)
                return fail(s, VINIX_SMC_PROTOCOL);
            s->endpoints[group] |= (uint32_t)word;
            uint64_t reply = (uint64_t)group << 32;
            reply |= (word & EPMAP_LAST) ? EPMAP_LAST : 1;
            if (management(s, 8, reply) < 0)
                return s->failed;
            if (word & EPMAP_LAST) {
                map_done = 1;
                /* Only start system endpoints whose traffic we service. */
                const unsigned system_eps[] = {1, 2, 4, 8};
                for (unsigned j = 0; j < sizeof(system_eps)/sizeof(system_eps[0]); ++j)
                    if (has_endpoint(s, system_eps[j]) &&
                        start_endpoint(s, system_eps[j]) < 0)
                        return s->failed;
            }
            break;
        }
        case 7:
            iop_on = (word & 0xff) == 0x20;
            break;
        case 11:
            if (ap_requested)
                ap_on = (word & 0xff) == 0x20;
            break;
        default:
            break;
        }
        if (map_done && !ap_requested) {
            if (management(s, 11, 0x20) < 0)
                return s->failed;
            ap_requested = 1;
        }
        if (hello && map_done && iop_on && ap_on) {
            if (!has_endpoint(s, APP_EP))
                return fail(s, VINIX_SMC_UNSUPPORTED);
            if (start_endpoint(s, APP_EP) < 0)
                return s->failed;
            uint64_t address;
            int status = transaction(s, CMD_SRAM, 0, 0, &address);
            if (status < 0)
                return status;
            /* All requested battery data fits inline. No SRAM mapping or
             * speculative physical-memory access is needed here.
             */
            s->ready = 1;
            return 0;
        }
    }
    return fail(s, VINIX_SMC_TIMEOUT);
}

int vinix_smc_poll(void *state, unsigned budget)
{
    struct smc_state *s = state;
    if (!s || !s->ready)
        return s && s->failed ? s->failed : VINIX_SMC_NOT_READY;
    if (budget > 64)
        budget = 64;
    uint64_t start = s->clock(s->context);
    for (unsigned i = 0; i < budget; ++i) {
        if (expired(s, start, command_ticks(s)))
            return 0;
        uint64_t word = 0;
        uint8_t ep = 0;
        int got = s->recv(s->context, &word, &ep);
        if (got < 0)
            return fail(s, VINIX_SMC_IO);
        if (!got)
            return 0;
        /* There is no outstanding request while polling. Drain old replies
         * and unsolicited SMC notifications without mistaking them for data.
         */
        if (ep != APP_EP && system_message(s, ep, word) < 0)
            return s->failed;
    }
    return 0;
}

int vinix_smc_refresh(void *state)
{
    struct smc_state *s = state;
    if (!s || !s->ready)
        return s && s->failed ? s->failed : VINIX_SMC_NOT_READY;
    uint64_t now = s->clock(s->context);
    if (s->sampled && now - s->sample_time < s->frequency)
        return s->sample;
    int result = vinix_smc_poll(s, 64);
    if (result < 0)
        return result;
    uint64_t word = 0;
    result = transaction(s, CMD_READ, KEY_BRSC, 2, &word);
    if (result == 0) {
        /* BRSC is ui16, little endian; the mailbox payload is also LE.
         * B0RM has different byte order and is deliberately not a fallback.
         */
        unsigned capacity = (unsigned)((word >> 32) & 0xffff);
        result = capacity <= 100 ? (int)capacity : VINIX_SMC_RANGE;
    }
    if (!s->failed) {
        s->sample = result;
        s->sample_time = s->clock(s->context);
        s->sampled = 1;
    }
    return result;
}

int vinix_smc_cached_capacity(void *state)
{
    struct smc_state *s = state;
    if (!s || !s->ready)
        return s && s->failed ? s->failed : VINIX_SMC_NOT_READY;
    if (!s->sampled)
        return VINIX_SMC_NOT_READY;
    if (s->clock(s->context) - s->sample_time >= 2 * s->frequency)
        return VINIX_SMC_TIMEOUT;
    return s->sample;
}

uint64_t vinix_smc_sample_time(const void *state)
{
    const struct smc_state *s = state;
    return s && s->sampled ? s->sample_time : 0;
}

int vinix_smc_format_capacity(int percent, uint8_t output[4])
{
    if (!output || percent < 0 || percent > 100)
        return VINIX_SMC_RANGE;
    int length = 0;
    if (percent == 100)
        output[length++] = '1';
    if (percent >= 10)
        output[length++] = (uint8_t)('0' + (percent / 10) % 10);
    output[length++] = (uint8_t)('0' + percent % 10);
    output[length++] = '\n';
    return length;
}

const char *vinix_smc_error(int result)
{
    switch (result) {
    case VINIX_SMC_IO: return "mailbox/firmware I/O error";
    case VINIX_SMC_TIMEOUT: return "SMC timeout (no retry after an in-flight timeout)";
    case VINIX_SMC_PROTOCOL: return "invalid SMC/RTKit message or SRAM range";
    case VINIX_SMC_NO_KEY: return "BRSC key unavailable";
    case VINIX_SMC_UNSUPPORTED: return "unsupported RTKit version, endpoint, or DMA request";
    case VINIX_SMC_RANGE: return "battery percentage outside 0..100";
    case VINIX_SMC_NOT_READY: return "battery sample unavailable";
    default: return "ok";
    }
}
