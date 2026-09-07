/* SPDX-License-Identifier: GPL-2.0-or-later
 * Bounded classic-ext2 reader/writer. Layout references:
 * docs.kernel.org/filesystems/ext2.html and ext4/{super,inodes,directory}.html.
 * Does not invoke Vinix's legacy ext2 allocator or assume 512-byte device LBAs.
 * Writable operation is intentionally limited to non-journaled, non-indexed
 * ext2. Metadata is written in leak-before-corruption order and a dirty mount
 * is refused; recovery after an interrupted mutation belongs to an external
 * fsck, not to this small kernel driver.
 */
#include "apple_ans_ext2.h"
#define E2_IO (-5)
#define E2_INVALID (-22)
#define E2_UNSUPPORTED (-95)
#define E2_EXIST (-17)
#define E2_NOTDIR (-20)
#define E2_ISDIR (-21)
#define E2_NOSPC (-28)
#define E2_ROFS (-30)
#define E2_NAMETOOLONG (-36)
#define E2_NOTEMPTY (-39)
#define E2_FBIG (-27)
#define E2_DIRECTORY 0x4000u
#define E2_REGULAR 0x8000u
#define E2_SYMLINK 0xa000u
struct e2_fs {
    vinix_ext2_reader read;
    vinix_ext2_writer write;
    void *cookie;
    uint64_t bytes;
    uint32_t block_size, inode_size, blocks, inodes, first;
    uint32_t bpg, ipg, groups, first_inode, filetype, largefile, opened;
    uint32_t writable, active, failed;
};
struct e2_inode {
    uint64_t size;
    uint32_t mode, uid, gid, links, sectors, flags, times[3], ptr[15];
    uint8_t data[60];
    int fast_link;
};
static uint16_t e2_u16(const uint8_t *p)
{ return (uint16_t)(p[0] | (uint16_t)p[1] << 8); }
static uint32_t e2_u32(const uint8_t *p)
{ return (uint32_t)e2_u16(p) | (uint32_t)e2_u16(p + 2) << 16; }
static void e2_p16(uint8_t *p, uint16_t v)
{ p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }
static void e2_p32(uint8_t *p, uint32_t v)
{ e2_p16(p, (uint16_t)v); e2_p16(p + 2, (uint16_t)(v >> 16)); }
static void e2_zero(void *p, size_t n)
{ uint8_t *b = p; while (n--) *b++ = 0; }
static void e2_copy(void *d, const void *s, size_t n)
{ uint8_t *a = d; const uint8_t *b = s; while (n--) *a++ = *b++; }
static int e2_disk(struct e2_fs *fs, void *p, uint64_t off, size_t n)
{
    if (!fs || !fs->opened || !fs->read || (!p && n) || off > fs->bytes || n > fs->bytes - off)
        return E2_INVALID;
    return fs->read(fs->cookie, p, off, n) ? E2_IO : 0;
}
static int e2_store(struct e2_fs *fs, const void *p, uint64_t off, size_t n)
{
    if (!fs || !fs->opened || !fs->writable || !fs->active || !fs->write ||
        (!p && n) || off > fs->bytes || n > fs->bytes - off) return E2_ROFS;
    if (fs->write(fs->cookie, p, off, n)) {
        /* A failed metadata or data transfer may have reached the SSD only in
         * part. Freeze this mount and keep the superblock dirty for fsck. */
        fs->failed = 1;
        fs->active = 0;
        return E2_IO;
    }
    return 0;
}
static int e2_block_valid(const struct e2_fs *fs, uint32_t block)
{ return block >= fs->first && block < fs->blocks && block != 0; }
static int e2_inode_get(struct e2_fs *fs, uint32_t ino, struct e2_inode *out)
{
    uint8_t desc[32], raw[128];
    if (!fs || !fs->opened || !out || !ino || ino > fs->inodes) return E2_INVALID;
    uint32_t group = (ino - 1) / fs->ipg, slot = (ino - 1) % fs->ipg;
    if (group >= fs->groups) return E2_INVALID;
    uint64_t bgdt = (uint64_t)(fs->first + 1) * fs->block_size;
    if (e2_disk(fs, desc, bgdt + (uint64_t)group * 32, sizeof(desc))) return E2_IO;
    uint32_t table = e2_u32(desc + 8);
    uint64_t group_first = fs->first + (uint64_t)group * fs->bpg;
    uint64_t group_end = group_first + fs->bpg;
    if (group_end > fs->blocks) group_end = fs->blocks;
    uint64_t table_blocks = ((uint64_t)fs->ipg * fs->inode_size + fs->block_size - 1) / fs->block_size;
    if (!e2_block_valid(fs, table) || table < group_first || table >= group_end ||
        table_blocks > group_end - table) return E2_INVALID;
    if (e2_disk(fs, raw, (uint64_t)table * fs->block_size + (uint64_t)slot * fs->inode_size,
        sizeof(raw))) return E2_IO;
    struct e2_inode v = {0};
    v.mode = e2_u16(raw); v.links = e2_u16(raw + 26);
    uint32_t kind = v.mode & 0xf000u, flags = e2_u32(raw + 32);
    /* Reject encodings this reader does not implement, not just extents. */
    if ((kind != E2_DIRECTORY && kind != E2_REGULAR && kind != E2_SYMLINK) ||
        !v.links || e2_u32(raw + 20) || (flags & ~(0x10u | 0x20u | 0x40u | 0x80u | 0x1000u)))
        return E2_UNSUPPORTED;
    v.flags = flags; v.size = e2_u32(raw + 4);
    if (kind == E2_REGULAR) {
        uint32_t high = e2_u32(raw + 108);
        if (high && !fs->largefile) return E2_UNSUPPORTED;
        v.size |= (uint64_t)high << 32;
    }
    uint64_t per = fs->block_size / 4;
    uint64_t max_blocks = 12 + per + per * per + per * per * per;
    if (v.size > max_blocks * fs->block_size || v.size > INT64_MAX ||
        (kind == E2_DIRECTORY && (v.size > 0x4000000u || v.size % fs->block_size)) ||
        (kind == E2_SYMLINK && (!v.size || v.size > 4095))) return E2_INVALID;
    v.uid = e2_u16(raw + 2) | (uint32_t)e2_u16(raw + 120) << 16;
    v.gid = e2_u16(raw + 24) | (uint32_t)e2_u16(raw + 122) << 16;
    v.sectors = e2_u32(raw + 28);
    v.times[0] = e2_u32(raw + 8); v.times[1] = e2_u32(raw + 16); v.times[2] = e2_u32(raw + 12);
    for (unsigned i = 0; i < 15; ++i) v.ptr[i] = e2_u32(raw + 40 + i * 4);
    e2_copy(v.data, raw + 40, 60);
    uint32_t acl = e2_u32(raw + 104);
    if (acl && !e2_block_valid(fs, acl)) return E2_INVALID;
    v.fast_link = kind == E2_SYMLINK && v.size <= 60 &&
        v.sectors == (acl ? fs->block_size / 512 : 0);
    *out = v; return 0;
}
static int e2_map(struct e2_fs *fs, const struct e2_inode *in, uint64_t logical, uint32_t *out)
{
    if (logical < 12) { *out = in->ptr[logical]; return !*out || e2_block_valid(fs, *out) ? 0 : E2_INVALID; }
    uint64_t per = fs->block_size / 4, span = per;
    logical -= 12;
    unsigned level = 1;
    while (level < 3 && logical >= span) { logical -= span; span *= per; ++level; }
    if (logical >= span) return E2_INVALID;
    uint32_t block = in->ptr[11 + level];
    for (; level; --level) {
        if (!block) { *out = 0; return 0; }
        if (!e2_block_valid(fs, block)) return E2_INVALID;
        span /= per;
        uint64_t index = logical / span;
        logical %= span;
        uint8_t raw[4];
        if (e2_disk(fs, raw, (uint64_t)block * fs->block_size + index * 4, 4)) return E2_IO;
        block = e2_u32(raw);
    }
    if (block && !e2_block_valid(fs, block)) return E2_INVALID;
    *out = block; return 0;
}
static int64_t e2_read_inode(struct e2_fs *fs, const struct e2_inode *in,
    void *buffer, uint64_t offset, size_t count)
{
    if ((!buffer && count) || offset > in->size) return E2_INVALID;
    if (count > in->size - offset) count = (size_t)(in->size - offset);
    if (count > 0x100000u) count = 0x100000u;
    uint8_t *p = buffer;
    if (in->fast_link) { e2_copy(p, in->data + offset, count); return (int64_t)count; }
    size_t done = 0;
    while (done < count) {
        uint64_t pos = offset + done;
        unsigned within = (unsigned)(pos % fs->block_size);
        size_t n = fs->block_size - within;
        if (n > count - done) n = count - done;
        uint32_t block;
        int rc = e2_map(fs, in, pos / fs->block_size, &block);
        if (rc) return rc;
        if (!block) e2_zero(p + done, n);
        else if (e2_disk(fs, p + done, (uint64_t)block * fs->block_size + within, n)) return E2_IO;
        done += n;
    }
    return (int64_t)done;
}
size_t vinix_ext2_context_size(void) { return sizeof(struct e2_fs); }
static int e2_open(void *context, size_t size, vinix_ext2_reader read,
    vinix_ext2_writer write, void *cookie, uint64_t bytes)
{
    if (!context || size < sizeof(struct e2_fs) || !read || bytes < 4096) return E2_INVALID;
    e2_zero(context, sizeof(struct e2_fs));
    uint8_t sb[1024];
    if (read(cookie, sb, 1024, sizeof(sb))) return E2_IO;
    unsigned revision = e2_u32(sb + 76), shift = e2_u32(sb + 24);
    if (e2_u16(sb + 56) != 0xef53 || revision > 1 || shift > 2 || e2_u32(sb + 72) != 0 ||
        e2_u16(sb + 58) != 1 || e2_u32(sb + 232) || e2_u32(sb + 28) != shift)
        return E2_UNSUPPORTED;
    uint32_t compat = revision ? e2_u32(sb + 92) : 0;
    uint32_t incompat = revision ? e2_u32(sb + 96) : 0;
    uint32_t rocompat = revision ? e2_u32(sb + 100) : 0;
    /* Classic ext2 only: ext_attr, resize_inode, dir_index, FILETYPE,
     * sparse_super and large_file. No journal/recovery, extents or checksums. */
    if ((compat & ~0x38u) || (incompat & ~2u) || (rocompat & ~3u) ||
        (write && ((compat & ~0x08u) || !(incompat & 2u)))) return E2_UNSUPPORTED;
    struct e2_fs fs = {0};
    fs.block_size = 1024u << shift;
    fs.inode_size = revision ? e2_u16(sb + 88) : 128;
    fs.blocks = e2_u32(sb + 4); fs.inodes = e2_u32(sb);
    fs.first = e2_u32(sb + 20); fs.bpg = e2_u32(sb + 32); fs.ipg = e2_u32(sb + 40);
    fs.first_inode = revision ? e2_u32(sb + 84) : 11;
    /* Older read-only fixtures and revision-1 images produced by early tools
     * sometimes leave s_first_ino zero. Never accept that ambiguity for a
     * writable mount, but retain the established read-only compatibility. */
    if (!write && !fs.first_inode) fs.first_inode = 11;
    if (fs.first != (shift ? 0u : 1u) || fs.blocks <= fs.first + 2 || fs.inodes < 2 ||
        !fs.bpg || fs.bpg > fs.block_size * 8 || !fs.ipg || fs.ipg > fs.block_size * 8 ||
        fs.inode_size < 128 || fs.inode_size > fs.block_size || (fs.inode_size & (fs.inode_size - 1)) ||
        e2_u32(sb + 36) != fs.bpg || fs.first_inode < 11 || fs.first_inode > fs.inodes ||
        (uint64_t)fs.blocks * fs.block_size > bytes)
        return E2_INVALID;
    fs.groups = (uint32_t)(((uint64_t)fs.blocks - fs.first + fs.bpg - 1) / fs.bpg);
    if (((uint64_t)fs.inodes + fs.ipg - 1) / fs.ipg > fs.groups ||
        (uint64_t)(fs.first + 1) * fs.block_size + (uint64_t)fs.groups * 32 > (uint64_t)fs.blocks * fs.block_size)
        return E2_INVALID;
    fs.bytes = (uint64_t)fs.blocks * fs.block_size;
    fs.cookie = cookie; fs.read = read; fs.write = write; fs.opened = 1;
    fs.writable = write != NULL;
    fs.filetype = incompat & 2; fs.largefile = rocompat & 2;
    struct e2_inode root;
    int rc = e2_inode_get(&fs, 2, &root);
    if (rc || (root.mode & 0xf000u) != E2_DIRECTORY || !root.size) return rc ? rc : E2_INVALID;
    e2_copy(context, &fs, sizeof(fs)); return 0;
}
int vinix_ext2_open(void *context, size_t size, vinix_ext2_reader read,
    void *cookie, uint64_t bytes)
{ return e2_open(context, size, read, NULL, cookie, bytes); }
int vinix_ext2_open_rw(void *context, size_t size, vinix_ext2_reader read,
    vinix_ext2_writer write, void *cookie, uint64_t bytes)
{
    if (!write) return E2_INVALID;
    return e2_open(context, size, read, write, cookie, bytes);
}
int vinix_ext2_begin_write(void *context)
{
    struct e2_fs *fs = context;
    if (!fs || !fs->opened || !fs->writable || fs->active) return E2_INVALID;
    uint8_t state[2]; e2_p16(state, 2);
    fs->active = 1;
    int rc = e2_store(fs, state, 1024 + 58, sizeof(state));
    if (rc) fs->active = 0;
    return rc;
}
int vinix_ext2_close_clean(void *context)
{
    struct e2_fs *fs = context;
    if (!fs || !fs->opened || !fs->writable) return E2_INVALID;
    if (fs->failed) return E2_IO;
    if (!fs->active) return 0;
    uint8_t state[2]; e2_p16(state, 1);
    int rc = e2_store(fs, state, 1024 + 58, sizeof(state));
    if (!rc) fs->active = 0;
    return rc;
}
int vinix_ext2_stat(void *context, uint32_t ino, uint64_t fields[10])
{
    if (!fields) return E2_INVALID;
    struct e2_fs *fs = context; struct e2_inode in;
    int rc = e2_inode_get(fs, ino, &in); if (rc) return rc;
    fields[0] = in.size; fields[1] = in.mode; fields[2] = in.uid; fields[3] = in.gid;
    fields[4] = in.links; fields[5] = in.sectors;
    for (unsigned i = 0; i < 3; ++i) fields[6+i] = in.times[i];
    fields[9] = fs->block_size; return 0;
}
int64_t vinix_ext2_read(void *context, uint32_t ino, void *buffer, uint64_t offset, size_t n)
{
    struct e2_inode in; struct e2_fs *fs = context;
    int rc = e2_inode_get(fs, ino, &in); if (rc) return rc;
    return e2_read_inode(fs, &in, buffer, offset, n);
}
int vinix_ext2_next(void *context, uint32_t directory, uint64_t *offset,
    uint32_t *inode, char *name, size_t capacity)
{
    if (!offset || !inode || !name || capacity < 256) return E2_INVALID;
    struct e2_fs *fs = context; struct e2_inode in;
    int rc = e2_inode_get(fs, directory, &in); if (rc) return rc;
    if ((in.mode & 0xf000u) != E2_DIRECTORY) return -20;
    if (*offset > in.size || (*offset & 3)) return E2_INVALID;
    uint64_t pos = *offset;
    while (pos < in.size) {
        uint8_t h[8];
        if (e2_read_inode(fs, &in, h, pos, 8) != 8) return E2_IO;
        unsigned rec = e2_u16(h + 4), len = fs->filetype ? h[6] : e2_u16(h + 6);
        uint32_t ino = e2_u32(h);
        if (rec < 8 || (rec & 3) || rec > fs->block_size - pos % fs->block_size || rec > in.size - pos ||
            len > 255 || len > rec - 8 || ino > fs->inodes) return E2_INVALID;
        if (!ino) { pos += rec; continue; }
        if (!len || (fs->filetype && h[7] > 7)) return E2_INVALID;
        if (e2_read_inode(fs, &in, name, pos + 8, len) != (int64_t)len) return E2_IO;
        for (unsigned i = 0; i < len; ++i) if (!name[i] || name[i] == '/') return E2_INVALID;
        name[len] = 0; *inode = ino; *offset = pos + rec; return 1;
    }
    *offset = pos; return 0;
}

