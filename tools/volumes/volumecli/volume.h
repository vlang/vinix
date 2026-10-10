// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VINIX_VOLUME_H
#define VINIX_VOLUME_H
#include <stdint.h>
#include <stddef.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <stdio.h>
struct vinix_volume_request { uint32_t version, slot; uint64_t offset, length, flags; };
struct vinix_block_status {
    uint64_t version, bytes, sector, flags, reads, writes, read_bytes, write_bytes;
    uint64_t flushes, errors, last_error, disk_id, start, slot, generation, reserved;
};
_Static_assert(sizeof(struct vinix_volume_request) == 32, "volume request ABI");
_Static_assert(sizeof(struct vinix_block_status) == 128, "block status ABI");
_Static_assert(offsetof(struct vinix_volume_request, length) == 16, "volume geometry ABI");
#endif
