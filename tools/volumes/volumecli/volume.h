// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VINIX_VOLUME_H
#define VINIX_VOLUME_H
#include <stdint.h>
#include <stddef.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <stdio.h>
#include <string.h>
struct vinix_volume_request { uint32_t version, slot; uint64_t offset, length, flags; };
struct vinix_encrypted_volume_request { struct vinix_volume_request data; uint8_t key[64]; };
_Static_assert(sizeof(struct vinix_encrypted_volume_request) == 96, "encrypted volume request ABI");
_Static_assert(offsetof(struct vinix_encrypted_volume_request, key) == 32, "encrypted volume key ABI");
struct vinix_block_status {
    uint64_t version, bytes, sector, flags, reads, writes, read_bytes, write_bytes;
    uint64_t flushes, errors, last_error, disk_id, start, slot, generation, reserved;
};
struct vinix_block_health {
    uint64_t version, protocol, flags, disk_id, reserved[4];
    uint8_t identify[512], data[512];
};
_Static_assert(sizeof(struct vinix_block_health) == 1088, "block health ABI");
_Static_assert(offsetof(struct vinix_block_health, data) == 576, "block health data ABI");
_Static_assert(sizeof(struct vinix_volume_request) == 32, "volume request ABI");
_Static_assert(sizeof(struct vinix_block_status) == 128, "block status ABI");
_Static_assert(offsetof(struct vinix_volume_request, length) == 16, "volume geometry ABI");
#endif
