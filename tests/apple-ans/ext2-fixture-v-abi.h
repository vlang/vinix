/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_EXT2_FIXTURE_V_ABI_H
#define VINIX_EXT2_FIXTURE_V_ABI_H
#include "ext2_fixture.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
struct image {
    uint8_t *data;
    size_t bytes;
    unsigned bs, isize, reads, writes;
    int fail, fail_write;
    struct e2_fs fs;
};
typedef const void *ext2_fixture_const_p;
int ext2_fixture_read(void *, void *, uint64_t, size_t);
int ext2_fixture_write(void *, const void *, uint64_t, size_t);
void ext2_fixture_setup(struct image *, unsigned, unsigned);
void ext2_fixture_destroy(struct image *);
int ext2_fixture_run(void);
#endif
