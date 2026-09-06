/* SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Base-M1 ANS2: bounded, polled, read-only NVMe transport.
 * Register/protocol references: Linux drivers/nvme/host/apple.c (Asahi Linux
 * Contributors), U-Boot drivers/nvme/nvme_apple.c (Mark Kettenis), and their
 * RTKit/SART drivers. See docs/apple-ans.md for pinned reference blobs.
 *
 * Hardware access is injected so host tests run the actual production code.
 * Only the V layer binds hardware; this file never guesses a physical address.
 */
#include "apple_ans.h"
#if defined(__AARCH64__) || defined(VINIX_ANS_TEST)

#define A_CAP 0x0000u
#define A_INTMS 0x000cu
#define A_CC 0x0014u
#define A_CSTS 0x001cu
#define A_AQA 0x0024u
#define A_ASQ 0x0028u
#define A_ACQ 0x0030u
#define A_ACQ_DB 0x1004u
#define A_IOCQ_DB 0x100cu
#define A_PENDING 0x1210u
#define A_BOOT 0x1300u
#define A_MODE 0x1304u
#define A_UNKNOWN 0x24008u
#define A_LINEAR 0x24908u
#define A_ASQ_DB 0x2490cu
#define A_IOSQ_DB 0x24910u
#define A_TCB_NUM 0x28100u
#define A_ASQ_TCB 0x28108u
#define A_IOSQ_TCB 0x28110u
#define A_INVALIDATE 0x28118u
#define A_TCB_STATUS 0x28120u
#define ASC_CPU 0x44u
#define ASC_RUN (1u << 4)
#define MB_TX_CTRL 0x110u
#define MB_RX_CTRL 0x114u
#define MB_TX0 0x800u
#define MB_TX1 0x808u
#define MB_RX0 0x830u
#define MB_RX1 0x838u
#define BOOT_MAGIC 0xde71ce55u
#define QDEPTH 64u
#define PAGE 4096u
#define ALIGNMENT 16384u
#define ASQ 0x00000u
#define ACQ 0x04000u
#define ATCB 0x08000u
#define IOSQ 0x0c000u
#define IOCQ 0x10000u
#define ITCB 0x14000u
#define PRPL 0x18000u
#define BOUNCE 0x20000u
#define BOUNCE_SIZE 0x10000u
#define GPT_SCRATCH 0x30000u
#define GPT_MAX_BYTES 0x20000u
#define SHARED 0x60000u
#define SHARED_SIZE 0x400000u
#define READY_US 5000000u
#define COMMAND_US 5000000u
#define BOOT_US 10000000u
#define SEND_US 20000u
#define TYPE(t) ((uint64_t)(t) << 52)
#define IOVA_MASK ((UINT64_C(1) << 42) - 1)
#define PM_FLAGS (3u << 8)
#define PM_DISABLE (1u << 10)
#define PM_RESET (1u << 31)

/* Internal errors are stable diagnostics, not userspace errno numbers. */
enum { ANS_OK, ANS_CONFIG, ANS_HANDOFF, ANS_TIMEOUT, ANS_PROTOCOL,
    ANS_FIRMWARE, ANS_SART, ANS_COMPLETION, ANS_CAPABILITY, ANS_NAMESPACE,
    ANS_GPT, ANS_RANGE, ANS_READ_ONLY };

struct ans_ops {
    uint32_t (*read32)(void *, uint64_t);
    void (*write32)(void *, uint64_t, uint32_t);
    uint64_t (*read64)(void *, uint64_t);
    void (*write64)(void *, uint64_t, uint64_t);
    uint64_t (*now)(void *);
    void (*delay)(void *, unsigned);
    /* for_cpu=0: clean/invalidate before DMA; 1: invalidate after DMA.
     * Both include a full completion barrier. All buffers are exclusive. */
    void (*sync)(void *, void *, size_t, int for_cpu);
};
struct ans_partition { uint64_t start, blocks; unsigned number; };
struct ans_namespace {
    uint32_t id, sector;
    uint64_t blocks;
    unsigned nparts;
    struct ans_partition parts[VINIX_ANS_MAX_PARTS];
};
struct ans_queue { unsigned head, phase; };
struct ans {
    struct ans_ops ops;
    void *cookie;
    uint64_t nvme, asc, mailbox, sart, reset;
    uint8_t *dma;
    uint64_t physical;
    struct ans_queue queues[2];
    struct ans_namespace ns[VINIX_ANS_MAX_NS];
    unsigned nns, max_transfer, shared_used, stage;
    uint16_t last_status, sart_owned;
    uint64_t shared_addr[9], shared_request[9];
    uint32_t endpoints[8];
    unsigned hello, mapped, ap_requested, iop_power, ap_power;
    int error, dead, started, live;
};

