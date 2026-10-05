/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_VERITY_H
#define VINIX_VERITY_H
#include <stddef.h>
#include <stdint.h>

#define VINIX_VERITY_BLOCK_BYTES 4096
#define VINIX_VERITY_MAX_LEVELS 8
#define VINIX_VERITY_DEVICE_BYTES 128
/* Headerless dm-verity version 1, SHA-256, no salt, one backing device.
 * Geometry and root hash come from the authenticated command line. */
struct vinix_verity {
    uint64_t data_blocks;
    uint64_t total_blocks;
    uint64_t level_start[VINIX_VERITY_MAX_LEVELS]; /* leaf first */
    uint32_t levels;
    unsigned char root_hash[32];
};
typedef int (*vinix_verity_reader)(void *, uint64_t, void *);
/* V exports omit C's const qualifiers; keep them for ordinary C callers. */
#ifdef VINIX_V_RUNTIME
#define VINIX_VERITY_CONST
#else
#define VINIX_VERITY_CONST const
#endif
int vinix_verity_init(struct vinix_verity *, uint64_t, VINIX_VERITY_CONST char *, size_t);
/* 0 absent, 1 valid, -1 malformed/duplicate/conflicting root selection. */
int vinix_verity_parse(VINIX_VERITY_CONST char *, struct vinix_verity *, char *, size_t);
/* Never allocates or exposes data; caller keeps data stable until copying it.
 * reader must fill an entire 4096-byte block, returning zero only on success. */
int vinix_verity_check(VINIX_VERITY_CONST struct vinix_verity *, uint64_t, VINIX_VERITY_CONST void *,
                       vinix_verity_reader, void *, void *);
void vinix_verity_sha256(VINIX_VERITY_CONST void *, size_t, unsigned char[32]);
#undef VINIX_VERITY_CONST
#endif
