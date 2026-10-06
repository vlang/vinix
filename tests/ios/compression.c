// SPDX-License-Identifier: GPL-2.0-or-later
#include <zlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
_Static_assert(sizeof(z_stream) == 112, "Darwin ARM64 zlib ABI");
static unsigned allocations, releases;
static void *allocate(void *context, unsigned count, unsigned size) {
    if (context != &allocations) abort();
    ++allocations; return calloc(count, size);
}
static void release(void *context, void *pointer) {
    if (context != &allocations) abort();
    ++releases; free(pointer);
}
int main(void) {
    const unsigned char original[] = "Vinix runs native iOS compression callbacks";
    unsigned char compressed[256], output[256];
    z_stream encoder = {0}, decoder = {0};
    encoder.zalloc = allocate; encoder.zfree = release; encoder.opaque = &allocations;
    if (deflateInit2(&encoder, 6, Z_DEFLATED, 15, 8, Z_DEFAULT_STRATEGY) != Z_OK) abort();
    encoder.next_in = (unsigned char *)original; encoder.avail_in = sizeof(original);
    encoder.next_out = compressed; encoder.avail_out = sizeof(compressed);
    if (deflate(&encoder, Z_FINISH) != Z_STREAM_END) abort();
    unsigned length = (unsigned)encoder.total_out;
    if (deflateReset(&encoder) != Z_OK || deflateEnd(&encoder) != Z_OK) abort();
    decoder.zalloc = allocate; decoder.zfree = release; decoder.opaque = &allocations;
    if (inflateInit(&decoder) != Z_OK || inflateReset(&decoder) != Z_OK || inflateReset2(&decoder, 15) != Z_OK) abort();
    decoder.next_in = compressed; decoder.avail_in = length;
    decoder.next_out = output; decoder.avail_out = sizeof(output);
    if (inflate(&decoder, Z_FINISH) != Z_STREAM_END || decoder.total_out != sizeof(original) ||
        memcmp(output, original, sizeof(original)) || inflateEnd(&decoder) != Z_OK) abort();
    decoder = (z_stream){0};
    if (inflateInit2(&decoder, 15) != Z_OK || inflateEnd(&decoder) != Z_OK) abort();
    unsigned long size = sizeof(output);
    if (uncompress(output, &size, compressed, length) != Z_OK || size != sizeof(original) ||
        memcmp(output, original, size) || crc32(0, original, sizeof(original)) != crc32(0, output, (unsigned)size) ||
        !allocations || allocations != releases) abort();
    puts("IOS-ZLIB: stream layout, native compression and iOS allocation callbacks");
    return 0;
}