static uint16_t a_le16(const uint8_t *p)
{ return (uint16_t)(p[0] | (uint16_t)p[1] << 8); }
static uint32_t a_le32(const uint8_t *p)
{ return (uint32_t)a_le16(p) | (uint32_t)a_le16(p + 2) << 16; }
static uint64_t a_le64(const uint8_t *p)
{ return a_le32(p) | (uint64_t)a_le32(p + 4) << 32; }
static void a_put16(uint8_t *p, uint16_t v)
{ p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }
static void a_put32(uint8_t *p, uint32_t v)
{ a_put16(p, (uint16_t)v); a_put16(p + 2, (uint16_t)(v >> 16)); }
static void a_put64(uint8_t *p, uint64_t v)
{ a_put32(p, (uint32_t)v); a_put32(p + 4, (uint32_t)(v >> 32)); }
static void a_zero(void *p, size_t n)
{ uint8_t *b = p; while (n--) *b++ = 0; }
static void a_copy(void *d, const void *s, size_t n)
{ uint8_t *a = d; const uint8_t *b = s; while (n--) *a++ = *b++; }
static int a_equal(const uint8_t *a, const uint8_t *b, size_t n)
{ while (n--) if (*a++ != *b++) return 0; return 1; }
static int a_fail(struct ans *a, int error)
{ if (!a->dead) a->error = error; a->dead = 1; a->live = 0; return -error; }
static uint32_t a_r32(struct ans *a, uint64_t base, unsigned off)
{ return a->ops.read32(a->cookie, base + off); }
static void a_w32(struct ans *a, uint64_t base, unsigned off, uint32_t v)
{ a->ops.write32(a->cookie, base + off, v); }
static void a_sync(struct ans *a, unsigned off, size_t n, int cpu)
{ a->ops.sync(a->cookie, a->dma + off, n, cpu); }
struct a_deadline { uint64_t start, last; unsigned stalls; };
static struct a_deadline a_begin(struct ans *a)
{ uint64_t now = a->ops.now(a->cookie); return (struct a_deadline){now, now, 0}; }
static int a_expired(struct ans *a, struct a_deadline *d, uint64_t us)
{
    uint64_t now = a->ops.now(a->cookie);
    if (now == d->last) ++d->stalls; else d->stalls = 0;
    d->last = now;
    return now - d->start >= us || d->stalls >= 1024;
}

/* Allow only a driver's own, aligned shared-memory extent, and never change
 * a firmware/bootloader-owned SART entry. SART is NOT a DART page table. */
static int a_sart_allow(struct ans *a, uint64_t pa, unsigned bytes)
{
    if (!bytes || (pa & (ALIGNMENT - 1)) || (bytes & (ALIGNMENT - 1)) ||
        pa > IOVA_MASK || bytes - 1 > IOVA_MASK - pa ||
        pa < a->physical + SHARED || pa - (a->physical + SHARED) > SHARED_SIZE ||
        bytes > SHARED_SIZE - (pa - (a->physical + SHARED)))
        return a_fail(a, ANS_SART);
    for (unsigned i = 0; i < 16; ++i) {
        if ((a->sart_owned & (1u << i)) ||
            (a_r32(a, a->sart, i * 4) >> 24)) continue;
        uint32_t config = 0xff000000u | (bytes >> 12);
        a_w32(a, a->sart, 0x40 + i * 4, (uint32_t)(pa >> 12));
        a_w32(a, a->sart, i * 4, config);
        a->sart_owned |= (uint16_t)(1u << i);
        if (a_r32(a, a->sart, i * 4) != config ||
            a_r32(a, a->sart, 0x40 + i * 4) != (uint32_t)(pa >> 12))
            return a_fail(a, ANS_SART);
        return 0;
    }
    return a_fail(a, ANS_SART);
}

