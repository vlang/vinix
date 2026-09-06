/* SPDX-License-Identifier: GPL-2.0-or-later
 * Single-flight partition writes, real Flush and ordered controller shutdown.
 */
#ifndef VINIX_APPLE_ANS_RW_H
#define VINIX_APPLE_ANS_RW_H
#define A_SHUTDOWN_US UINT64_C(30000000)
static int a_flush_ns(struct ans *a, unsigned index)
{
    if (a->dead) return -a->error;
    if (a->stopped || index >= a->nns) return -ANS_STOPPED;
    uint8_t c[64] = {0}; a_put32(c + 4, a->ns[index].id);
    int rc = a_submit(a, 1, c, NULL);
    if (rc) { a->write_fault = 1; return a_fail(a, -rc); }
    a->dirty_namespaces &= (uint16_t)~(1u << index);
    ++a->flushes_completed; return 0;
}
static int a_flush_all(struct ans *a)
{
    if (!a->started || a->stopped) return 0;
    if (a->dead) return -a->error;
    if (!a->ioq_active) return -ANS_STOPPED;
    for (unsigned i = 0; i < a->nns; ++i) { int rc = a_flush_ns(a, i); if (rc) return rc; }
    return 0;
}
static int a_write_partition(struct ans *a, unsigned index, unsigned part,
    const void *buffer, uint64_t offset, size_t count)
{
    if (a->dead) return -a->error;
    if (!a->live || a->stopping || a->stopped) return -ANS_STOPPED;
    if (!a->write_enabled || a->write_fault || index != a->write_ns || part != a->write_part)
        return -ANS_READ_ONLY;
    if (index >= a->nns || part >= a->ns[index].nparts || (!buffer && count)) return -ANS_RANGE;
    const struct ans_namespace *ns = &a->ns[index];
    const struct ans_partition *p = &ns->parts[part];
    uint64_t limit = p->blocks * ns->sector;
    if (offset > limit || count > limit - offset) return -ANS_RANGE;
    if (!count) return 0;
    const uint8_t *in = buffer; uint64_t absolute = p->start * ns->sector + offset;
    while (count) {
        unsigned within = (unsigned)(absolute % ns->sector);
        size_t bytes = a->max_transfer - within; if (bytes > count) bytes = count;
        unsigned sectors = (unsigned)((within + bytes + ns->sector - 1) / ns->sector);
        unsigned transfer = sectors * ns->sector; uint64_t lba = absolute / ns->sector;
        /* The V lock spans the RMW. Complete boundary LBAs remain inside the
         * selected partition. Full-LBA writes never read stale bounce data. */
        if (within || bytes != transfer) {
            int rc = a_read_bytes(a, index, a->dma + BOUNCE, lba * ns->sector, transfer);
            if (rc) { a->write_fault = 1; return a_fail(a, -rc); }
        }
        a_copy(a->dma + BOUNCE + within, in, bytes);
        uint8_t c[64] = {0}; c[0] = 1;
        a_put32(c + 4, ns->id); a_put64(c + 40, lba);
        a_put16(c + 48, (uint16_t)(sectors - 1)); a_put16(c + 50, 0x4000u); /* FUA */
        a_data_prps(a, c, transfer); a_sync(a, BOUNCE, transfer, 0);
        a->dirty_namespaces |= (uint16_t)(1u << index);
        int rc = a_submit(a, 1, c, NULL);
        if (rc) {
            /* An error can mean a partial media change. Never retry or recycle
             * the failed request; don't pretend to have rolled it back. */
            a->write_fault = 1; return a_fail(a, -rc);
        }
        ++a->writes_completed;
        absolute += bytes; in += bytes; count -= bytes;
    }
    return a_flush_ns(a, index); /* no success before persistence barrier */
}
static int a_power_state(struct ans *a, int ap, unsigned state)
{
    if (ap) a->ap_power = UINT32_MAX; else a->iop_power = UINT32_MAX;
    if (a_send(a, 0, TYPE(ap ? 11 : 6) | state)) return -a->error;
    struct a_deadline deadline = a_begin(a);
    for (unsigned i = 0; i < 1000000; ++i) {
        if (a_pump(a) < 0) return -a->error;
        if ((ap ? a->ap_power : a->iop_power) == state) return 0;
        if (a_expired(a, &deadline, BOOT_US)) break;
        a->ops.delay(a->cookie, 10);
    }
    return a_fail(a, ANS_TIMEOUT);
}
static int a_shutdown(struct ans *a)
{
    if (!a->started || a->stopped) return 0;
    if (a->dead) return -a->error;
    if (!a->live || a->stopping) return -ANS_STOPPED;
    a->stopping = 1; a->stage = 8;
    int rc = a_flush_all(a); if (rc) return rc;
    if (a->ioq_active) {
        uint8_t c[64] = {0}; a_put16(c + 40, 1); /* Delete SQ 1 */
        rc = a_submit(a, 0, c, NULL); if (rc) return a_fail(a, -rc);
        c[0] = 4; rc = a_submit(a, 0, c, NULL); if (rc) return a_fail(a, -rc);
        a->ioq_active = 0;
    }
    a->stage = 9; uint32_t cc = a_r32(a, a->nvme, A_CC);
    /* SHN=normal -> SHST=complete -> EN=0 -> RDY=0, never a reset. */
    a_w32(a, a->nvme, A_CC, (cc & ~(3u << 14)) | (1u << 14));
    if (a_wait32(a, A_CSTS, 3u << 2, 2u << 2, A_SHUTDOWN_US)) return -a->error;
    a_w32(a, a->nvme, A_CC, cc & ~(1u | (3u << 14)));
    if (a_wait32(a, A_CSTS, 1, 0, READY_US)) return -a->error;
    a->stage = 10;
    if (a_power_state(a, 1, 0x10) || a_power_state(a, 0, 1)) return -a->error;
    a_w32(a, a->asc, ASC_CPU, a_r32(a, a->asc, ASC_CPU) & ~ASC_RUN);
    if (a_r32(a, a->asc, ASC_CPU) & ASC_RUN) return a_fail(a, ANS_FIRMWARE);
    /* Revoke only extents still matching our ownership record. All DMA memory
     * remains pinned even on successful shutdown; failures must not free it. */
    for (unsigned i = 0; i < 16; ++i) {
        if (!(a->sart_owned & (1u << i))) continue;
        if (a_r32(a, a->sart, i * 4) != (0xff000000u | (a->sart_bytes[i] >> 12)) ||
            a_r32(a, a->sart, 0x40 + i * 4) != (uint32_t)(a->sart_pa[i] >> 12))
            return a_fail(a, ANS_SART);
    }
    for (unsigned i = 0; i < 16; ++i) {
        if (!(a->sart_owned & (1u << i))) continue;
        a_w32(a, a->sart, i * 4, 0);
        if (a_r32(a, a->sart, i * 4)) return a_fail(a, ANS_SART);
        a_w32(a, a->sart, 0x40 + i * 4, 0);
    }
    a->sart_owned = 0; a->live = 0; a->stopped = 1; a->stage = 11; return 0;
}
#endif
