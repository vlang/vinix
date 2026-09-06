/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* Share the exact ext2 fixture/reader, but run its seven groups separately. */
#define main ext2_fixture_tests_main
#define rng ext2_fixture_rng
#define random32 ext2_fixture_random32
#define t_mutation ext2_fixture_mutation
#include "ext2_test.c"
#undef rng
#undef random32
#undef t_mutation
#undef main
#define VINIX_ANS_TEST
#include "../../kernel/c/apple_ans.c"

#define F_NVME UINT64_C(0x100000)
#define F_ASC UINT64_C(0x200000)
#define F_MB UINT64_C(0x300000)
#define F_SART UINT64_C(0x400000)
#define F_RESET UINT64_C(0x500000)
#define F_DMA UINT64_C(0x800000000)
struct message { uint64_t data; unsigned ep; };
struct fake {
    struct ans a;
    uint32_t regs[0x30000 / 4], sart[32], reset, cpu;
    struct message messages[128]; unsigned mh, mt;
    uint64_t txmsg, now;
    uint8_t *disk;
    unsigned sector, blocks, commands, reads, writes, nvme_writes, syncs;
    unsigned cq_head[2], cq_phase[2], mdts;
    int stuck_send, silent_firmware, frozen_clock, stall_command, bad_cid, bad_qid;
    int bad_nvmmu, wrong_phase, status, bad_boot, bad_ready, bad_version;
    int nonzero_iova, runtime_crash;
    unsigned media_writes, flushes, deleted_sq, deleted_cq, shutdown_requested;
    unsigned ap_quiesced, iop_asleep, bounce_syncs;
    int fail_opcode, fail_on_queue, fail_after, shutdown_stall, disable_stall, power_stall;
    unsigned events[512], nevents;
};
static unsigned groups;
static void f_event(struct fake *f, unsigned e)
{ if (f->nevents < 512) f->events[f->nevents++] = e; }
static void f_from_dma(struct fake *f, const uint8_t *c, uint8_t *out, unsigned bytes)
{
    assert(bytes && bytes <= BOUNCE_SIZE);
    for (unsigned off = 0; off < bytes; off += PAGE) {
        uint64_t pa;
        if (!off) pa = a_le64(c + 24);
        else if (bytes <= 2 * PAGE) pa = a_le64(c + 32);
        else {
            assert(a_le64(c + 32) == F_DMA + PRPL);
            pa = a_le64(f->a.dma + PRPL + (off / PAGE - 1) * 8);
        }
        assert(pa == F_DMA + BOUNCE + off);
        unsigned n = bytes - off < PAGE ? bytes - off : PAGE;
        memcpy(out + off, f->a.dma + (pa - F_DMA), n);
    }
}
static void f_queue(struct fake *f, unsigned ep, uint64_t msg)
{
    assert(f->mt - f->mh < 128);
    f->messages[f->mt++ % 128] = (struct message){msg, ep};
}
static void *f_dma(struct fake *f, uint64_t pa, unsigned size)
{
    assert(pa >= F_DMA && pa - F_DMA <= VINIX_ANS_DMA_BYTES);
    assert(size <= VINIX_ANS_DMA_BYTES - (pa - F_DMA));
    return f->a.dma + (pa - F_DMA);
}
/* Build wire data independently of the production identification parser. */
static void f_ns_id(struct fake *f, uint8_t *p)
{
    memset(p, 0, PAGE);
    a_put64(p, f->blocks); a_put64(p + 8, f->blocks);
    p[128 + 2] = f->sector == 512 ? 9 : 12;
}
static void f_transfer(struct fake *f, const uint8_t *c, const uint8_t *src, unsigned bytes)
{
    uint64_t p1 = a_le64(c + 24), p2 = a_le64(c + 32);
    assert(p1 == F_DMA + BOUNCE && bytes && bytes <= BOUNCE_SIZE);
    unsigned first = bytes < PAGE ? bytes : PAGE;
    memcpy(f_dma(f, p1, first), src, first);
    if (bytes <= PAGE) { assert(p2 == 0); return; }
    if (bytes <= PAGE * 2) {
        assert(p2 == p1 + PAGE);
        memcpy(f_dma(f, p2, bytes - PAGE), src + PAGE, bytes - PAGE); return;
    }
    assert(p2 == F_DMA + PRPL);
    const uint8_t *list = f_dma(f, p2, PAGE);
    for (unsigned off = PAGE; off < bytes; off += PAGE) {
        uint64_t pa = a_le64(list + (off / PAGE - 1) * 8);
        assert(pa == F_DMA + BOUNCE + off);
        unsigned n = bytes - off < PAGE ? bytes - off : PAGE;
        memcpy(f_dma(f, pa, n), src + off, n);
    }
}
static void f_command(struct fake *f, unsigned q, unsigned cid)
{
    ++f->commands;
    assert(cid == (q ? 1u : 0u));
    /* ANS2 linear SQ stride is 64, independent of CC.IOSQES. */
    unsigned sq = (q ? IOSQ : ASQ) + cid * 64;
    const uint8_t *c = f->a.dma + sq;
    const uint8_t *t = f->a.dma + (q ? ITCB : ATCB) + cid * 128;
    assert(f->syncs && c[1] == 0 && a_le16(c + 2) == cid);
    assert(t[0] == 0 && t[2] == cid);
    assert(t[1] == (!a_le64(c + 24) ? 0 : (c[0] & 1u) ? 2 : 1));
    assert(a_le16(t + 4) == a_le16(c + 48));
    assert(a_le64(t + 24) == a_le64(c + 24) && a_le64(t + 32) == a_le64(c + 32));
    for (unsigned i = 40; i < 128; ++i) assert(t[i] == 0); /* no AES/vendor data */
    /* Neighbouring linear slots must not be used as 128-byte entries. */
    if (q) for (unsigned i = 0; i < 64; ++i) {
        assert(f->a.dma[IOSQ + i] == 0);
        assert(f->a.dma[IOSQ + 128 + i] == 0);
    }
    if (f->stall_command) return;
    unsigned status = (unsigned)f->status;
    if (f->fail_after >= 0 && f->fail_opcode == c[0] && f->fail_on_queue == (int)q) {
        if (!f->fail_after) status = 2; else --f->fail_after;
    }
    if (!status) {
        if (!q && c[0] == 6) {
            uint8_t p[PAGE] = {0};
            switch (a_le32(c + 40)) {
            case 1: a_put16(p, 0x106b); p[77] = (uint8_t)f->mdts;
                    a_put32(p + 516, 1); break;
            case 2: a_put32(p, 1); break;
            case 0: assert(a_le32(c + 4) == 1); f_ns_id(f, p); break;
            default: assert(0);
            }
            f_transfer(f, c, p, PAGE);
        } else if (!q && c[0] == 9) {
            assert(a_le32(c + 40) == 7 && a_le32(c + 44) == 0);
        } else if (!q && (c[0] == 5 || c[0] == 1)) {
            assert(a_le16(c + 40) == 1 && a_le16(c + 42) == 63);
            assert(a_le16(c + 44) == 1); /* no interrupt-enable bit */
            if (c[0] == 1) assert(a_le16(c + 46) == 1);
            assert(a_le64(c + 24) == F_DMA + (c[0] == 5 ? IOCQ : IOSQ));
        } else if (q && c[0] == 2) {
            uint64_t lba = a_le64(c + 40);
            unsigned n = (unsigned)a_le16(c + 48) + 1;
            assert(a_le32(c + 4) == 1 && lba < f->blocks && n <= f->blocks - lba);
            ++f->reads;
            f_transfer(f, c, f->disk + lba * f->sector, n * f->sector);
        } else if (q && c[0] == 1) {
            uint64_t lba = a_le64(c + 40); unsigned n = (unsigned)a_le16(c + 48) + 1;
            assert(a_le32(c + 4) == 1 && lba < f->blocks && n <= f->blocks - lba);
            assert(a_le16(c + 50) == 0x4000 && f->bounce_syncs);
            f_from_dma(f, c, f->disk + lba * f->sector, n * f->sector);
            ++f->media_writes; f_event(f, 1);
        } else if (q && c[0] == 0) {
            assert(a_le32(c + 4) == 1 && !a_le64(c + 24));
            ++f->flushes; f_event(f, 2);
        } else if (!q && c[0] == 0) {
            assert(a_le16(c + 40) == 1 && f->flushes);
            f->deleted_sq = 1; f_event(f, 3);
        } else if (!q && c[0] == 4) {
            assert(a_le16(c + 40) == 1 && f->deleted_sq);
            f->deleted_cq = 1; f_event(f, 4);
        } else { fprintf(stderr, "unexpected command q=%u op=%u\n", q, c[0]); abort(); }
    }
    uint8_t *e = f->a.dma + (q ? IOCQ : ACQ) + f->cq_head[q] * 16;
    memset(e, 0, 16);
    a_put16(e + 10, (uint16_t)(f->bad_qid ? 3 : q));
    a_put16(e + 12, (uint16_t)(f->bad_cid ? 7 : cid));
    a_put16(e + 14, (uint16_t)(status << 1 |
        (f->cq_phase[q] ^ !!f->wrong_phase)));
    if (++f->cq_head[q] == (q ? QDEPTH : 2)) { f->cq_head[q] = 0; f->cq_phase[q] ^= 1; }
    if (f->runtime_crash) f_queue(f, 1, TYPE(2));
}
static uint32_t f_read32(void *cookie, uint64_t p)
{
    struct fake *f = cookie;
    if (p == F_RESET) return f->reset;
    if (p == F_ASC + ASC_CPU) return f->cpu;
    if (p == F_MB + MB_TX_CTRL) return f->stuck_send ? 1u << 16 : 0;
    if (p == F_MB + MB_RX_CTRL) return f->mh == f->mt ? 1u << 17 : 0;
    if (p >= F_SART && p < F_SART + 128) return f->sart[(p - F_SART) / 4];
    assert(p >= F_NVME && p < F_NVME + sizeof(f->regs) && !(p & 3u));
    if (p == F_NVME + A_TCB_STATUS) return f->bad_nvmmu ? 1 : 0;
    if (p == F_NVME + A_BOOT) return f->bad_boot ? 0 : BOOT_MAGIC;
    return f->regs[(p - F_NVME) / 4];
}
static void f_write32(void *cookie, uint64_t p, uint32_t v)
{
    struct fake *f = cookie; ++f->writes;
    if (p == F_RESET) { f->reset = v; return; }
    if (p == F_ASC + ASC_CPU) {
        if (!(v & ASC_RUN)) { assert(f->iop_asleep); f_event(f, 9); }
        f->cpu = v; return;
    }
    if (p >= F_SART && p < F_SART + 128) { f->sart[(p - F_SART) / 4] = v; return; }
    assert(p >= F_NVME && p < F_NVME + sizeof(f->regs) && !(p & 3u));
    ++f->nvme_writes;
    f->regs[(p - F_NVME) / 4] = v;
    if (p == F_NVME + A_CC) {
        if ((v >> 14 & 3u) == 1) {
            assert(f->deleted_cq && f->flushes);
            f->shutdown_requested = 1; f_event(f, 5);
            f->regs[A_CSTS / 4] = f->shutdown_stall ? 1 : 9;
        } else if (!(v & 1)) {
            assert(f->shutdown_requested && !f->shutdown_stall); f_event(f, 6);
            f->regs[A_CSTS / 4] = f->disable_stall ? 1 : 8;
        } else {
            assert(v == (1u | 7u << 16 | 4u << 20));
            f->regs[A_CSTS / 4] = f->bad_ready ? 0 : 1;
        }
    }
    if (p == F_NVME + A_ASQ_DB) f_command(f, 0, v);
    if (p == F_NVME + A_IOSQ_DB) f_command(f, 1, v);
}
static uint64_t f_read64(void *cookie, uint64_t p)
{
    struct fake *f = cookie;
    if (p == F_MB + MB_RX0) { assert(f->mt != f->mh); return f->messages[f->mh % 128].data; }
    if (p == F_MB + MB_RX1) { assert(f->mt != f->mh); return f->messages[f->mh++ % 128].ep; }
    assert(p == F_NVME + A_CAP);
    return UINT64_C(1) << 37 | 63;
}
static void f_write64(void *cookie, uint64_t p, uint64_t v)
{
    struct fake *f = cookie; ++f->writes;
    if (p == F_MB + MB_TX0) { f->txmsg = v; return; }
    if (p == F_MB + MB_TX1) {
        uint64_t m = f->txmsg; unsigned type = (unsigned)(m >> 52) & 255u;
        if (f->silent_firmware) return;
        if (v == 0 && type == 6 && (m & 0xffffu) == 1) {
            assert(f->ap_quiesced && !(f->regs[A_CSTS / 4] & 1)); f_event(f, 8);
            if (!f->power_stall) { f->iop_asleep = 1; f_queue(f, 0, TYPE(7) | 1); }
        } else if (v == 0 && type == 6) {
            assert((m & 0xffffu) == 0x220);
            f_queue(f, 0, TYPE(1) | (f->bad_version ? 14u : 11u) | (UINT64_C(12) << 16));
        } else if (v == 0 && type == 2) {
            assert((m & 0xffffffffu) == 0x000c000cu);
            f_queue(f, 0, TYPE(8) | UINT64_C(1) << 51 | 0x117u);
        } else if (v == 0 && type == 5) {
            unsigned ep = (unsigned)(m >> 32) & 255u;
            assert((m & 0xffffffffu) == 2);
            uint64_t request = ep == 8 ? UINT64_C(1) << 56 | UINT64_C(4096) << 36
                                      : TYPE(1) | UINT64_C(1) << 44;
            f_queue(f, ep, request | (f->nonzero_iova ? 0x4000 : 0));
        } else if (v == 0 && type == 11 && (m & 0xffffu) == 0x10) {
            assert(!(f->regs[A_CSTS / 4] & 1)); f_event(f, 7);
            if (!f->power_stall) { f->ap_quiesced = 1; f_queue(f, 0, TYPE(11) | 0x10); }
        } else if (v == 0 && type == 11) {
            f_queue(f, 0, TYPE(7) | 0x220); f_queue(f, 0, TYPE(11) | 0x20);
        } else if (v != 0 && (type == 1 || (m >> 56) == 1)) {
            uint64_t pa = v == 8 ? (m & ((UINT64_C(1) << 36) - 1)) << 12 : m & IOVA_MASK;
            assert(pa >= F_DMA + SHARED && pa < F_DMA + VINIX_ANS_DMA_BYTES);
            int allowed = 0;
            for (unsigned i = 0; i < 16; ++i)
                if ((f->sart[i] >> 24) == 0xff && ((uint64_t)f->sart[16 + i] << 12) == pa)
                    allowed = 1;
            assert(allowed);
        }
        return;
    }
    assert(p >= F_NVME && p + 8 <= F_NVME + sizeof(f->regs) && !(p & 7u));
    f->regs[(p - F_NVME) / 4] = (uint32_t)v;
    f->regs[(p - F_NVME) / 4 + 1] = (uint32_t)(v >> 32);
}
static uint64_t f_now(void *cookie)
{ struct fake *f = cookie; if (!f->frozen_clock) ++f->now; return f->now; }
static void f_delay(void *cookie, unsigned us)
{ struct fake *f = cookie; if (!f->frozen_clock) f->now += us; }
static void f_sync(void *cookie, void *p, size_t n, int cpu)
{
    struct fake *f = cookie; (void)cpu;
    assert((uint8_t *)p >= f->a.dma && (uint8_t *)p + n <= f->a.dma + VINIX_ANS_DMA_BYTES);
    ++f->syncs;
    if (!cpu && p == f->a.dma + BOUNCE && n) ++f->bounce_syncs;
}
static void f_seal_header(uint8_t *p)
{ a_put32(p + 16, 0); a_put32(p + 16, a_crc32(p, a_le32(p + 12))); }
static void f_gpt(struct fake *f)
{
    unsigned table_bytes = 128 * 128, table_blocks = (table_bytes + f->sector - 1) / f->sector;
    uint8_t *table = f->disk + 2 * f->sector;
    memset(f->disk, 0, (2 + table_blocks) * f->sector);
    f->disk[510] = 0x55; f->disk[511] = 0xaa;
    f->disk[450] = 0xee; a_put32(f->disk + 454, 1); a_put32(f->disk + 458, f->blocks - 1);
    memset(table, 0, table_bytes);
    table[0] = 0xaf; table[16] = 1;
    a_put64(table + 32, 64); a_put64(table + 40, 255);
    /* Slot 2 is unused; slot 3 verifies stable GPT numbering with holes. */
    table[256] = 0xaf; table[272] = 2;
    a_put64(table + 288, 300); a_put64(table + 296, 301);
    unsigned backup_lba = f->blocks - 1 - table_blocks;
    memcpy(f->disk + (size_t)backup_lba * f->sector, table, table_bytes);
    for (unsigned i = 0; i < 2; ++i) {
        unsigned lba = i ? f->blocks - 1 : 1;
        uint8_t *h = f->disk + (size_t)lba * f->sector;
        memset(h, 0, f->sector); memcpy(h, "EFI PART", 8);
        a_put32(h + 8, 0x10000); a_put32(h + 12, 92);
        a_put64(h + 24, lba); a_put64(h + 32, i ? 1 : f->blocks - 1);
        a_put64(h + 40, 34); a_put64(h + 48, f->blocks - 34); h[56] = 0x42;
        a_put64(h + 72, i ? backup_lba : 2);
        a_put32(h + 80, 128); a_put32(h + 84, 128);
        a_put32(h + 88, a_crc32(table, table_bytes)); f_seal_header(h);
    }
}
static struct fake *f_new(unsigned sector)
{
    struct fake *f = calloc(1, sizeof(*f)); assert(f);
    f->sector = sector; f->blocks = 2048; f->fail_after = -1;
    f->disk = malloc((size_t)f->blocks * sector); assert(f->disk);
    for (size_t i = 0; i < (size_t)f->blocks * sector; ++i) f->disk[i] = (uint8_t)(i % 251);
    f->a.dma = aligned_alloc(ALIGNMENT, VINIX_ANS_DMA_BYTES); assert(f->a.dma);
    memset(f->a.dma, 0, VINIX_ANS_DMA_BYTES);
    f->a.physical = F_DMA; f->a.cookie = f;
    f->a.ops = (struct ans_ops){f_read32, f_write32, f_read64, f_write64, f_now, f_delay, f_sync};
    f->a.nvme = F_NVME; f->a.asc = F_ASC; f->a.mailbox = F_MB;
    f->a.sart = F_SART; f->a.reset = F_RESET;
    f->reset = 0x100000ff; f->cq_phase[0] = f->cq_phase[1] = 1;
    /* A bootloader-owned SART mapping must survive byte-for-byte. */
    f->sart[0] = 0xff001234; f->sart[16] = 0x81234;
    f_gpt(f); return f;
}
static void f_free(struct fake *f) { free(f->a.dma); free(f->disk); free(f); }
static void t_start(void)
{
    struct fake *f = f_new(4096); assert(a_start(&f->a) == 0);
    assert(f->a.live && f->a.stage == 7 && f->a.nns == 1);
    assert(f->a.ns[0].id == 1 && f->a.ns[0].sector == 4096);
    assert(f->a.ns[0].nparts == 2 && f->a.ns[0].parts[0].blocks == 192);
    assert(f->a.ns[0].parts[1].number == 3 && f->a.ns[0].parts[1].blocks == 2);
    assert(f->sart[0] == 0xff001234 && f->sart[16] == 0x81234);
    assert(f->a.sart_owned == 0x1e && f->a.shared_used == 4 * ALIGNMENT);
    assert(f->regs[A_INTMS / 4] == UINT32_MAX && f->regs[A_TCB_NUM / 4] == 63);
    assert(f->regs[A_LINEAR / 4] == 1 && f->regs[A_PENDING / 4] == 0x400040);
    f_free(f);
}
static void t_byte_reads(void)
{
    for (unsigned s = 512; s <= 4096; s *= 8) {
        struct fake *f = f_new(s); assert(!a_start(&f->a));
        const unsigned counts[] = {1, 511, 512, 4096, 8192, 8193, 65536, 100003};
        uint8_t *out = malloc(100100); assert(out);
        for (unsigned i = 0; i < sizeof(counts) / sizeof(counts[0]); ++i) {
            unsigned n = counts[i]; uint64_t off = 100u * s + 17;
            memset(out, 0xa5, n + 16);
            assert(!a_read_bytes(&f->a, 0, out + 8, off, n));
            assert(!memcmp(out + 8, f->disk + off, n));
            for (unsigned j = 0; j < 8; ++j) assert(out[j] == 0xa5 && out[8 + n + j] == 0xa5);
        }
        free(out); f_free(f);
    }
}
static void t_wrap(void)
{
    struct fake *f = f_new(512); assert(!a_start(&f->a)); uint8_t out[512];
    for (unsigned i = 0; i < 200; ++i) {
        assert(!a_read_bytes(&f->a, 0, out, (uint64_t)(64 + i) * 512, 512));
        assert(!memcmp(out, f->disk + (64 + i) * 512, 512));
    }
    assert(f->a.queues[1].head == f->cq_head[1] && f->a.queues[1].phase == f->cq_phase[1]);
    f_free(f);
}
static void t_ranges(void)
{
    struct fake *f = f_new(4096); assert(!a_start(&f->a)); uint8_t x;
    unsigned commands = f->commands;
    uint64_t size = (uint64_t)f->sector * f->blocks;
    assert(!a_read_bytes(&f->a, 0, NULL, size, 0));
    assert(a_read_bytes(&f->a, 0, &x, size, 1) == -ANS_RANGE);
    assert(a_read_bytes(&f->a, 0, &x, UINT64_MAX, 1) == -ANS_RANGE);
    assert(a_read_bytes(&f->a, 0, &x, 0, SIZE_MAX) == -ANS_RANGE);
    assert(a_read_bytes(&f->a, 1, &x, 0, 1) == -ANS_RANGE);
    assert(a_read_bytes(&f->a, 0, NULL, 0, 1) == -ANS_RANGE);
    assert(f->commands == commands);
    assert(!a_read_bytes(&f->a, 0, &x, size - 1, 1));
    f_free(f);
}
static void t_read_only(void)
{
    struct fake *f = f_new(512); assert(!a_start(&f->a));
    for (unsigned op = 0; op < 256; ++op) {
        uint8_t c[64] = {0}; c[0] = (uint8_t)op;
        if (op != 2) assert(a_submit(&f->a, 1, c, NULL) == -ANS_READ_ONLY);
    }
    const uint8_t forbidden[] = {0x80, 0x84, 0x10, 0x11, 0x0d, 0x15, 0xd8};
    unsigned n = f->commands;
    for (unsigned i = 0; i < sizeof(forbidden); ++i) {
        uint8_t c[64] = {0}; c[0] = forbidden[i];
        assert(a_submit(&f->a, 0, c, NULL) == -ANS_READ_ONLY);
    }
    uint8_t c[64] = {9}; a_put32(c + 40, 6); /* volatile write-cache feature also denied */
    assert(a_submit(&f->a, 0, c, NULL) == -ANS_READ_ONLY && f->commands == n);
    assert(!f->a.dead); f_free(f);
}
static void t_handoff(void)
{
    struct fake *f = f_new(512); f->cpu = ASC_RUN;
    assert(a_start(&f->a) == -ANS_HANDOFF && !f->writes); f_free(f);
    f = f_new(512); f->reset = 0;
    assert(a_start(&f->a) == -ANS_CONFIG && !f->writes); f_free(f);
    f = f_new(512); ++f->a.physical;
    assert(a_start(&f->a) == -ANS_CONFIG && !f->writes); f_free(f);
}
static void t_rtkit_failures(void)
{
    for (unsigned kind = 0; kind < 5; ++kind) {
        struct fake *f = f_new(512);
        if (kind == 0) f->stuck_send = 1;
        if (kind == 1) f->silent_firmware = 1;
        if (kind == 2) f->bad_version = 1;
        if (kind == 3) f->nonzero_iova = 1;
        if (kind == 4) for (unsigned i = 0; i < 16; ++i) f->sart[i] = 0xff000001;
        assert(a_start(&f->a) < 0 && f->a.dead && !f->commands);
        assert(f->now < BOOT_US + 100000); f_free(f);
    }
}
static void t_boot_timeouts(void)
{
    for (unsigned kind = 0; kind < 2; ++kind) {
        struct fake *f = f_new(512);
        if (kind == 0) f->bad_boot = 1; else f->bad_ready = 1;
        assert(a_start(&f->a) == -ANS_TIMEOUT && f->a.dead && !f->commands);
        f_free(f);
    }
}
static void t_timeout_pins_dma(void)
{
    for (unsigned frozen = 0; frozen < 2; ++frozen) {
        struct fake *f = f_new(512); assert(!a_start(&f->a));
        f->frozen_clock = (int)frozen; f->stall_command = 1; uint8_t out[512]; memset(out, 0xa5, sizeof(out));
        uint64_t now = f->now; uint8_t *dma = f->a.dma; uint16_t owned = f->a.sart_owned;
        assert(a_read_bytes(&f->a, 0, out, 100 * 512, 512) == -ANS_TIMEOUT);
        assert(f->a.dead && f->a.dma == dma && f->a.sart_owned == owned);
        /* Outstanding read TCB remains intact, not zeroed/recycled. */
        assert(f->a.dma[ITCB + 129] == 1 && f->a.dma[ITCB + 130] == 1);
        assert(a_le64(f->a.dma + ITCB + 128 + 24) == F_DMA + BOUNCE);
        for (unsigned i = 0; i < sizeof(out); ++i) assert(out[i] == 0xa5);
        unsigned writes = f->writes;
        assert(a_read_bytes(&f->a, 0, out, 0, 512) == -ANS_TIMEOUT && writes == f->writes);
        assert(frozen || f->now - now <= COMMAND_US + 100);
        f_free(f);
    }
}
static void t_completion_validation(void)
{
    for (unsigned kind = 0; kind < 4; ++kind) {
        struct fake *f = f_new(512); assert(!a_start(&f->a)); uint8_t out[512];
        if (kind == 0) f->bad_cid = 1;
        if (kind == 1) f->bad_qid = 1;
        if (kind == 2) f->bad_nvmmu = 1;
        if (kind == 3) f->wrong_phase = 1;
        assert(a_read_bytes(&f->a, 0, out, 0, 512) < 0 && f->a.dead); f_free(f);
    }
}
static void t_command_error(void)
{
    struct fake *f = f_new(512); assert(!a_start(&f->a));
    f->status = 0x4002; uint8_t out[512]; memset(out, 0xa5, sizeof(out));
    assert(a_read_bytes(&f->a, 0, out, 0, 512) == -ANS_COMPLETION && !f->a.dead);
    assert(f->a.last_status == 0x4002);
    for (unsigned i = 0; i < sizeof(out); ++i) assert(out[i] == 0xa5);
    f->status = 0; assert(!a_read_bytes(&f->a, 0, out, 0, 512)); f_free(f);
}
static void t_runtime_mailbox(void)
{
    struct fake *f = f_new(512); assert(!a_start(&f->a)); uint8_t out[512];
    f_queue(f, 2, TYPE(5) | 7); f_queue(f, 4, TYPE(8)); f_queue(f, 4, TYPE(12));
    assert(!a_read_bytes(&f->a, 0, out, 0, 512));
    while (f->mh != f->mt) assert(a_pump(&f->a) == 1);
    f->runtime_crash = 1;
    assert(a_read_bytes(&f->a, 0, out, 0, 512) == -ANS_FIRMWARE && f->a.dead);
    f_free(f);
}
static void t_mdts(void)
{
    struct fake *f = f_new(4096); f->mdts = 1; assert(!a_start(&f->a));
    assert(f->a.max_transfer == 8192); uint8_t out[20000]; unsigned reads = f->reads;
    assert(!a_read_bytes(&f->a, 0, out, 100 * 4096 + 1, sizeof(out)));
    assert(f->reads - reads == 3); assert(!memcmp(out, f->disk + 100 * 4096 + 1, sizeof(out)));
    f_free(f);
}
static void t_namespace_validation(void)
{
    struct fake *f = f_new(512); uint8_t p[4096]; struct ans_namespace ns;
    f_ns_id(f, p); assert(!a_parse_namespace(&ns, 1, p));
    for (unsigned kind = 0; kind < 8; ++kind) {
        f_ns_id(f, p);
        if (kind == 0) a_put64(p, 0);
        if (kind == 1) a_put64(p + 8, f->blocks + 1);
        if (kind == 2) p[26] = 1;
        if (kind == 3) p[26] = 0x10;
        if (kind == 4) p[29] = 1;
        if (kind == 5) a_put16(p + 128, 8);
        if (kind == 6) p[130] = 31;
        if (kind == 7) a_put64(p, UINT64_MAX);
        assert(a_parse_namespace(&ns, 1, p) == -ANS_NAMESPACE);
    }
    f_free(f);
}
static void t_gpt_backup_and_corruption(void)
{
    for (unsigned kind = 0; kind < 5; ++kind) {
        struct fake *f = f_new(512);
        if (kind == 0) f->disk[512 + 16] ^= 1; /* primary header CRC */
        if (kind == 1) f->disk[1024 + 100] ^= 1; /* primary array CRC */
        if (kind == 2) { f->disk[512 + 16] ^= 1; f->disk[(f->blocks - 1) * 512 + 16] ^= 1; }
        if (kind == 3) { /* two valid but conflicting headers */
            uint8_t *h = f->disk + (f->blocks - 1) * 512;
            h[56] ^= 1; f_seal_header(h);
        }
        if (kind == 4) f->disk[510] = 0;
        assert(!a_start(&f->a) && f->a.live);
        assert(f->a.ns[0].nparts == (kind < 2 ? 2u : 0u));
        f_free(f);
    }
}
static void t_gpt_extents(void)
{
    struct fake *f = f_new(512); struct ans_namespace ns = {.sector = 512, .blocks = 2048};
    struct ans_gpt h; uint8_t header[512], table[16384];
    memcpy(header, f->disk + 512, 512);
    assert(!a_gpt_header(&ns, header, 1, &h));
    for (unsigned kind = 0; kind < 4; ++kind) {
        memcpy(table, f->disk + 1024, sizeof(table));
        if (kind == 0) a_put64(table + 32, 0);
        if (kind == 1) a_put64(table + 40, UINT64_MAX);
        if (kind == 2) a_put64(table + 288, 255); /* inclusive overlap */
        if (kind == 3) memcpy(table + 272, table + 16, 16); /* duplicate GUID */
        h.table_crc = a_crc32(table, sizeof(table));
        ns.nparts = 0; assert(a_gpt_entries(&ns, &h, table) == -ANS_GPT && ns.nparts == 0);
    }
    for (unsigned kind = 0; kind < 4; ++kind) {
        memcpy(header, f->disk + 512, 512);
        if (kind == 0) a_put32(header + 80, UINT32_MAX);
        if (kind == 1) a_put32(header + 84, UINT32_MAX);
        if (kind == 2) a_put64(header + 72, UINT64_MAX);
        if (kind == 3) a_put64(header + 72, 34);
        f_seal_header(header); assert(a_gpt_header(&ns, header, 1, &h) == -ANS_GPT);
    }
    f_free(f);
}
static void t_cmdline(void)
{
#define REQUEST(s) vinix_ans_requested(s, sizeof(s) - 1)
    assert(REQUEST("vinix.apple_ans=1"));
    assert(REQUEST("foo=2\tvinix.apple_ans=1\nbar=3"));
    assert(!REQUEST("xvinix.apple_ans=1")); assert(!REQUEST("vinix.apple_ans=10"));
    assert(!REQUEST("vinix.apple_ans=1 vinix.apple_ans=0"));
    assert(!REQUEST("vinix.apple_ans=0 vinix.apple_ans=1"));
    assert(!REQUEST("")); assert(!vinix_ans_requested(NULL, 4));
}
static uint32_t rng = 0xa4523817;
static uint32_t random32(void)
{ rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng; }
static void t_mutation(void)
{
    struct fake *f = f_new(512); uint8_t p[4096], header[512];
    struct ans_namespace ns = {.sector = 512, .blocks = 2048}; struct ans_gpt h;
    for (unsigned i = 0; i < 10000; ++i) {
        f_ns_id(f, p);
        for (unsigned j = 0; j < 8; ++j) p[random32() % 192] ^= (uint8_t)random32();
        if (!a_parse_namespace(&ns, 1, p)) {
            assert(ns.sector == 512 || ns.sector == 4096);
            assert(ns.blocks && ns.blocks <= (uint64_t)INT64_MAX / ns.sector);
        }
        ns.sector = 512; ns.blocks = 2048;
        memcpy(header, f->disk + 512, 512);
        for (unsigned j = 0; j < 6; ++j) header[random32() % 92] ^= (uint8_t)random32();
        if (i & 1) { a_put32(header + 12, 92); f_seal_header(header); }
        if (!a_gpt_header(&ns, header, 1, &h)) {
            assert(h.entries <= 128 && h.entry_size <= 1024);
            assert(h.table < h.first && h.last < ns.blocks - 1);
        }
    }
    f_free(f);
}
static void run(void (*test)(void), const char *name)
{ test(); printf("ok %u - %s\n", ++groups, name); }
#include "test_rw.h"
static void t_root_partition_bridge(void)
{
    for (unsigned sector = 512; sector <= 4096; sector *= 8) {
        struct fake *f = f_new(sector);
        rw_gpt(f);
        uint8_t *entry = f->disk + 2 * sector;
        a_put64(entry + 40, 767);
        memset(entry + 256, 0, 128); /* remove the old slot-3 partition */
        unsigned table_bytes = 128 * 128;
        unsigned backup = f->blocks - 1 - table_bytes / sector;
        memcpy(f->disk + (size_t)backup * sector, entry, table_bytes);
        for (unsigned i = 0; i < 2; ++i) {
            uint8_t *h = f->disk + (size_t)(i ? f->blocks - 1 : 1) * sector;
            a_put32(h + 88, a_crc32(entry, table_bytes)); f_seal_header(h);
        }
        struct image im; setup(&im, 1024, 128);
        assert(im.bytes <= (768 - 64) * sector);
        memcpy(f->disk + 64 * sector, im.data, im.bytes);
        assert(!a_start(&f->a));
        const char *text = "vinix.apple_ans=1 vinix.root=PARTUUID=00000001-0000-0000-0000-000000000000 vinix.rootfstype=ext2 vinix.rootmode=ro";
        struct ans_policy policy;
        assert(!a_parse_policy(text, strlen(text), &policy));
        assert(!a_apply_policy(&f->a, &policy));
        struct e2_fs fs; assert(!a_open_root(&f->a, &fs, sizeof(fs)));
        uint64_t fields[10]; assert(!vinix_ext2_stat(&fs, 12, fields) && fields[0] == 3072);
        uint8_t data[3072]; assert(vinix_ext2_read(&fs, 12, data, 0, sizeof(data)) == 3072);
        for (unsigned i = 0; i < sizeof(data); ++i)
            assert(data[i] == (i < 1024 ? 0x31 : i < 2048 ? 0 : 0x72));
        unsigned commands = f->commands;
        assert(a_root_disk(&f->a, data, (uint64_t)(768 - 64) * sector - 1, 2) == -ANS_RANGE);
        assert(f->commands == commands && f->media_writes == 0 && !f->a.write_enabled);
        f->fail_opcode = 2; f->fail_on_queue = 1; f->fail_after = 0;
        assert(vinix_ext2_read(&fs, 12, data, 0, sizeof(data)) == E2_IO);
        destroy(&im); f_free(f);
    }
}
int main(void)
{
    assert(a_crc32((const uint8_t *)"123456789", 9) == 0xcbf43926u);
    run(t_start, "RTKit/SART/ANS startup and GPT to block views");
    run(t_byte_reads, "512/4096-byte LBAs, unaligned reads and all PRP forms");
    run(t_wrap, "200 I/O completions across CQ phase wraps");
    run(t_ranges, "EOF, null, index and integer overflow bounds");
    run(t_read_only, "lowest-layer read-only opcode whitelist");
    run(t_handoff, "unclean handoff and invalid resources perform no writes");
    run(t_rtkit_failures, "RTKit timeout/version/address and exhausted SART");
    run(t_boot_timeouts, "ANS boot and NVMe ready timeouts");
    run(t_timeout_pins_dma, "timeouts including stopped clock pin outstanding DMA");
    run(t_completion_validation, "wrong tags, queues, phase and NVMMU errors");
    run(t_command_error, "NVMe status propagation and subsequent recovery");
    run(t_runtime_mailbox, "runtime system messages and firmware crash");
    run(t_mdts, "MDTS-bounded chunked reads");
    run(t_namespace_validation, "namespace metadata and format validation");
    run(t_gpt_backup_and_corruption, "backup GPT, both CRCs and conflicting copies");
    run(t_gpt_extents, "GPT overlap, inclusive end, GUID and allocation bounds");
    run(t_cmdline, "exact-token opt-in and disable precedence");
    run(t_mutation, "10000 deterministic namespace and GPT mutations");
    run_rw_tests();
    run(t_root_partition_bridge, "ANS DMA to partition-scoped ext2 reads (512/4096-byte LBAs)");
    printf("PASS: %u test groups\n", groups); return 0;
}