static int a_send(struct ans *a, unsigned ep, uint64_t msg)
{
    struct a_deadline deadline = a_begin(a);
    for (unsigned i = 0; i < 4000; ++i) {
        if (!(a_r32(a, a->mailbox, MB_TX_CTRL) & (1u << 16))) {
            a->ops.write64(a->cookie, a->mailbox + MB_TX0, msg);
            a->ops.write64(a->cookie, a->mailbox + MB_TX1, ep);
            return 0;
        }
        if (a_expired(a, &deadline, SEND_US)) break;
        a->ops.delay(a->cookie, 10);
    }
    return a_fail(a, ANS_TIMEOUT);
}
static int a_buffer_request(struct ans *a, unsigned ep, uint64_t msg)
{
    uint64_t size, address;
    if (ep == 8) {
        size = (msg >> 36) & 0xfffffu;
        address = (msg & ((UINT64_C(1) << 36) - 1)) << 12;
    } else {
        size = ((msg >> 44) & 255u) << 12;
        /* Reject unsupported/reserved address bits too; do not truncate. */
        address = msg & ((UINT64_C(1) << 44) - 1);
    }
    if (!size || address || size > 0x100000u || a->shared_addr[ep])
        return a_fail(a, ep == 1 && a->shared_addr[ep] ? ANS_FIRMWARE : ANS_PROTOCOL);
    unsigned rounded = ((unsigned)size + ALIGNMENT - 1) & ~(ALIGNMENT - 1);
    if (rounded > SHARED_SIZE - a->shared_used) return a_fail(a, ANS_SART);
    unsigned off = SHARED + a->shared_used;
    uint64_t pa = a->physical + off;
    a_zero(a->dma + off, rounded);
    a_sync(a, off, rounded, 0);
    if (a_sart_allow(a, pa, rounded)) return -a->error;
    a->shared_used += rounded;
    a->shared_addr[ep] = pa;
    a->shared_request[ep] = msg;
    uint64_t reply = ep == 8 ? (UINT64_C(1) << 56) | (size << 36) | (pa >> 12)
                             : TYPE(1) | ((size >> 12) << 44) | pa;
    return a_send(a, ep, reply);
}

/* One nonblocking message receive, with bounded replies. Returns 1 if a
 * message was serviced, 0 if empty, negative on an unrecoverable error. */
static int a_pump(struct ans *a)
{
    if (a->dead) return -a->error;
    if (a_r32(a, a->mailbox, MB_RX_CTRL) & (1u << 17)) return 0;
    uint64_t msg = a->ops.read64(a->cookie, a->mailbox + MB_RX0);
    uint64_t flags = a->ops.read64(a->cookie, a->mailbox + MB_RX1);
    unsigned ep = flags & 255u, type = (unsigned)(msg >> 52) & 255u;
    int rc = 0;
    if (ep == 0) {
        switch (type) {
        case 1: {
            unsigned min = msg & 0xffffu, max = (msg >> 16) & 0xffffu;
            if (a->hello || min > max || min > 12 || max < 11)
                return a_fail(a, ANS_PROTOCOL);
            unsigned version = max > 12 ? 12 : max;
            a->hello = 1;
            rc = a_send(a, 0, TYPE(2) | version | (uint64_t)version << 16);
            break;
        }
        case 8: {
            if (!a->hello || a->mapped) return a_fail(a, ANS_PROTOCOL);
            unsigned group = (unsigned)(msg >> 32) & 7u;
            if ((msg >> 35) & 0xffffu) return a_fail(a, ANS_PROTOCOL);
            a->endpoints[group] |= (uint32_t)msg;
            int last = !!(msg & (UINT64_C(1) << 51));
            rc = a_send(a, 0, TYPE(8) | (uint64_t)group << 32 |
                (last ? UINT64_C(1) << 51 : 1));
            if (rc) break;
            if (last) {
                static const unsigned supported[] = {1, 2, 4, 8};
                for (unsigned i = 0; i < sizeof(supported) / sizeof(supported[0]); ++i) {
                    unsigned id = supported[i];
                    if (a->endpoints[0] & (1u << id)) {
                        rc = a_send(a, 0, TYPE(5) | (uint64_t)id << 32 | 2);
                        if (rc) return rc;
                    }
                }
                a->mapped = 1;
                rc = a_send(a, 0, TYPE(11) | 0x20u);
                a->ap_requested = !rc;
            }
            break;
        }
        case 7: a->iop_power = msg & 0xffffu; break;
        case 11: a->ap_power = msg & 0xffffu; break;
        default: break; /* Unknown management messages are not DMA requests. */
        }
    } else if (ep == 1 || ep == 2 || ep == 4 || ep == 8) {
        if (!a->mapped || !(a->endpoints[0] & (1u << ep)))
            return a_fail(a, ANS_PROTOCOL);
        unsigned kind = ep == 8 ? (unsigned)(msg >> 56) : type;
        if (kind == 1) rc = a_buffer_request(a, ep, msg);
        else if (ep == 1) return a_fail(a, ANS_FIRMWARE);
        else if ((ep == 2 && kind == 5) || (ep == 4 && (kind == 8 || kind == 12)))
            rc = a_send(a, ep, msg);
        /* SYSLOG init/OSLOG notifications are intentionally discarded. */
    }
    return rc ? rc : 1;
}
static int a_boot_rtkit(struct ans *a)
{
    if (a_send(a, 0, TYPE(6) | 0x220u)) return -a->error;
    struct a_deadline deadline = a_begin(a);
    for (unsigned i = 0; i < 1000000; ++i) {
        if (a_pump(a) < 0) return -a->error;
        if (a->mapped && a->ap_requested && (a->ap_power & 255u) == 0x20 &&
            (a->iop_power & 255u) == 0x20) return 0;
        if (a_expired(a, &deadline, BOOT_US)) break;
        a->ops.delay(a->cookie, 10);
    }
    return a_fail(a, ANS_TIMEOUT);
}
static int a_wait32(struct ans *a, unsigned reg, uint32_t mask, uint32_t value,
    uint64_t timeout)
{
    struct a_deadline deadline = a_begin(a);
    for (unsigned i = 0; i < 500000; ++i) {
        if (a_pump(a) < 0) return -a->error;
        uint32_t v = a_r32(a, a->nvme, reg);
        if (reg == A_CSTS && (v & 2u)) return a_fail(a, ANS_FIRMWARE);
        if ((v & mask) == value) return 0;
        if (a_expired(a, &deadline, timeout)) break;
        a->ops.delay(a->cookie, 10);
    }
    return a_fail(a, ANS_TIMEOUT);
}

