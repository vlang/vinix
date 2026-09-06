/* SPDX-License-Identifier: GPL-2.0-or-later
 * Bounded, read-only ext2 root reader. Layout references:
 * docs.kernel.org/filesystems/ext2.html and ext4/{super,inodes,directory}.html.
 * Does not invoke Vinix's legacy ext2 allocator or assume 512-byte device LBAs.
 */
#include "apple_ans_ext2.h"
#define E2_IO (-5)
#define E2_INVALID (-22)
#define E2_UNSUPPORTED (-95)
#define E2_DIRECTORY 0x4000u
#define E2_REGULAR 0x8000u
#define E2_SYMLINK 0xa000u
struct e2_fs {
    vinix_ext2_reader read;
    void *cookie;
    uint64_t bytes;
    uint32_t block_size, inode_size, blocks, inodes, first;
    uint32_t bpg, ipg, groups, filetype, largefile, opened;
};
struct e2_inode {
    uint64_t size;
    uint32_t mode, uid, gid, links, sectors, times[3], ptr[15];
    uint8_t data[60];
    int fast_link;
};
static uint16_t e2_u16(const uint8_t *p)
{ return (uint16_t)(p[0] | (uint16_t)p[1] << 8); }
static uint32_t e2_u32(const uint8_t *p)
{ return (uint32_t)e2_u16(p) | (uint32_t)e2_u16(p + 2) << 16; }
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
    v.size = e2_u32(raw + 4);
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
int vinix_ext2_open(void *context, size_t size, vinix_ext2_reader read, void *cookie, uint64_t bytes)
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
    if ((compat & ~0x38u) || (incompat & ~2u) || (rocompat & ~3u)) return E2_UNSUPPORTED;
    struct e2_fs fs = {0};
    fs.block_size = 1024u << shift;
    fs.inode_size = revision ? e2_u16(sb + 88) : 128;
    fs.blocks = e2_u32(sb + 4); fs.inodes = e2_u32(sb);
    fs.first = e2_u32(sb + 20); fs.bpg = e2_u32(sb + 32); fs.ipg = e2_u32(sb + 40);
    if (fs.first != (shift ? 0u : 1u) || fs.blocks <= fs.first + 2 || fs.inodes < 2 ||
        !fs.bpg || fs.bpg > fs.block_size * 8 || !fs.ipg || fs.ipg > fs.block_size * 8 ||
        fs.inode_size < 128 || fs.inode_size > fs.block_size || (fs.inode_size & (fs.inode_size - 1)) ||
        e2_u32(sb + 36) != fs.bpg || (uint64_t)fs.blocks * fs.block_size > bytes)
        return E2_INVALID;
    fs.groups = (uint32_t)(((uint64_t)fs.blocks - fs.first + fs.bpg - 1) / fs.bpg);
    if (((uint64_t)fs.inodes + fs.ipg - 1) / fs.ipg > fs.groups ||
        (uint64_t)(fs.first + 1) * fs.block_size + (uint64_t)fs.groups * 32 > (uint64_t)fs.blocks * fs.block_size)
        return E2_INVALID;
    fs.bytes = (uint64_t)fs.blocks * fs.block_size;
    fs.cookie = cookie; fs.read = read; fs.opened = 1;
    fs.filetype = incompat & 2; fs.largefile = rocompat & 2;
    struct e2_inode root;
    int rc = e2_inode_get(&fs, 2, &root);
    if (rc || (root.mode & 0xf000u) != E2_DIRECTORY || !root.size) return rc ? rc : E2_INVALID;
    e2_copy(context, &fs, sizeof(fs)); return 0;
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
