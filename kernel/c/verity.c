/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "verity.h"
#include <string.h>

static const uint32_t constants[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};
static uint32_t rotr(uint32_t value, unsigned shift)
{
    return value >> shift | value << (32 - shift);
}
static void compress(uint32_t state[8], const unsigned char block[64])
{
    uint32_t w[64];
    for (unsigned i = 0; i < 16; i++) {
        const unsigned char *p = block + i * 4;
        w[i] = (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
    }
    for (unsigned i = 16; i < 64; i++) {
        uint32_t a = w[i - 15], b = w[i - 2];
        w[i] = w[i - 16] + (rotr(a,7) ^ rotr(a,18) ^ (a >> 3)) + w[i - 7]
             + (rotr(b,17) ^ rotr(b,19) ^ (b >> 10));
    }
    uint32_t a=state[0],b=state[1],c=state[2],d=state[3];
    uint32_t e=state[4],f=state[5],g=state[6],h=state[7];
    for (unsigned i = 0; i < 64; i++) {
        uint32_t first = h + (rotr(e,6)^rotr(e,11)^rotr(e,25)) + ((e&f)^(~e&g)) + constants[i] + w[i];
        uint32_t second = (rotr(a,2)^rotr(a,13)^rotr(a,22)) + ((a&b)^(a&c)^(b&c));
        h=g; g=f; f=e; e=d+first; d=c; c=b; b=a; a=first+second;
    }
    state[0]+=a; state[1]+=b; state[2]+=c; state[3]+=d;
    state[4]+=e; state[5]+=f; state[6]+=g; state[7]+=h;
}
void vinix_verity_sha256(const void *input, size_t length, unsigned char output[32])
{
    const unsigned char *data = input;
    uint32_t state[8] = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
    size_t at = 0;
    while (length - at >= 64) { compress(state, data + at); at += 64; }
    unsigned char tail[128] = {0};
    size_t remaining = length - at;
    if (remaining) memcpy(tail, data + at, remaining);
    tail[remaining] = 0x80;
    size_t padded = remaining < 56 ? 64 : 128;
    uint64_t bits = (uint64_t)length * 8;
    for (unsigned i = 0; i < 8; i++) tail[padded - 1 - i] = (unsigned char)(bits >> (i * 8));
    compress(state, tail);
    if (padded == 128) compress(state, tail + 64);
    for (unsigned i = 0; i < 32; i++) output[i] = (unsigned char)(state[i / 4] >> (24 - (i % 4) * 8));
}
static int hex_digit(char value)
{
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    return -1;
}
int vinix_verity_init(struct vinix_verity *v, uint64_t blocks, const char *hex, size_t length)
{
    memset(v, 0, sizeof(*v));
    if (!blocks || blocks > (uint64_t)INT64_MAX / VINIX_VERITY_BLOCK_BYTES || length != 64) return -1;
    for (unsigned i = 0; i < 32; i++) {
        int high = hex_digit(hex[i * 2]), low = hex_digit(hex[i * 2 + 1]);
        if (high < 0 || low < 0) return -1;
        v->root_hash[i] = (unsigned char)(high * 16 + low);
    }
    v->data_blocks = blocks;
    uint64_t counts[VINIX_VERITY_MAX_LEVELS];
    while (blocks > 1) {
        blocks = (blocks + 127) / 128;
        if (v->levels == VINIX_VERITY_MAX_LEVELS) return -1;
        counts[v->levels++] = blocks;
    }
    v->total_blocks = v->data_blocks;
    for (unsigned i = v->levels; i; i--) {
        v->level_start[i - 1] = v->total_blocks;
        if (counts[i - 1] > (uint64_t)INT64_MAX / VINIX_VERITY_BLOCK_BYTES - v->total_blocks) return -1;
        v->total_blocks += counts[i - 1];
    }
    return 0;
}
static int whitespace(char byte)
{
    return byte == ' ' || byte == '\t' || byte == '\r' || byte == '\n';
}
static const char *find_text(const char *text, const char *needle)
{
    size_t size = strlen(needle);
    for (; *text; text++) {
        size_t i = 0;
        while (i < size && text[i] && text[i] == needle[i]) i++;
        if (i == size) return text;
    }
    return NULL;
}
int vinix_verity_parse(const char *cmdline, struct vinix_verity *v, char *device, size_t capacity)
{
    if (!cmdline) return 0;
    size_t length = 0;
    while (length < 4096 && cmdline[length]) length++;
    if (length == 4096) return -1;
    const char *reserved = find_text(cmdline, "vinix.verity");
    if (!reserved) return 0;
    if (find_text(reserved + 1, "vinix.verity")) return -1;
    const char *conflicts[] = {"vinix.disk=","vinix.qemu_persist=","vinix.qemu_root=",
        "vinix.apple_ans=","vinix.ans_rw=","vinix.persist=","vinix.root","root="};
    for (unsigned i = 0; i < sizeof(conflicts) / sizeof(conflicts[0]); i++)
        if (find_text(cmdline, conflicts[i])) return -1;
    const char *value = NULL;
    size_t size = 0;
    for (size_t at = 0; at < length;) {
        while (at < length && whitespace(cmdline[at])) at++;
        size_t start = at;
        while (at < length && !whitespace(cmdline[at])) at++;
        if (at - start >= 13 && !memcmp(cmdline + start, "vinix.verity=", 13)) {
            if (value) return -1;
            value = cmdline + start + 13;
            size = at - start - 13;
        }
    }
    if (!value || reserved != value - 13 || size < 2 || value[0] != '1' || value[1] != ',') return -1;
    const char *path = value + 2, *end = value + size, *comma = path;
    while (comma < end && *comma != ',') comma++;
    size_t path_size = (size_t)(comma - path);
    if (comma == end || path_size <= 5 || path_size > 68 || path_size >= capacity || memcmp(path, "/dev/", 5)) return -1;
    for (size_t i = 5; i < path_size; i++) {
        char c = path[i];
        int alnum = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
        if (!alnum && (i == 5 || (c != '_' && c != '-' && c != '.'))) return -1;
    }
    const char *digits = comma + 1;
    if (digits == end || *digits < '1' || *digits > '9') return -1;
    uint64_t blocks = 0;
    comma = digits;
    while (comma < end && *comma != ',') {
        if (*comma < '0' || *comma > '9' || blocks > (UINT64_MAX - (unsigned)(*comma - '0')) / 10) return -1;
        blocks = blocks * 10 + (unsigned)(*comma++ - '0');
    }
    if (comma == end || vinix_verity_init(v, blocks, comma + 1, (size_t)(end - comma - 1))) return -1;
    memcpy(device, path, path_size);
    device[path_size] = 0;
    return 1;
}
int vinix_verity_check(const struct vinix_verity *v, uint64_t block, const void *data,
                       vinix_verity_reader reader, void *context, void *scratch)
{
    if (block >= v->data_blocks) return -1;
    unsigned char digest[32];
    vinix_verity_sha256(data, VINIX_VERITY_BLOCK_BYTES, digest);
    uint64_t index = block;
    for (unsigned level = 0; level < v->levels; level++) {
        uint64_t position = v->level_start[level] + index / 128;
        if (position >= v->total_blocks || reader(context, position, scratch)) return -1;
        if (memcmp(digest, (unsigned char *)scratch + (index % 128) * 32, 32)) return -1;
        vinix_verity_sha256(scratch, VINIX_VERITY_BLOCK_BYTES, digest);
        index /= 128;
    }
    return memcmp(digest, v->root_hash, 32) ? -1 : 0;
}