/* Whitelist at the lowest command submission layer, not merely at write(). */
static int a_command_allowed(unsigned q, const uint8_t c[64])
{
    if (q == 1) return c[0] == 2; /* NVM Read only */
    if (q) return 0;
    switch (c[0]) {
    case 1: case 5: return a_le16(c + 40) == 1; /* Create I/O SQ/CQ 1 */
    case 6: return a_le32(c + 40) <= 2; /* Identify NS/controller/active list */
    case 9: return a_le32(c + 40) == 7 && a_le32(c + 44) == 0; /* one queue */
    default: return 0;
    }
}

static int a_submit(struct ans *a, unsigned qid, uint8_t c[64], uint32_t *result)
{
    if (a->dead) return -a->error;
    if (!a_command_allowed(qid, c)) return -ANS_READ_ONLY;
    /* Fixed, disjoint tags: ANS shares one 0..63 tag space across both queues.
     * Single-flight serialization is held by V across the entire operation. */
    unsigned cid = qid ? 1 : 0;
    unsigned sq = qid ? IOSQ : ASQ, cq = qid ? IOCQ : ACQ;
    unsigned tcb = (qid ? ITCB : ATCB) + cid * 128;
    /* ANS2 linear slots are 64 bytes for BOTH queues, even with
     * CC.IOSQES=7. The 128-byte stride belongs to non-linear ANS queues. */
    unsigned stride = 64;
    a_put16(c + 2, (uint16_t)cid);
    a_zero(a->dma + sq + cid * stride, stride);
    a_copy(a->dma + sq + cid * stride, c, 64);
    a_zero(a->dma + tcb, 128);
    uint8_t *t = a->dma + tcb;
    /* Match the Linux ANS2 NVMMU contract: opcode is zero, and flags
     * describe the DMA direction (bit 0 from device, bit 1 to device). */
    t[0] = 0;
    t[1] = !a_le64(c + 24) ? 0 : (c[0] & 1u) ? 2 : 1;
    t[2] = (uint8_t)cid;
    a_put16(t + 4, a_le16(c + 48));
    a_put64(t + 24, a_le64(c + 24));
    a_put64(t + 32, a_le64(c + 32));
    a_sync(a, sq + cid * stride, stride, 0);
    a_sync(a, tcb, 128, 0);
    a_w32(a, a->nvme, qid ? A_IOSQ_DB : A_ASQ_DB, cid);
    struct ans_queue *q = &a->queues[qid];
    unsigned off = cq + q->head * 16;
    struct a_deadline deadline = a_begin(a);
    for (unsigned i = 0; i < 500000; ++i) {
        if (a_pump(a) < 0) return -a->error;
        uint32_t csts = a_r32(a, a->nvme, A_CSTS);
        if ((csts & 3u) != 1u) return a_fail(a, ANS_FIRMWARE);
        a_sync(a, off, 16, 1);
        const uint8_t *e = a->dma + off;
        uint16_t status = a_le16(e + 14);
        if ((status & 1u) == q->phase) {
            /* Do not accept stale, wrong-queue or wrong-tag completions. */
            if (a_le16(e + 12) != cid || a_le16(e + 10) != qid ||
                a_le16(e + 8) >= (qid ? QDEPTH : 2))
                return a_fail(a, ANS_PROTOCOL);
            uint32_t res = a_le32(e);
            a->last_status = (uint16_t)(status >> 1);
            if (++q->head == (qid ? QDEPTH : 2)) { q->head = 0; q->phase ^= 1; }
            a_w32(a, a->nvme, qid ? A_IOCQ_DB : A_ACQ_DB, q->head);
            a_zero(a->dma + tcb, 128);
            a_sync(a, tcb, 128, 0);
            a_w32(a, a->nvme, A_INVALIDATE, cid);
            if (a_r32(a, a->nvme, A_TCB_STATUS)) return a_fail(a, ANS_PROTOCOL);
            if (result) *result = res;
            /* DNR/More are flags, not success codes. A nonzero SC/SCT fails. */
            return (a->last_status & 0x7ffu) ? -ANS_COMPLETION : 0;
        }
        if (a_expired(a, &deadline, COMMAND_US)) break;
        a->ops.delay(a->cookie, 10);
    }
    /* Never recycle a tag or DMA storage following an uncompleted command. */
    return a_fail(a, ANS_TIMEOUT);
}

