/* SPDX-License-Identifier: GPL-2.0-or-later
 * Private, byte-oriented GPT decoder for the ANS block views.
 * Included by apple_ans.c; no packed-struct or unaligned integer accesses.
 */
#ifndef VINIX_APPLE_ANS_GPT_H
#define VINIX_APPLE_ANS_GPT_H
struct ans_gpt {
    uint64_t first, last, table;
    uint32_t entries, entry_size, table_crc;
    uint8_t guid[16];
};
static uint32_t a_crc32(const uint8_t *p, size_t n)
{
    uint32_t crc = UINT32_MAX;
    while (n--) {
        crc ^= *p++;
        for (unsigned b = 0; b < 8; ++b)
            crc = (crc >> 1) ^ ((crc & 1u) ? 0xedb88320u : 0);
    }
    return ~crc;
}
static int a_gpt_header(const struct ans_namespace *ns, uint8_t *p,
    uint64_t lba, struct ans_gpt *out)
{
    static const uint8_t signature[] = {'E','F','I',' ','P','A','R','T'};
    if (ns->blocks < 6 || !a_equal(p, signature, 8) || a_le32(p + 8) != 0x10000u ||
        a_le32(p + 20) || a_le64(p + 24) != lba ||
        a_le64(p + 32) != (lba == 1 ? ns->blocks - 1 : 1)) return -ANS_GPT;
    unsigned bytes = a_le32(p + 12);
    if (bytes < 92 || bytes > ns->sector) return -ANS_GPT;
    uint32_t expected = a_le32(p + 16);
    a_put32(p + 16, 0);
    uint32_t actual = a_crc32(p, bytes);
    a_put32(p + 16, expected);
    if (actual != expected) return -ANS_GPT;
    struct ans_gpt h = {0};
    h.first = a_le64(p + 40); h.last = a_le64(p + 48); h.table = a_le64(p + 72);
    h.entries = a_le32(p + 80); h.entry_size = a_le32(p + 84);
    h.table_crc = a_le32(p + 88); a_copy(h.guid, p + 56, 16);
    if (!h.entries || h.entries > VINIX_ANS_MAX_PARTS ||
        h.entry_size < 128 || h.entry_size > 1024 || (h.entry_size & (h.entry_size - 1)) ||
        h.first < 2 || h.first > h.last || h.last >= ns->blocks - 1)
        return -ANS_GPT;
    uint64_t table_bytes = (uint64_t)h.entries * h.entry_size;
    uint64_t table_blocks = (table_bytes + ns->sector - 1) / ns->sector;
    if (table_bytes > GPT_MAX_BYTES || h.table >= ns->blocks ||
        table_blocks > ns->blocks - h.table) return -ANS_GPT;
    if (lba == 1) {
        if (h.table < 2 || h.table >= h.first || table_blocks > h.first - h.table)
            return -ANS_GPT;
    } else if (h.table <= h.last || h.table >= lba || table_blocks > lba - h.table)
        return -ANS_GPT;
    *out = h;
    return 0;
}
static int a_gpt_entries(struct ans_namespace *ns, const struct ans_gpt *h,
    const uint8_t *table)
{
    uint8_t zero_guid[16] = {0};
    if (a_crc32(table, (size_t)h->entries * h->entry_size) != h->table_crc)
        return -ANS_GPT;
    /* Validate the entire array before publishing even its first entry. */
    for (unsigned i = 0; i < h->entries; ++i) {
        const uint8_t *p = table + i * h->entry_size;
        if (a_equal(p, zero_guid, 16)) continue;
        uint64_t first = a_le64(p + 32), last = a_le64(p + 40);
        if (a_equal(p + 16, zero_guid, 16) || first < h->first || last > h->last || first > last)
            return -ANS_GPT;
        for (unsigned j = 0; j < i; ++j) {
            const uint8_t *q = table + j * h->entry_size;
            if (a_equal(q, zero_guid, 16)) continue;
            if (a_equal(p + 16, q + 16, 16) ||
                (first <= a_le64(q + 40) && a_le64(q + 32) <= last))
                return -ANS_GPT;
        }
    }
    ns->nparts = 0;
    for (unsigned i = 0; i < h->entries; ++i) {
        const uint8_t *p = table + i * h->entry_size;
        if (a_equal(p, zero_guid, 16)) continue;
        struct ans_partition *part = &ns->parts[ns->nparts++];
        a_copy(part->type_guid, p, 16); a_copy(part->guid, p + 16, 16);
        part->attributes = a_le64(p + 48);
        part->number = i + 1; /* GPT slot numbers, including unused holes */
        part->start = a_le64(p + 32);
        part->blocks = a_le64(p + 40) - part->start + 1; /* inclusive end */
    }
    return 0;
}
static int a_scan_gpt(struct ans *a, unsigned index)
{
    struct ans_namespace *ns = &a->ns[index];
    uint8_t sector[4096];
    struct ans_gpt h[2] = {{0}, {0}};
    int valid[2] = {0, 0};
    ns->nparts = 0; ns->gpt_complete = 0; ns->gpt_hybrid = 0;
    if (ns->blocks < 6 || a_read_bytes(a, index, sector, 0, ns->sector)) return -ANS_GPT;
    if (sector[510] != 0x55 || sector[511] != 0xaa) return -ANS_GPT;
    int protective = 0;
    for (unsigned i = 0; i < 4; ++i) {
        const uint8_t *p = sector + 446 + i * 16;
        if (p[4] == 0xee && a_le32(p + 8) == 1 && a_le32(p + 12)) protective = 1;
        else if (p[4]) ns->gpt_hybrid = 1;
    }
    if (!protective) return -ANS_GPT;
    for (unsigned i = 0; i < 2; ++i) {
        uint64_t lba = i ? ns->blocks - 1 : 1;
        if (!a_read_bytes(a, index, sector, lba * ns->sector, ns->sector))
            valid[i] = !a_gpt_header(ns, sector, lba, &h[i]);
        if (a->dead) return -a->error;
    }
    if (valid[0] && valid[1] && (h[0].first != h[1].first || h[0].last != h[1].last ||
        h[0].entries != h[1].entries || h[0].entry_size != h[1].entry_size ||
        h[0].table_crc != h[1].table_crc || !a_equal(h[0].guid, h[1].guid, 16)))
        return -ANS_GPT; /* Never guess between two valid but conflicting GPTs. */
    for (unsigned i = 0; i < 2; ++i) {
        if (!valid[i]) continue;
        if (a_read_bytes(a, index, a->dma + GPT_SCRATCH, h[i].table * ns->sector,
            (size_t)h[i].entries * h[i].entry_size)) {
            if (a->dead) return -a->error;
            continue;
        }
        if (!a_gpt_entries(ns, &h[i], a->dma + GPT_SCRATCH)) {
            /* Write opt-in requires both tables to be byte-identical, not just
             * equal CRC32s. A single intact copy still permits read-only recovery. */
            if (valid[0] && valid[1]) {
                size_t total = (size_t)h[i].entries * h[i].entry_size, off = 0;
                while (off < total) {
                    size_t n = total - off; if (n > sizeof(sector)) n = sizeof(sector);
                    if (a_read_bytes(a, index, sector, h[1-i].table * ns->sector + off, n) ||
                        !a_equal(sector, a->dma + GPT_SCRATCH + off, n)) break;
                    off += n;
                }
                if (a->dead) { ns->nparts = 0; return -a->error; }
                ns->gpt_complete = off == total;
            }
            return 0;
        }
    }
    return -ANS_GPT;
}
#endif
