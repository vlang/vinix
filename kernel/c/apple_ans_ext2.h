/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_APPLE_ANS_EXT2_H
#define VINIX_APPLE_ANS_EXT2_H
#include <stdint.h>
#include <stddef.h>
/* Read-only, byte-oriented ext2 reader. The callback must read exactly count
 * bytes relative to the selected partition or return nonzero. No writer,
 * allocator, repair, journal replay or block-device passthrough is present. */
typedef int (*vinix_ext2_reader)(void *, void *, uint64_t, size_t);
size_t vinix_ext2_context_size(void);
int vinix_ext2_open(void *context, size_t context_size, vinix_ext2_reader,
    void *cookie, uint64_t partition_bytes);
/* Native-endian u64 fields: size, mode, uid, gid, nlink, blocks(512-byte),
 * atime, mtime, ctime, filesystem block size. */
int vinix_ext2_stat(void *context, uint32_t inode, uint64_t fields[10]);
int64_t vinix_ext2_read(void *context, uint32_t inode, void *buffer,
    uint64_t offset, size_t capacity);
/* Returns 1 for an entry, 0 for EOF, negative errno on failure. Offset is a
 * directory byte cursor. Name capacity must be at least 256. */
int vinix_ext2_next(void *context, uint32_t directory, uint64_t *offset,
    uint32_t *inode, char *name, size_t capacity);
#endif