static void a_data_prps(struct ans *a, uint8_t c[64], unsigned bytes)
{
    a_put64(c + 24, a->physical + BOUNCE);
    a_put64(c + 32, 0);
    if (bytes <= PAGE) return;
    if (bytes <= 2 * PAGE) { a_put64(c + 32, a->physical + BOUNCE + PAGE); return; }
    a_zero(a->dma + PRPL, PAGE);
    for (unsigned page = 1; page < (bytes + PAGE - 1) / PAGE; ++page)
        a_put64(a->dma + PRPL + (page - 1) * 8, a->physical + BOUNCE + page * PAGE);
    a_sync(a, PRPL, PAGE, 0);
    a_put64(c + 32, a->physical + PRPL);
}
static int a_identify(struct ans *a, uint32_t id, unsigned cns)
{
    uint8_t c[64] = {0}; c[0] = 6; a_put32(c + 4, id); a_put32(c + 40, cns);
    a_data_prps(a, c, PAGE);
    a_zero(a->dma + BOUNCE, PAGE); a_sync(a, BOUNCE, PAGE, 0);
    int rc = a_submit(a, 0, c, NULL);
    if (!rc) a_sync(a, BOUNCE, PAGE, 1);
    return rc;
}
static int a_parse_namespace(struct ans_namespace *ns, uint32_t id, const uint8_t *p)
{
    uint64_t blocks = a_le64(p), capacity = a_le64(p + 8);
    unsigned format = p[26] & 15u;
    if (!id || id == UINT32_MAX || !blocks || !capacity || capacity > blocks ||
        (p[26] & 0xf0u) || (p[29] & 7u) || format > p[25] || p[25] >= 16)
        return -ANS_NAMESPACE;
    const uint8_t *lbaf = p + 128 + format * 4;
    unsigned shift = lbaf[2];
    if (a_le16(lbaf) || (shift != 9 && shift != 12) || blocks > (uint64_t)INT64_MAX >> shift)
        return -ANS_NAMESPACE;
    a_zero(ns, sizeof(*ns)); ns->id = id; ns->sector = 1u << shift; ns->blocks = blocks;
    return 0;
}
static int a_read_bytes(struct ans *a, unsigned index, void *buffer, uint64_t offset, size_t count)
{
    if (a->dead) return -a->error;
    if (index >= a->nns || (!buffer && count)) return -ANS_RANGE;
    struct ans_namespace *ns = &a->ns[index];
    uint64_t size = ns->blocks * ns->sector;
    if (offset > size || count > size - offset) return -ANS_RANGE;
    uint8_t *out = buffer;
    while (count) {
        unsigned within = (unsigned)(offset % ns->sector);
        size_t n = a->max_transfer - within;
        if (n > count) n = count;
        unsigned sectors = (unsigned)((within + n + ns->sector - 1) / ns->sector);
        unsigned bytes = sectors * ns->sector;
        uint8_t c[64] = {0}; c[0] = 2;
        a_put32(c + 4, ns->id); a_put64(c + 40, offset / ns->sector);
        a_put16(c + 48, (uint16_t)(sectors - 1));
        a_data_prps(a, c, bytes);
        a_sync(a, BOUNCE, bytes, 0);
        int rc = a_submit(a, 1, c, NULL);
        if (rc) return rc;
        a_sync(a, BOUNCE, bytes, 1);
        a_copy(out, a->dma + BOUNCE + within, n);
        offset += n; out += n; count -= n;
    }
    return 0;
}

