/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_APPLE_ANS_EXT2_H
#define VINIX_APPLE_ANS_EXT2_H
#include <stdint.h>
#include <stddef.h>
/* Byte-oriented ext2 access. Callbacks transfer exactly count bytes relative
 * to the selected partition or return nonzero. Writable mounts deliberately
 * support only classic, non-journaled ext2; the filesystem is marked dirty
 * before publication and clean only during an orderly shutdown. */
typedef int (*vinix_ext2_reader)(void *, void *, uint64_t, size_t);
typedef int (*vinix_ext2_writer)(void *, const void *, uint64_t, size_t);
size_t vinix_ext2_context_size(void);
int vinix_ext2_open(void *context, size_t context_size, vinix_ext2_reader,
    void *cookie, uint64_t partition_bytes);
int vinix_ext2_open_rw(void *context, size_t context_size, vinix_ext2_reader,
    vinix_ext2_writer, void *cookie, uint64_t partition_bytes);
int vinix_ext2_begin_write(void *context);
int vinix_ext2_close_clean(void *context);
/* Native-endian u64 fields: size, mode, uid, gid, nlink, blocks(512-byte),
 * atime, mtime, ctime, filesystem block size. */
int vinix_ext2_stat(void *context, uint32_t inode, uint64_t fields[10]);
int64_t vinix_ext2_read(void *context, uint32_t inode, void *buffer,
    uint64_t offset, size_t capacity);
int64_t vinix_ext2_write(void *context, uint32_t inode, const void *buffer,
    uint64_t offset, size_t count);
int vinix_ext2_truncate(void *context, uint32_t inode, uint64_t size);
/* Returns 1 for an entry, 0 for EOF, negative errno on failure. Offset is a
 * directory byte cursor. Name capacity must be at least 256. */
int vinix_ext2_next(void *context, uint32_t directory, uint64_t *offset,
    uint32_t *inode, char *name, size_t capacity);
int vinix_ext2_create(void *context, uint32_t parent, const char *name,
    size_t name_length, uint32_t mode, uint32_t *inode);
int vinix_ext2_symlink(void *context, uint32_t parent, const char *name,
    size_t name_length, const char *target, size_t target_length,
    uint32_t *inode);
int vinix_ext2_link(void *context, uint32_t parent, const char *name,
    size_t name_length, uint32_t inode);
int vinix_ext2_unlink(void *context, uint32_t parent, const char *name,
    size_t name_length, int directory);
int vinix_ext2_drop_link(void *context, uint32_t inode);
int vinix_ext2_rename(void *context, uint32_t old_parent,
    const char *old_name, size_t old_length, uint32_t new_parent,
    const char *new_name, size_t new_length, int replace);
#endif
