/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Host harness for the unchanged production verifier. */
#include "verity.h"
#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ZERO_HASH "0000000000000000000000000000000000000000000000000000000000000000"
#define POLICY "vinix.verity=1,/dev/vda,129," ZERO_HASH

static void known_hash(const void *data, size_t size, const char *expected)
{
    unsigned char digest[32];
    char text[65];
    vinix_verity_sha256(data, size, digest);
    for (unsigned i = 0; i < 32; ++i) snprintf(text + i * 2, 3, "%02x", digest[i]);
    assert(!strcmp(text, expected));
}

static void primitives(void)
{
    known_hash(NULL, 0, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    known_hash("abc", 3, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    const char *long_message = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    known_hash(long_message, strlen(long_message),
               "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
    static unsigned char million[1000000];
    memset(million, 'a', sizeof(million));
    known_hash(million, sizeof(million),
               "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");

    const uint64_t blocks[] = {1, 2, 128, 129, 16384, 16385};
    const unsigned levels[] = {0, 1, 1, 2, 2, 3};
    const uint64_t totals[] = {1, 3, 129, 132, 16513, 16517};
    const uint64_t offsets[][3] = {{0}, {2}, {128}, {130, 129},
                                  {16385, 16384}, {16388, 16386, 16385}};
    struct vinix_verity policy;
    for (unsigned i = 0; i < 6; ++i) {
        assert(vinix_verity_init(&policy, blocks[i], ZERO_HASH, 64) == 0);
        assert(policy.data_blocks == blocks[i] && policy.total_blocks == totals[i]);
        assert(policy.levels == levels[i]);
        for (unsigned level = 0; level < levels[i]; ++level)
            assert(policy.level_start[level] == offsets[i][level]);
    }
    assert(vinix_verity_init(&policy, 0, ZERO_HASH, 64) == -1);
    assert(vinix_verity_init(&policy, UINT64_MAX, ZERO_HASH, 64) == -1);
    assert(vinix_verity_init(&policy, INT64_MAX / 4096, ZERO_HASH, 64) == -1);
    assert(vinix_verity_init(&policy, UINT64_C(1) << 50, ZERO_HASH, 64) == 0);
    assert(policy.levels == 8);
    assert(vinix_verity_init(&policy, 1, ZERO_HASH, 63) == -1);
    assert(vinix_verity_init(&policy, 1, ZERO_HASH, 65) == -1);
    assert(vinix_verity_init(&policy, 1,
        "A000000000000000000000000000000000000000000000000000000000000000", 64) == -1);

    char device[VINIX_VERITY_DEVICE_BYTES];
    assert(vinix_verity_parse(NULL, &policy, device, sizeof(device)) == 0);
    assert(vinix_verity_parse("", &policy, device, sizeof(device)) == 0);
    assert(vinix_verity_parse("console=ttyS0", &policy, device, sizeof(device)) == 0);
    assert(vinix_verity_parse(" \t" POLICY "\r\nquiet", &policy, device, sizeof(device)) == 1);
    assert(!strcmp(device, "/dev/vda") && policy.data_blocks == 129);
    assert(vinix_verity_parse(POLICY, &policy, device, 9) == 1);
    assert(vinix_verity_parse(POLICY, &policy, device, 8) == -1);
    const char *bad[] = {
        "vinix.verity", "vinix.verity=", "vinix.verity=1", "vinix.verity=1,",
        "vinix.verity=2,/dev/vda,129," ZERO_HASH,
        "vinix.verity=1,/dev/,129," ZERO_HASH,
        "vinix.verity=1,/dev/.vda,129," ZERO_HASH,
        "vinix.verity=1,/dev/-vda,129," ZERO_HASH,
        "vinix.verity=1,/dev/../vda,129," ZERO_HASH,
        "vinix.verity=1,/dev/vda/child,129," ZERO_HASH,
        "vinix.verity=1,/dev/vda,0," ZERO_HASH,
        "vinix.verity=1,/dev/vda,01," ZERO_HASH,
        "vinix.verity=1,/dev/vda,+1," ZERO_HASH,
        "vinix.verity=1,/dev/vda,-1," ZERO_HASH,
        "vinix.verity=1,/dev/vda,18446744073709551616," ZERO_HASH,
        "vinix.verity=1,/dev/vda,2251799813685247," ZERO_HASH,
        "vinix.verity=1,/dev/vda,1,", "vinix.verity=1,/dev/vda,1," ZERO_HASH "0",
        "vinix.verity=1,/dev/vda,1," ZERO_HASH ",", "x=" POLICY,
        "vinix.verityx=1,/dev/vda,129," ZERO_HASH,
        POLICY " " POLICY, POLICY " x=vinix.verity", "x=vinix.verity " POLICY,
        POLICY " root=/dev/vda", POLICY " x=root=/dev/vda",
        POLICY " vinix.disk=auto", POLICY " vinix.qemu_persist=0",
        POLICY " vinix.qemu_root=0", POLICY " vinix.apple_ans=off",
        POLICY " vinix.ans_rw=0", POLICY " vinix.persist=0", POLICY " vinix.rootfs=0",
    };
    for (unsigned i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
        memset(device, '!', sizeof(device));
        assert(vinix_verity_parse(bad[i], &policy, device, sizeof(device)) == -1);
        for (unsigned byte = 0; byte < sizeof(device); ++byte) assert(device[byte] == '!');
    }
    char lengthy[4097];
    memset(lengthy, 'a', sizeof(lengthy));
    lengthy[4096] = 0;
    assert(vinix_verity_parse(lengthy, &policy, device, sizeof(device)) == -1);
    lengthy[4095] = 0;
    assert(vinix_verity_parse(lengthy, &policy, device, sizeof(device)) == 0);
    /* Exercise NUL termination at every parser boundary, including the
     * find_text replacement, with ASan watching each exact-sized string. */
    const char *original = POLICY;
    const unsigned char mutations[] = {0, ',', '/', '\t', 'A', 0xff};
    size_t length = strlen(original);
    for (size_t size = 0; size < length; ++size) {
        char *prefix = malloc(size + 1);
        assert(prefix);
        memcpy(prefix, original, size);
        prefix[size] = 0;
        int result = vinix_verity_parse(prefix, &policy, device, sizeof(device));
        assert(result >= -1 && result <= 1);
        free(prefix);
    }
    for (size_t at = 0; at < length; ++at)
        for (unsigned change = 0; change < sizeof(mutations); ++change) {
            char *text = malloc(length + 1);
            assert(text);
            memcpy(text, original, length + 1);
            text[at] = (char)mutations[change];
            int result = vinix_verity_parse(text, &policy, device, sizeof(device));
            assert(result >= -1 && result <= 1);
            free(text);
        }
    puts("VERITY C PRIMITIVES PASS");
}

struct source {
    FILE *file;
    const struct vinix_verity *policy;
    unsigned reads, fail_call, error_after_complete;
    uint64_t corrupt_block;
    unsigned corrupt_byte;
};

static int read_hash(void *context, uint64_t block, void *output)
{
    struct source *source = context;
    assert(block >= source->policy->data_blocks && block < source->policy->total_blocks);
    ++source->reads;
    if (source->fail_call == source->reads && !source->error_after_complete) {
        /* A partial backing-device read must return failure, even if the
         * scratch buffer still contains valid bytes from a previous read. */
        memset(output, 0, 17);
        return -1;
    }
    if (fseek(source->file, (long)(block * VINIX_VERITY_BLOCK_BYTES), SEEK_SET) ||
        fread(output, 1, VINIX_VERITY_BLOCK_BYTES, source->file) != VINIX_VERITY_BLOCK_BYTES)
        return -1;
    /* These bytes would authenticate successfully if the verifier ignored
     * the callback status. Both positive and negative errors must fail. */
    if (source->fail_call == source->reads) return 1;
    if (block == source->corrupt_block) ((unsigned char *)output)[source->corrupt_byte] ^= 1;
    return 0;
}

struct guarded_block {
    unsigned char before[32], bytes[VINIX_VERITY_BLOCK_BYTES], after[32];
};

static void guard(const struct guarded_block *block)
{
    for (unsigned i = 0; i < 32; ++i) assert(block->before[i] == 0xa5 && block->after[i] == 0xa5);
}

static void image_checks(const char *filename, uint64_t blocks, const char *digest)
{
    struct vinix_verity policy;
    assert(vinix_verity_init(&policy, blocks, digest, strlen(digest)) == 0);
    struct vinix_verity immutable = policy;
    struct source source = {.file = fopen(filename, "rb"), .policy = &policy,
                            .corrupt_block = UINT64_MAX};
    assert(source.file);
    assert(fseek(source.file, 0, SEEK_END) == 0);
    assert((uint64_t)ftell(source.file) == policy.total_blocks * VINIX_VERITY_BLOCK_BYTES);
    struct guarded_block data, scratch;
    memset(&data, 0xa5, sizeof(data));
    memset(&scratch, 0xa5, sizeof(scratch));
    unsigned char saved[VINIX_VERITY_BLOCK_BYTES];
    /* Every data block crosses the real callback and stored tree, including
     * digest-slot and hash-level transitions at 128 and 16384. */
    for (uint64_t block = 0; block < blocks; ++block) {
        assert(fseek(source.file, (long)(block * VINIX_VERITY_BLOCK_BYTES), SEEK_SET) == 0);
        assert(fread(data.bytes, 1, sizeof(data.bytes), source.file) == sizeof(data.bytes));
        memcpy(saved, data.bytes, sizeof(saved));
        source.reads = 0;
        assert(vinix_verity_check(&policy, block, data.bytes, read_hash, &source, scratch.bytes) == 0);
        assert(source.reads == policy.levels);
        assert(!memcmp(saved, data.bytes, sizeof(saved)) && !memcmp(&immutable, &policy, sizeof(policy)));
        guard(&data); guard(&scratch);
    }
    /* Reuse the same buffers repeatedly; production object symbol checks
     * below establish that this path has no allocator call. */
    uint64_t last = blocks - 1;
    for (unsigned repeat = 0; repeat < 256; ++repeat)
        assert(vinix_verity_check(&policy, last, data.bytes, read_hash, &source, scratch.bytes) == 0);
    data.bytes[4095] ^= 1;
    assert(vinix_verity_check(&policy, last, data.bytes, read_hash, &source, scratch.bytes) == -1);
    data.bytes[4095] ^= 1;
    policy.root_hash[0] ^= 1;
    assert(vinix_verity_check(&policy, last, data.bytes, read_hash, &source, scratch.bytes) == -1);
    policy.root_hash[0] ^= 1;
    uint64_t index = last;
    for (unsigned level = 0; level < policy.levels; ++level) {
        source.corrupt_block = policy.level_start[level] + index / 128;
        /* Each stored hash byte, including unused padding, is authenticated. */
        for (unsigned byte = 0; byte < VINIX_VERITY_BLOCK_BYTES; ++byte) {
            source.corrupt_byte = byte;
            assert(vinix_verity_check(&policy, last, data.bytes, read_hash, &source, scratch.bytes) == -1);
        }
        source.corrupt_block = UINT64_MAX;
        source.fail_call = level + 1;
        source.reads = 0;
        assert(vinix_verity_check(&policy, last, data.bytes, read_hash, &source, scratch.bytes) == -1);
        source.error_after_complete = 1;
        source.reads = 0;
        assert(vinix_verity_check(&policy, last, data.bytes, read_hash, &source, scratch.bytes) == -1);
        source.error_after_complete = 0;
        source.fail_call = 0;
        index /= 128;
    }
    source.reads = 0;
    assert(vinix_verity_check(&policy, blocks, NULL, read_hash, &source, scratch.bytes) == -1);
    assert(vinix_verity_check(&policy, UINT64_MAX, NULL, read_hash, &source, scratch.bytes) == -1);
    assert(source.reads == 0);
    guard(&data); guard(&scratch);
    assert(!memcmp(&immutable, &policy, sizeof(policy)));
    assert(fclose(source.file) == 0);
    printf("VERITY C IMAGE PASS blocks=%" PRIu64 " levels=%u\n", blocks, policy.levels);
}

int main(int argc, char **argv)
{
    if (argc == 1) primitives();
    else {
        assert(argc == 4);
        image_checks(argv[1], strtoull(argv[2], NULL, 10), argv[3]);
    }
    return 0;
}