/* GPT is decoded separately below, including both CRCs and overlap checks. */
#include "apple_ans_gpt.h"

static int a_start(struct ans *a)
{
    if (!a->nvme || !a->asc || !a->mailbox || !a->sart || !a->reset || !a->dma ||
        (a->nvme | a->asc | a->mailbox | a->sart) & 7u || (a->reset & 3u) ||
        (a->physical & (ALIGNMENT - 1)) || ((uintptr_t)a->dma & (ALIGNMENT - 1)) ||
        !a->physical || a->physical > IOVA_MASK - (VINIX_ANS_DMA_BYTES - 1) ||
        !a->ops.read32 || !a->ops.write32 || !a->ops.read64 || !a->ops.write64 ||
        !a->ops.now || !a->ops.delay || !a->ops.sync || a->started)
        return a_fail(a, ANS_CONFIG);
    a->started = 1; a->stage = 1;
    /* Only the clean, stopped U-Boot/m1n1 handoff is supported. Never reset
     * a running firmware instance whose DMA ownership belongs to someone else. */
    if (a_r32(a, a->asc, ASC_CPU) & ASC_RUN) return a_fail(a, ANS_HANDOFF);
    uint32_t reset = a_r32(a, a->reset, 0);
    if ((reset & 0xf0u) != 0xf0u) return a_fail(a, ANS_CONFIG);
    a_w32(a, a->reset, 0, (reset & ~PM_FLAGS) | PM_DISABLE);
    a_w32(a, a->reset, 0, (reset & ~PM_FLAGS) | PM_DISABLE | PM_RESET);
    a->ops.delay(a->cookie, 10);
    a_w32(a, a->reset, 0, (reset & ~(PM_FLAGS | PM_RESET)) | PM_DISABLE);
    a_w32(a, a->reset, 0, reset & ~(PM_FLAGS | PM_RESET | PM_DISABLE));
    a_zero(a->dma, SHARED); a_sync(a, 0, SHARED, 0);
    a_w32(a, a->asc, ASC_CPU, ASC_RUN);
    a->stage = 2;
    if (a_boot_rtkit(a)) return -a->error;
    a->stage = 3;
    if (a_wait32(a, A_BOOT, UINT32_MAX, BOOT_MAGIC, READY_US)) return -a->error;
    /* With stopped firmware the previous loader must also have disabled NVMe. */
    if ((a_r32(a, a->nvme, A_CC) & 1u) || (a_r32(a, a->nvme, A_CSTS) & 1u))
        return a_fail(a, ANS_HANDOFF);
    uint64_t cap = a->ops.read64(a->cookie, a->nvme + A_CAP);
    /* 4-KiB controller pages, NVM command set, 64 slots, 4-byte doorbells. */
    if ((cap & 0xffffu) < QDEPTH - 1 || ((cap >> 32) & 15u) ||
        ((cap >> 48) & 15u) || !(cap & (UINT64_C(1) << 37)))
        return a_fail(a, ANS_CAPABILITY);
    a_w32(a, a->nvme, A_INTMS, UINT32_MAX);
    a_w32(a, a->nvme, A_LINEAR, 1);
    a_w32(a, a->nvme, A_PENDING, QDEPTH | (QDEPTH << 16));
    a_w32(a, a->nvme, A_TCB_NUM, QDEPTH - 1);
    /* U-Boot's M1 bring-up disables the spurious PRP2-null check and selects
     * mode 0. All our PRPs are still built/validated before submission. */
    a_w32(a, a->nvme, A_UNKNOWN, a_r32(a, a->nvme, A_UNKNOWN) & ~(1u << 11));
    a_w32(a, a->nvme, A_MODE, 0);
    a_w32(a, a->nvme, A_AQA, 1u | (1u << 16));
    a->ops.write64(a->cookie, a->nvme + A_ASQ, a->physical + ASQ);
    a->ops.write64(a->cookie, a->nvme + A_ACQ, a->physical + ACQ);
    a->ops.write64(a->cookie, a->nvme + A_ASQ_TCB, a->physical + ATCB);
    a->ops.write64(a->cookie, a->nvme + A_IOSQ_TCB, a->physical + ITCB);
    a->queues[0].phase = a->queues[1].phase = 1;
    a->stage = 4;
    a_w32(a, a->nvme, A_CC, 1u | (7u << 16) | (4u << 20));
    if (a_wait32(a, A_CSTS, 1, 1, READY_US)) return -a->error;
    int rc = a_identify(a, 0, 1);
    if (rc) return a_fail(a, -rc);
    const uint8_t *id = a->dma + BOUNCE;
    uint32_t nn = a_le32(id + 516);
    if (!nn || a_le16(id) != 0x106bu) return a_fail(a, ANS_CAPABILITY);
    a->max_transfer = BOUNCE_SIZE;
    unsigned mdts = id[77];
    if (mdts && mdts < 4) a->max_transfer = PAGE << mdts;
    /* All supported LBAs fit even the smallest MDTS (4 KiB). */
    uint8_t c[64] = {0}; c[0] = 9; a_put32(c + 40, 7);
    rc = a_submit(a, 0, c, NULL);
    if (rc) return a_fail(a, -rc);
    a_zero(c, sizeof(c)); c[0] = 5;
    a_put64(c + 24, a->physical + IOCQ);
    a_put16(c + 40, 1); a_put16(c + 42, QDEPTH - 1); a_put16(c + 44, 1);
    rc = a_submit(a, 0, c, NULL);
    if (rc) return a_fail(a, -rc);
    a_zero(c, sizeof(c)); c[0] = 1;
    a_put64(c + 24, a->physical + IOSQ);
    a_put16(c + 40, 1); a_put16(c + 42, QDEPTH - 1);
    a_put16(c + 44, 1); a_put16(c + 46, 1);
    rc = a_submit(a, 0, c, NULL);
    if (rc) return a_fail(a, -rc);
    a->stage = 5;
    rc = a_identify(a, 0, 2);
    if (rc) return a_fail(a, -rc);
    uint32_t ids[VINIX_ANS_MAX_NS]; unsigned nids = 0;
    for (unsigned i = 0; i < PAGE / 4; ++i) {
        uint32_t nsid = a_le32(a->dma + BOUNCE + i * 4);
        if (!nsid) break;
        if (nsid == UINT32_MAX || nsid > nn || (nids && nsid <= ids[nids - 1]) ||
            nids == VINIX_ANS_MAX_NS) return a_fail(a, ANS_NAMESPACE);
        ids[nids++] = nsid;
    }
    if (!nids) return a_fail(a, ANS_NAMESPACE);
    for (unsigned i = 0; i < nids; ++i) {
        rc = a_identify(a, ids[i], 0);
        if (rc) return a_fail(a, -rc);
        rc = a_parse_namespace(&a->ns[a->nns], ids[i], a->dma + BOUNCE);
        if (rc) return a_fail(a, -rc);
        ++a->nns;
    }
    a->stage = 6;
    for (unsigned i = 0; i < a->nns; ++i) {
        /* Bad/missing GPT only suppresses partition views, not the raw disk. */
        (void)a_scan_gpt(a, i);
        if (a->dead) return -a->error;
    }
    a->stage = 7; a->live = 1;
    return 0;
}