/* Writable classic-ext2 support.  The routines below intentionally keep the
 * mutation surface small: regular files use direct and singly-indirect blocks,
 * directory entries are linear, and all allocation bitmaps remain one block.
 * Those limits are validated before changing media. */
static uint64_t e2_bgdt(const struct e2_fs *fs)
{ return (uint64_t)(fs->first + 1) * fs->block_size; }
static int e2_desc_get(struct e2_fs *fs, uint32_t group, uint8_t raw[32])
{
    if (group >= fs->groups) return E2_INVALID;
    return e2_disk(fs, raw, e2_bgdt(fs) + (uint64_t)group * 32, 32);
}
static int e2_desc_put(struct e2_fs *fs, uint32_t group, const uint8_t raw[32])
{
    if (group >= fs->groups) return E2_INVALID;
    return e2_store(fs, raw, e2_bgdt(fs) + (uint64_t)group * 32, 32);
}
static int e2_inode_offset(struct e2_fs *fs, uint32_t ino, uint64_t *off)
{
    if (!ino || ino > fs->inodes || !off) return E2_INVALID;
    uint32_t group = (ino - 1) / fs->ipg, slot = (ino - 1) % fs->ipg;
    uint8_t desc[32]; int rc = e2_desc_get(fs, group, desc); if (rc) return rc;
    uint32_t table = e2_u32(desc + 8);
    if (!e2_block_valid(fs, table)) return E2_INVALID;
    *off = (uint64_t)table * fs->block_size + (uint64_t)slot * fs->inode_size;
    return *off <= fs->bytes && 128 <= fs->bytes - *off ? 0 : E2_INVALID;
}
static int e2_inode_put(struct e2_fs *fs, uint32_t ino, const struct e2_inode *in)
{
    uint64_t off; uint8_t raw[128]; int rc = e2_inode_offset(fs, ino, &off);
    if (rc) return rc;
    rc = e2_disk(fs, raw, off, sizeof(raw)); if (rc) return rc;
    e2_p16(raw, (uint16_t)in->mode); e2_p16(raw + 2, (uint16_t)in->uid);
    e2_p32(raw + 4, (uint32_t)in->size);
    e2_p32(raw + 8, in->times[0]); e2_p32(raw + 12, in->times[2]);
    e2_p32(raw + 16, in->times[1]); e2_p32(raw + 20, 0);
    e2_p16(raw + 24, (uint16_t)in->gid); e2_p16(raw + 26, (uint16_t)in->links);
    e2_p32(raw + 28, in->sectors); e2_p32(raw + 32, in->flags);
    for (unsigned i = 0; i < 15; ++i) e2_p32(raw + 40 + i * 4, in->ptr[i]);
    e2_p32(raw + 108, (in->mode & 0xf000u) == E2_REGULAR ? (uint32_t)(in->size >> 32) : 0);
    e2_p16(raw + 120, (uint16_t)(in->uid >> 16));
    e2_p16(raw + 122, (uint16_t)(in->gid >> 16));
    return e2_store(fs, raw, off, sizeof(raw));
}
static int e2_super_count(struct e2_fs *fs, unsigned offset, int delta)
{
    uint8_t raw[4]; int rc = e2_disk(fs, raw, 1024 + offset, 4); if (rc) return rc;
    uint32_t value = e2_u32(raw);
    if ((delta < 0 && value < (uint32_t)-delta) ||
        (delta > 0 && value > UINT32_MAX - (uint32_t)delta)) return E2_INVALID;
    value = delta < 0 ? value - (uint32_t)-delta : value + (uint32_t)delta;
    e2_p32(raw, value); return e2_store(fs, raw, 1024 + offset, 4);
}
static int e2_block_allocate(struct e2_fs *fs, uint32_t *out)
{
    if (!out) return E2_INVALID;
    for (uint32_t group = 0; group < fs->groups; ++group) {
        uint8_t desc[32], bitmap[4096]; int rc = e2_desc_get(fs, group, desc);
        if (rc) return rc;
        uint16_t free_count = e2_u16(desc + 12);
        if (!free_count) continue;
        uint32_t map = e2_u32(desc), group_first = fs->first + group * fs->bpg;
        uint32_t group_end = group_first + fs->bpg;
        if (group_end < group_first || group_end > fs->blocks) group_end = fs->blocks;
        if (!e2_block_valid(fs, map) || group_first >= group_end) return E2_INVALID;
        rc = e2_disk(fs, bitmap, (uint64_t)map * fs->block_size, fs->block_size);
        if (rc) return rc;
        for (uint32_t bit = 0; bit < group_end - group_first; ++bit) {
            if (bitmap[bit >> 3] & (uint8_t)(1u << (bit & 7))) continue;
            uint32_t block = group_first + bit;
            uint32_t inode_map = e2_u32(desc + 4), table = e2_u32(desc + 8);
            uint64_t table_blocks = ((uint64_t)fs->ipg * fs->inode_size + fs->block_size - 1) / fs->block_size;
            if (block == map || block == inode_map || (block >= table && block < table + table_blocks))
                return E2_INVALID; /* corrupt bitmap tried to allocate metadata */
            bitmap[bit >> 3] |= (uint8_t)(1u << (bit & 7));
            rc = e2_store(fs, bitmap, (uint64_t)map * fs->block_size, fs->block_size);
            if (rc) return rc;
            e2_p16(desc + 12, (uint16_t)(free_count - 1));
            rc = e2_desc_put(fs, group, desc); if (rc) return rc;
            rc = e2_super_count(fs, 12, -1); if (rc) return rc;
            e2_zero(bitmap, fs->block_size);
            rc = e2_store(fs, bitmap, (uint64_t)block * fs->block_size, fs->block_size);
            if (rc) return rc;
            *out = block; return 0;
        }
        return E2_INVALID; /* descriptor and bitmap free counts disagree */
    }
    return E2_NOSPC;
}
static int e2_block_free(struct e2_fs *fs, uint32_t block)
{
    if (!e2_block_valid(fs, block)) return E2_INVALID;
    uint32_t group = (block - fs->first) / fs->bpg;
    uint32_t group_first = fs->first + group * fs->bpg, bit = block - group_first;
    uint8_t desc[32], bitmap[4096]; int rc = e2_desc_get(fs, group, desc); if (rc) return rc;
    uint32_t map = e2_u32(desc); if (!e2_block_valid(fs, map) || bit >= fs->block_size * 8) return E2_INVALID;
    rc = e2_disk(fs, bitmap, (uint64_t)map * fs->block_size, fs->block_size); if (rc) return rc;
    if (!(bitmap[bit >> 3] & (uint8_t)(1u << (bit & 7)))) return E2_INVALID;
    bitmap[bit >> 3] &= (uint8_t)~(1u << (bit & 7));
    rc = e2_store(fs, bitmap, (uint64_t)map * fs->block_size, fs->block_size); if (rc) return rc;
    uint16_t count = e2_u16(desc + 12); if (count == 0xffffu) return E2_INVALID;
    e2_p16(desc + 12, (uint16_t)(count + 1));
    rc = e2_desc_put(fs, group, desc); if (rc) return rc;
    return e2_super_count(fs, 12, 1);
}
static int e2_inode_allocate(struct e2_fs *fs, uint32_t *out)
{
    if (!out) return E2_INVALID;
    for (uint32_t group = 0; group < fs->groups; ++group) {
        uint8_t desc[32], bitmap[4096]; int rc = e2_desc_get(fs, group, desc); if (rc) return rc;
        uint16_t free_count = e2_u16(desc + 14); if (!free_count) continue;
        uint32_t map = e2_u32(desc + 4); if (!e2_block_valid(fs, map)) return E2_INVALID;
        rc = e2_disk(fs, bitmap, (uint64_t)map * fs->block_size, fs->block_size); if (rc) return rc;
        uint32_t slots = fs->inodes - group * fs->ipg;
        if (slots > fs->ipg) slots = fs->ipg;
        for (uint32_t bit = 0; bit < slots; ++bit) {
            uint32_t ino = group * fs->ipg + bit + 1;
            if (ino < fs->first_inode || (bitmap[bit >> 3] & (uint8_t)(1u << (bit & 7)))) continue;
            bitmap[bit >> 3] |= (uint8_t)(1u << (bit & 7));
            rc = e2_store(fs, bitmap, (uint64_t)map * fs->block_size, fs->block_size); if (rc) return rc;
            e2_p16(desc + 14, (uint16_t)(free_count - 1));
            rc = e2_desc_put(fs, group, desc); if (rc) return rc;
            rc = e2_super_count(fs, 16, -1); if (rc) return rc;
            uint64_t off; rc = e2_inode_offset(fs, ino, &off); if (rc) return rc;
            e2_zero(bitmap, fs->inode_size);
            rc = e2_store(fs, bitmap, off, fs->inode_size); if (rc) return rc;
            *out = ino; return 0;
        }
        return E2_INVALID;
    }
    return E2_NOSPC;
}
static int e2_inode_free(struct e2_fs *fs, uint32_t ino)
{
    if (ino < fs->first_inode || ino > fs->inodes) return E2_INVALID;
    uint32_t group = (ino - 1) / fs->ipg, bit = (ino - 1) % fs->ipg;
    uint8_t desc[32], bitmap[4096]; int rc = e2_desc_get(fs, group, desc); if (rc) return rc;
    uint32_t map = e2_u32(desc + 4); if (!e2_block_valid(fs, map)) return E2_INVALID;
    rc = e2_disk(fs, bitmap, (uint64_t)map * fs->block_size, fs->block_size); if (rc) return rc;
    if (!(bitmap[bit >> 3] & (uint8_t)(1u << (bit & 7)))) return E2_INVALID;
    bitmap[bit >> 3] &= (uint8_t)~(1u << (bit & 7));
    rc = e2_store(fs, bitmap, (uint64_t)map * fs->block_size, fs->block_size); if (rc) return rc;
    uint16_t count = e2_u16(desc + 14); if (count == 0xffffu) return E2_INVALID;
    e2_p16(desc + 14, (uint16_t)(count + 1));
    rc = e2_desc_put(fs, group, desc); if (rc) return rc;
    return e2_super_count(fs, 16, 1);
}
static uint64_t e2_write_limit(const struct e2_fs *fs)
{ return (12u + fs->block_size / 4u) * (uint64_t)fs->block_size; }
static int e2_map_write(struct e2_fs *fs, struct e2_inode *in, uint64_t logical,
    int allocate, uint32_t *out)
{
    if (!out) return E2_INVALID;
    if (logical < 12) {
        if (!in->ptr[logical] && allocate) {
            int rc = e2_block_allocate(fs, &in->ptr[logical]); if (rc) return rc;
            in->sectors += fs->block_size / 512;
        }
        *out = in->ptr[logical]; return 0;
    }
    logical -= 12; uint32_t per = fs->block_size / 4;
    if (logical >= per) return E2_FBIG;
    if (!in->ptr[12]) {
        if (!allocate) { *out = 0; return 0; }
        int rc = e2_block_allocate(fs, &in->ptr[12]); if (rc) return rc;
        in->sectors += fs->block_size / 512;
    }
    uint8_t raw[4]; uint64_t off = (uint64_t)in->ptr[12] * fs->block_size + logical * 4;
    int rc = e2_disk(fs, raw, off, 4); if (rc) return rc;
    uint32_t block = e2_u32(raw);
    if (block && !e2_block_valid(fs, block)) return E2_INVALID;
    if (!block && allocate) {
        rc = e2_block_allocate(fs, &block); if (rc) return rc;
        e2_p32(raw, block); rc = e2_store(fs, raw, off, 4); if (rc) return rc;
        in->sectors += fs->block_size / 512;
    }
    *out = block; return 0;
}
static int e2_zero_tail(struct e2_fs *fs, const struct e2_inode *in, uint64_t size)
{
    if (!size || !(size % fs->block_size)) return 0;
    uint32_t block; int rc = e2_map(fs, in, size / fs->block_size, &block); if (rc || !block) return rc;
    uint8_t zero[256]; e2_zero(zero, sizeof(zero));
    uint32_t pos = (uint32_t)(size % fs->block_size);
    while (pos < fs->block_size) {
        size_t n = fs->block_size - pos; if (n > sizeof(zero)) n = sizeof(zero);
        rc = e2_store(fs, zero, (uint64_t)block * fs->block_size + pos, n); if (rc) return rc;
        pos += (uint32_t)n;
    }
    return 0;
}
static int e2_zero_range(struct e2_fs *fs, const struct e2_inode *in,
    uint64_t start, uint64_t end)
{
    uint8_t zero[4096]; e2_zero(zero, fs->block_size);
    while (start < end) {
        uint32_t within = (uint32_t)(start % fs->block_size), block;
        size_t n = fs->block_size - within;
        if (n > end - start) n = (size_t)(end - start);
        int rc = e2_map(fs, in, start / fs->block_size, &block); if (rc) return rc;
        if (block) {
            rc = e2_store(fs, zero, (uint64_t)block * fs->block_size + within, n);
            if (rc) return rc;
        }
        start += n;
    }
    return 0;
}
int vinix_ext2_truncate(void *context, uint32_t ino, uint64_t size)
{
    struct e2_fs *fs = context; struct e2_inode in;
    if (!fs || !fs->active) return E2_ROFS;
    if (size > e2_write_limit(fs)) return E2_FBIG;
    int rc = e2_inode_get(fs, ino, &in); if (rc) return rc;
    if ((in.mode & 0xf000u) != E2_REGULAR || (in.flags & (0x10u | 0x20u))) return E2_UNSUPPORTED;
    if (in.size > e2_write_limit(fs)) return E2_FBIG;
    if (size < in.size) {
        rc = e2_zero_tail(fs, &in, size); if (rc) return rc;
        uint64_t first_free = (size + fs->block_size - 1) / fs->block_size;
        uint64_t old_blocks = (in.size + fs->block_size - 1) / fs->block_size;
        uint32_t per = fs->block_size / 4;
        for (uint64_t logical = first_free; logical < old_blocks; ++logical) {
            uint32_t block; rc = e2_map_write(fs, &in, logical, 0, &block); if (rc) return rc;
            if (!block) continue;
            rc = e2_block_free(fs, block); if (rc) return rc;
            if (in.sectors < fs->block_size / 512) return E2_INVALID;
            in.sectors -= fs->block_size / 512;
            if (logical < 12) in.ptr[logical] = 0;
            else {
                uint8_t zero[4] = {0};
                rc = e2_store(fs, zero, (uint64_t)in.ptr[12] * fs->block_size + (logical - 12) * 4, 4);
                if (rc) return rc;
            }
        }
        if (in.ptr[12]) {
            uint8_t pointers[4096]; rc = e2_disk(fs, pointers, (uint64_t)in.ptr[12] * fs->block_size, fs->block_size);
            if (rc) return rc; unsigned used = 0;
            for (uint32_t i = 0; i < per; ++i) used |= e2_u32(pointers + i * 4);
            if (!used) {
                rc = e2_block_free(fs, in.ptr[12]); if (rc) return rc;
                in.ptr[12] = 0;
                if (in.sectors < fs->block_size / 512) return E2_INVALID;
                in.sectors -= fs->block_size / 512;
            }
        }
    }
    in.size = size; return e2_inode_put(fs, ino, &in);
}
int64_t vinix_ext2_write(void *context, uint32_t ino, const void *buffer,
    uint64_t offset, size_t count)
{
    struct e2_fs *fs = context; struct e2_inode in;
    if (!fs || !fs->active || (!buffer && count)) return E2_ROFS;
    if (offset > e2_write_limit(fs) || count > e2_write_limit(fs) - offset) return E2_FBIG;
    int rc = e2_inode_get(fs, ino, &in); if (rc) return rc;
    if ((in.mode & 0xf000u) != E2_REGULAR) return E2_ISDIR;
    if (in.flags & (0x10u | 0x20u)) return E2_UNSUPPORTED;
    if (offset > in.size) {
        rc = e2_zero_range(fs, &in, in.size, offset); if (rc) return rc;
    }
    const uint8_t *p = buffer; size_t done = 0;
    while (done < count) {
        uint64_t pos = offset + done; uint32_t within = (uint32_t)(pos % fs->block_size), block;
        size_t n = fs->block_size - within; if (n > count - done) n = count - done;
        rc = e2_map_write(fs, &in, pos / fs->block_size, 1, &block); if (rc) return rc;
        rc = e2_store(fs, p + done, (uint64_t)block * fs->block_size + within, n); if (rc) return rc;
        done += n;
    }
    if (offset + done > in.size) in.size = offset + done;
    rc = e2_inode_put(fs, ino, &in); return rc ? rc : (int64_t)done;
}
static int e2_name_valid(const char *name, size_t n)
{
    if (!name || !n) return E2_INVALID;
    if (n > 255) return E2_NAMETOOLONG;
    if ((n == 1 && name[0] == '.') || (n == 2 && name[0] == '.' && name[1] == '.')) return E2_INVALID;
    for (size_t i = 0; i < n; ++i) if (!name[i] || name[i] == '/') return E2_INVALID;
    return 0;
}
static int e2_name_equal(const char *a, size_t an, const char *b, size_t bn)
{
    if (an != bn) return 0;
    for (size_t i = 0; i < an; ++i) if (a[i] != b[i]) return 0;
    return 1;
}
static int e2_lookup(struct e2_fs *fs, uint32_t dir, const char *name, size_t n,
    uint32_t *ino, uint8_t *type)
{
    uint64_t pos = 0; char found[256]; uint32_t child;
    for (;;) {
        int rc = vinix_ext2_next(fs, dir, &pos, &child, found, sizeof(found));
        if (rc <= 0) return rc ? rc : -2;
        size_t length = 0; while (length < sizeof(found) && found[length]) ++length;
        if (e2_name_equal(found, length, name, n)) {
            if (ino) *ino = child;
            if (type) {
                struct e2_inode in; rc = e2_inode_get(fs, child, &in); if (rc) return rc;
                uint32_t kind = in.mode & 0xf000u;
                *type = kind == E2_DIRECTORY ? 2 : kind == E2_SYMLINK ? 7 : 1;
            }
            return 0;
        }
    }
}
static int e2_dir_add(struct e2_fs *fs, uint32_t dir, const char *name, size_t n,
    uint32_t child, uint8_t type)
{
    int rc = e2_name_valid(name, n); if (rc) return rc;
    uint32_t ignored; rc = e2_lookup(fs, dir, name, n, &ignored, NULL);
    if (!rc) return E2_EXIST; if (rc != -2) return rc;
    struct e2_inode in; rc = e2_inode_get(fs, dir, &in); if (rc) return rc;
    if ((in.mode & 0xf000u) != E2_DIRECTORY || (in.flags & 0x1000u)) return E2_NOTDIR;
    uint16_t needed = (uint16_t)((8 + n + 3) & ~3u); uint8_t block_data[4096];
    uint64_t blocks = in.size / fs->block_size;
    for (uint64_t logical = 0; logical < blocks; ++logical) {
        uint32_t block; rc = e2_map(fs, &in, logical, &block); if (rc || !block) return rc ? rc : E2_INVALID;
        rc = e2_disk(fs, block_data, (uint64_t)block * fs->block_size, fs->block_size); if (rc) return rc;
        for (uint32_t pos = 0; pos < fs->block_size;) {
            uint16_t rec = e2_u16(block_data + pos + 4); uint8_t len = block_data[pos + 6];
            if (rec < 8 || (rec & 3) || rec > fs->block_size - pos || len > rec - 8) return E2_INVALID;
            uint16_t actual = (uint16_t)((8 + len + 3) & ~3u);
            if (rec >= actual + needed) {
                e2_p16(block_data + pos + 4, actual); uint8_t *entry = block_data + pos + actual;
                e2_zero(entry, rec - actual); e2_p32(entry, child); e2_p16(entry + 4, rec - actual);
                entry[6] = (uint8_t)n; entry[7] = fs->filetype ? type : 0; e2_copy(entry + 8, name, n);
                return e2_store(fs, block_data, (uint64_t)block * fs->block_size, fs->block_size);
            }
            pos += rec;
        }
    }
    if (in.size > e2_write_limit(fs) - fs->block_size) return E2_FBIG;
    uint32_t block; rc = e2_map_write(fs, &in, blocks, 1, &block); if (rc) return rc;
    e2_zero(block_data, fs->block_size); e2_p32(block_data, child); e2_p16(block_data + 4, (uint16_t)fs->block_size);
    block_data[6] = (uint8_t)n; block_data[7] = fs->filetype ? type : 0; e2_copy(block_data + 8, name, n);
    rc = e2_store(fs, block_data, (uint64_t)block * fs->block_size, fs->block_size); if (rc) return rc;
    in.size += fs->block_size; return e2_inode_put(fs, dir, &in);
}
static int e2_dir_remove(struct e2_fs *fs, uint32_t dir, const char *name, size_t n,
    uint32_t *removed)
{
    struct e2_inode in; int rc = e2_inode_get(fs, dir, &in); if (rc) return rc;
    if ((in.mode & 0xf000u) != E2_DIRECTORY) return E2_NOTDIR;
    uint8_t data[4096]; uint64_t blocks = in.size / fs->block_size;
    for (uint64_t logical = 0; logical < blocks; ++logical) {
        uint32_t block; rc = e2_map(fs, &in, logical, &block); if (rc || !block) return rc ? rc : E2_INVALID;
        rc = e2_disk(fs, data, (uint64_t)block * fs->block_size, fs->block_size); if (rc) return rc;
        uint32_t previous = UINT32_MAX;
        for (uint32_t pos = 0; pos < fs->block_size;) {
            uint32_t child = e2_u32(data + pos); uint16_t rec = e2_u16(data + pos + 4);
            uint8_t len = data[pos + 6];
            if (rec < 8 || (rec & 3) || rec > fs->block_size - pos || len > rec - 8) return E2_INVALID;
            if (child && e2_name_equal((char *)data + pos + 8, len, name, n)) {
                if (previous != UINT32_MAX) e2_p16(data + previous + 4, (uint16_t)(e2_u16(data + previous + 4) + rec));
                else e2_p32(data + pos, 0);
                rc = e2_store(fs, data, (uint64_t)block * fs->block_size, fs->block_size);
                if (!rc && removed) *removed = child;
                return rc;
            }
            previous = pos; pos += rec;
        }
    }
    return -2;
}
static int e2_dir_empty(struct e2_fs *fs, uint32_t ino)
{
    uint64_t pos = 0; uint32_t child; char name[256];
    for (;;) {
        int rc = vinix_ext2_next(fs, ino, &pos, &child, name, sizeof(name));
        if (rc < 0) return rc; if (!rc) return 1;
        if (!((name[0] == '.' && !name[1]) || (name[0] == '.' && name[1] == '.' && !name[2]))) return 0;
    }
}
static int e2_release_inode(struct e2_fs *fs, uint32_t ino, struct e2_inode *in)
{
    uint32_t kind = in->mode & 0xf000u; int rc;
    if (kind == E2_REGULAR || kind == E2_DIRECTORY || (kind == E2_SYMLINK && !in->fast_link)) {
        /* The public truncate operation is regular-file-only. Once the name
         * is gone, temporarily use that path to release a directory or a
         * block-backed symlink without teaching it special-file semantics. */
        in->mode = E2_REGULAR | 0600;
        rc = e2_inode_put(fs, ino, in); if (rc) return rc;
        rc = vinix_ext2_truncate(fs, ino, 0); if (rc) return rc;
        rc = e2_inode_get(fs, ino, in); if (rc) return rc;
    }
    in->mode = 0; in->size = 0; in->links = 0; in->sectors = 0;
    for (unsigned i = 0; i < 15; ++i) in->ptr[i] = 0;
    rc = e2_inode_put(fs, ino, in); if (rc) return rc;
    return e2_inode_free(fs, ino);
}
int vinix_ext2_create(void *context, uint32_t parent, const char *name,
    size_t name_length, uint32_t mode, uint32_t *created)
{
    struct e2_fs *fs = context; if (!fs || !fs->active || !created) return E2_ROFS;
    uint32_t kind = mode & 0xf000u;
    if (kind != E2_REGULAR && kind != E2_DIRECTORY) return E2_UNSUPPORTED;
    int rc = e2_name_valid(name, name_length); if (rc) return rc;
    uint32_t exists; rc = e2_lookup(fs, parent, name, name_length, &exists, NULL);
    if (!rc) return E2_EXIST; if (rc != -2) return rc;
    uint32_t ino; rc = e2_inode_allocate(fs, &ino); if (rc) return rc;
    struct e2_inode in; e2_zero(&in, sizeof(in)); in.mode = mode; in.links = kind == E2_DIRECTORY ? 2 : 1;
    if (kind == E2_DIRECTORY) {
        uint32_t block; rc = e2_map_write(fs, &in, 0, 1, &block); if (rc) return rc;
        uint8_t data[4096]; e2_zero(data, fs->block_size);
        e2_p32(data, ino); e2_p16(data + 4, 12); data[6] = 1; data[7] = fs->filetype ? 2 : 0; data[8] = '.';
        e2_p32(data + 12, parent); e2_p16(data + 16, (uint16_t)(fs->block_size - 12));
        data[18] = 2; data[19] = fs->filetype ? 2 : 0; data[20] = '.'; data[21] = '.';
        rc = e2_store(fs, data, (uint64_t)block * fs->block_size, fs->block_size); if (rc) return rc;
        in.size = fs->block_size;
    }
    rc = e2_inode_put(fs, ino, &in); if (rc) return rc;
    rc = e2_dir_add(fs, parent, name, name_length, ino, kind == E2_DIRECTORY ? 2 : 1); if (rc) return rc;
    if (kind == E2_DIRECTORY) {
        struct e2_inode p; rc = e2_inode_get(fs, parent, &p); if (rc) return rc;
        ++p.links; rc = e2_inode_put(fs, parent, &p); if (rc) return rc;
        uint32_t group = (ino - 1) / fs->ipg; uint8_t desc[32]; rc = e2_desc_get(fs, group, desc); if (rc) return rc;
        uint16_t dirs = e2_u16(desc + 16); if (dirs == 0xffffu) return E2_INVALID;
        e2_p16(desc + 16, (uint16_t)(dirs + 1)); rc = e2_desc_put(fs, group, desc); if (rc) return rc;
    }
    *created = ino; return 0;
}
int vinix_ext2_symlink(void *context, uint32_t parent, const char *name,
    size_t name_length, const char *target, size_t target_length, uint32_t *created)
{
    struct e2_fs *fs = context;
    if (!fs || !fs->active || !created || !target || !target_length) return E2_ROFS;
    if (target_length > 60) return E2_NAMETOOLONG;
    int rc = e2_name_valid(name, name_length); if (rc) return rc;
    uint32_t exists; rc = e2_lookup(fs, parent, name, name_length, &exists, NULL);
    if (!rc) return E2_EXIST; if (rc != -2) return rc;
    uint32_t ino; rc = e2_inode_allocate(fs, &ino); if (rc) return rc;
    struct e2_inode in; e2_zero(&in, sizeof(in)); in.mode = E2_SYMLINK | 0777; in.links = 1; in.size = target_length;
    e2_copy(in.ptr, target, target_length);
    rc = e2_inode_put(fs, ino, &in); if (rc) return rc;
    rc = e2_dir_add(fs, parent, name, name_length, ino, 7); if (rc) return rc;
    *created = ino; return 0;
}
int vinix_ext2_link(void *context, uint32_t parent, const char *name,
    size_t name_length, uint32_t ino)
{
    struct e2_fs *fs = context; struct e2_inode in;
    if (!fs || !fs->active) return E2_ROFS;
    int rc = e2_inode_get(fs, ino, &in); if (rc) return rc;
    if ((in.mode & 0xf000u) == E2_DIRECTORY || in.links == 0xffffu) return E2_UNSUPPORTED;
    ++in.links; rc = e2_inode_put(fs, ino, &in); if (rc) return rc;
    rc = e2_dir_add(fs, parent, name, name_length, ino,
        (in.mode & 0xf000u) == E2_SYMLINK ? 7 : 1);
    if (rc) { --in.links; (void)e2_inode_put(fs, ino, &in); }
    return rc;
}
int vinix_ext2_drop_link(void *context, uint32_t ino)
{
    struct e2_fs *fs = context; struct e2_inode in;
    if (!fs || !fs->active) return E2_ROFS;
    int rc = e2_inode_get(fs, ino, &in); if (rc) return rc;
    if (!in.links) return E2_INVALID;
    if (in.links > 1) { --in.links; return e2_inode_put(fs, ino, &in); }
    return e2_release_inode(fs, ino, &in);
}
int vinix_ext2_unlink(void *context, uint32_t parent, const char *name,
    size_t name_length, int directory)
{
    struct e2_fs *fs = context; uint32_t ino; uint8_t type;
    if (!fs || !fs->active) return E2_ROFS;
    int rc = e2_name_valid(name, name_length); if (rc) return rc;
    rc = e2_lookup(fs, parent, name, name_length, &ino, &type); if (rc) return rc;
    if (directory && type != 2) return E2_NOTDIR;
    if (!directory && type == 2) return E2_ISDIR;
    if (directory) { int empty = e2_dir_empty(fs, ino); if (empty <= 0) return empty < 0 ? empty : E2_NOTEMPTY; }
    uint32_t removed; rc = e2_dir_remove(fs, parent, name, name_length, &removed); if (rc) return rc;
    struct e2_inode in; rc = e2_inode_get(fs, removed, &in); if (rc) return rc;
    if (directory) {
        struct e2_inode p; rc = e2_inode_get(fs, parent, &p); if (rc) return rc;
        if (p.links) --p.links; rc = e2_inode_put(fs, parent, &p); if (rc) return rc;
        uint32_t group = (removed - 1) / fs->ipg; uint8_t desc[32]; rc = e2_desc_get(fs, group, desc); if (rc) return rc;
        uint16_t dirs = e2_u16(desc + 16); if (!dirs) return E2_INVALID;
        e2_p16(desc + 16, (uint16_t)(dirs - 1)); rc = e2_desc_put(fs, group, desc); if (rc) return rc;
        return e2_release_inode(fs, removed, &in);
    }
    return vinix_ext2_drop_link(fs, removed);
}
int vinix_ext2_rename(void *context, uint32_t old_parent,
    const char *old_name, size_t old_length, uint32_t new_parent,
    const char *new_name, size_t new_length, int replace)
{
    struct e2_fs *fs = context; uint32_t source, destination; uint8_t type;
    if (!fs || !fs->active) return E2_ROFS;
    int rc = e2_name_valid(old_name, old_length); if (rc) return rc;
    rc = e2_name_valid(new_name, new_length); if (rc) return rc;
    rc = e2_lookup(fs, old_parent, old_name, old_length, &source, &type); if (rc) return rc;
    if (old_parent == new_parent && e2_name_equal(old_name, old_length, new_name, new_length)) return 0;
    if (type == 2 && old_parent != new_parent) return E2_UNSUPPORTED;
    rc = e2_lookup(fs, new_parent, new_name, new_length, &destination, NULL);
    if (!rc) {
        /* POSIX requires rename(a, b) to do nothing when both names are hard
         * links to the same inode. In particular, neither name is removed. */
        if (destination == source) return 0;
        if (!replace) return E2_EXIST;
        struct e2_inode target; rc = e2_inode_get(fs, destination, &target); if (rc) return rc;
        if ((target.mode & 0xf000u) == E2_DIRECTORY) return E2_UNSUPPORTED;
        rc = e2_dir_remove(fs, new_parent, new_name, new_length, NULL); if (rc) return rc;
        rc = vinix_ext2_drop_link(fs, destination); if (rc) return rc;
    } else if (rc != -2) return rc;
    rc = e2_dir_add(fs, new_parent, new_name, new_length, source, type); if (rc) return rc;
    rc = e2_dir_remove(fs, old_parent, old_name, old_length, NULL); if (rc) return rc;
    return 0;
}
