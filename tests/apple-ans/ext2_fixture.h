// SPDX-License-Identifier: GPL-2.0-or-later
// Private layout and helper declarations for the independent C media fixture.
#include "../../kernel/c/apple_ans_ext2.h"
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
uint16_t e2_u16(const uint8_t *);
uint32_t e2_u32(const uint8_t *);
void e2_p16(uint8_t *, uint16_t);
void e2_p32(uint8_t *, uint32_t);
int e2_lookup(struct e2_fs *, uint32_t, const char *, size_t, uint32_t *, uint8_t *);