int vinix_ans_requested(const char *s, size_t n)
{
    static const char yes[] = "vinix.apple_ans=1", no[] = "vinix.apple_ans=0";
    int found = 0;
    if (!s || n > 16384) return 0;
    for (size_t i = 0; i < n;) {
        while (i < n && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) ++i;
        size_t start = i;
        while (i < n && s[i] != ' ' && s[i] != '\t' && s[i] != '\n' && s[i] != '\r') ++i;
        if (i - start == sizeof(no) - 1 && a_equal((const uint8_t *)s + start,
            (const uint8_t *)no, sizeof(no) - 1)) return 0; /* disable wins */
        if (i - start == sizeof(yes) - 1 && a_equal((const uint8_t *)s + start,
            (const uint8_t *)yes, sizeof(yes) - 1)) found = 1;
    }
    return found;
}

#ifdef __AARCH64__
extern uint32_t vinix_mmio_read32(void *);
extern uint64_t vinix_mmio_read64(void *);
extern void vinix_mmio_write32(void *, uint32_t);
extern void vinix_mmio_write64(void *, uint64_t);
static struct ans controller;
static uint64_t a_counter_frequency;
static unsigned a_cache_line;
static uint32_t a_kernel_read32(void *cookie, uint64_t p)
{ (void)cookie; uint32_t v = vinix_mmio_read32((void *)(uintptr_t)p);
  __asm__ volatile("dmb sy" ::: "memory"); return v; }
static uint64_t a_kernel_read64(void *cookie, uint64_t p)
{ (void)cookie; uint64_t v = vinix_mmio_read64((void *)(uintptr_t)p);
  __asm__ volatile("dmb sy" ::: "memory"); return v; }
static void a_kernel_write32(void *cookie, uint64_t p, uint32_t v)
{ (void)cookie; __asm__ volatile("dmb sy" ::: "memory");
  vinix_mmio_write32((void *)(uintptr_t)p, v); }
static void a_kernel_write64(void *cookie, uint64_t p, uint64_t v)
{ (void)cookie; __asm__ volatile("dmb sy" ::: "memory");
  vinix_mmio_write64((void *)(uintptr_t)p, v); }
static uint64_t a_kernel_now(void *cookie)
{
    (void)cookie; uint64_t n;
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(n));
    return n / a_counter_frequency * 1000000u +
        n % a_counter_frequency * 1000000u / a_counter_frequency;
}
static void a_kernel_delay(void *cookie, unsigned us)
{
    uint64_t start = a_kernel_now(cookie);
    /* Cap even a stopped architectural counter; never execute WFE here. */
    for (unsigned i = 0; i < 4096 && a_kernel_now(cookie) - start < us; ++i)
        __asm__ volatile("yield" ::: "memory");
}
static void a_kernel_sync(void *cookie, void *buffer, size_t n, int cpu)
{
    (void)cookie; uintptr_t begin = (uintptr_t)buffer;
    uintptr_t end = begin + n;
    __asm__ volatile("dsb sy" ::: "memory");
    for (uintptr_t p = begin & ~(uintptr_t)(a_cache_line - 1); p < end; p += a_cache_line) {
        if (cpu) __asm__ volatile("dc ivac, %0" :: "r"(p) : "memory");
        else __asm__ volatile("dc civac, %0" :: "r"(p) : "memory");
    }
    __asm__ volatile("dsb sy" ::: "memory");
}
int vinix_ans_init(uint64_t nvme, uint64_t asc, uint64_t mailbox, uint64_t sart,
    uint64_t reset, void *dma, uint64_t physical, size_t bytes)
{
    if (controller.started || bytes < VINIX_ANS_DMA_BYTES || !dma ||
        (uintptr_t)dma > UINTPTR_MAX - VINIX_ANS_DMA_BYTES) return -ANS_CONFIG;
    uint64_t ctr;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(a_counter_frequency));
    __asm__ volatile("mrs %0, ctr_el0" : "=r"(ctr));
    if (!a_counter_frequency || a_counter_frequency > UINT32_MAX) return -ANS_CONFIG;
    a_cache_line = 4u << ((ctr >> 16) & 15u);
    if (a_cache_line > ALIGNMENT) return -ANS_CONFIG;
    controller = (struct ans){0};
    controller.ops = (struct ans_ops){a_kernel_read32, a_kernel_write32,
        a_kernel_read64, a_kernel_write64, a_kernel_now, a_kernel_delay, a_kernel_sync};
    controller.nvme = nvme; controller.asc = asc; controller.mailbox = mailbox;
    controller.sart = sart; controller.reset = reset;
    controller.dma = dma; controller.physical = physical;
    return a_start(&controller);
}
int vinix_ans_namespace_count(void) { return controller.live ? (int)controller.nns : 0; }
uint32_t vinix_ans_namespace_id(unsigned i) { return i < controller.nns ? controller.ns[i].id : 0; }
uint32_t vinix_ans_sector_size(unsigned i) { return i < controller.nns ? controller.ns[i].sector : 0; }
uint64_t vinix_ans_sector_count(unsigned i) { return i < controller.nns ? controller.ns[i].blocks : 0; }
int vinix_ans_partition_count(unsigned i) { return i < controller.nns ? (int)controller.ns[i].nparts : 0; }
unsigned vinix_ans_partition_number(unsigned i, unsigned p)
{ return i < controller.nns && p < controller.ns[i].nparts ? controller.ns[i].parts[p].number : 0; }
uint64_t vinix_ans_partition_start(unsigned i, unsigned p)
{ return i < controller.nns && p < controller.ns[i].nparts ? controller.ns[i].parts[p].start : 0; }
uint64_t vinix_ans_partition_blocks(unsigned i, unsigned p)
{ return i < controller.nns && p < controller.ns[i].nparts ? controller.ns[i].parts[p].blocks : 0; }
int vinix_ans_read(unsigned i, void *buf, uint64_t offset, size_t count)
{ return controller.live ? a_read_bytes(&controller, i, buf, offset, count) : -ANS_FIRMWARE; }
int vinix_ans_error(void) { return controller.error; }
unsigned vinix_ans_stage(void) { return controller.stage; }
uint16_t vinix_ans_completion_status(void) { return controller.last_status; }
#endif
#endif
