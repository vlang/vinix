/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "apple_dcp_backlight.h"

static struct vinix_dcp_bl *new_state(unsigned layout, uint32_t maximum,
                                      uint32_t scale, int known)
{
    struct vinix_dcp_bl *bl = malloc(vinix_dcp_bl_state_size());
    assert(bl);
    memset(bl, 0xa5, vinix_dcp_bl_state_size());
    assert(vinix_dcp_bl_init(bl, layout, maximum, scale, 50 * scale, known) == 0);
    return bl;
}

static void contains(struct vinix_dcp_bl *bl, const char *needle)
{
    char text[VINIX_DCP_BL_TEXT_CAPACITY];
    int length = vinix_dcp_bl_format(bl, text, sizeof(text));
    assert(length > 0 && (size_t)length == strlen(text));
    if (!strstr(text, needle)) {
        fprintf(stderr, "missing '%s' in:\n%s", needle, text);
        abort();
    }
}

static void test_calibration(void)
{
    uint32_t nits, dac = 0, previous = 0;
    for (nits = 2; nits <= 509; ++nits) {
        assert(vinix_dcp_bl_nits_to_dac(nits, &dac) == 0);
        assert(dac >= previous);
        assert((dac & 15U) == 0);
        previous = dac;
    }
    assert(vinix_dcp_bl_nits_to_dac(2, &dac) == 0 && dac == 0);
    assert(vinix_dcp_bl_nits_to_dac(99, &dac) == 0 && dac == 0x58f058d0);
    assert(vinix_dcp_bl_nits_to_dac(100, &dac) == 0 && dac == 0x592858d0);
    assert(vinix_dcp_bl_nits_to_dac(101, &dac) == 0 && dac == 0x596058e0);
    assert(vinix_dcp_bl_nits_to_dac(102, &dac) == 0 && dac == 0x599858e0);
    assert(vinix_dcp_bl_nits_to_dac(103, &dac) == 0 && dac == 0x59d058f0);
    dac = 0xdeadbeef;
    assert(vinix_dcp_bl_nits_to_dac(0, &dac) == -1 && dac == 0xdeadbeef);
    assert(vinix_dcp_bl_nits_to_dac(1, &dac) == -1);
    assert(vinix_dcp_bl_nits_to_dac(510, &dac) == -1);
    assert(vinix_dcp_bl_nits_to_dac(UINT32_MAX, &dac) == -1);
    assert(vinix_dcp_bl_nits_to_dac(200, NULL) == -1);
}

static void test_parser(void)
{
    static const char *bad[] = {
        "", "\n", "0", "1", "510", "-20", "+20", " 20", "20 ",
        "20\n\n", "20\r\n", "20junk", "20 30", "4294967296", "9999999999999999",
    };
    uint32_t value = 0;
    size_t i;
    assert(vinix_dcp_bl_parse("2", 1, &value) == 0 && value == 2);
    assert(vinix_dcp_bl_parse("400\n", 4, &value) == 0 && value == 400);
    assert(vinix_dcp_bl_parse("0509", 4, &value) == 0 && value == 509);
    for (i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
        value = 12345;
        assert(vinix_dcp_bl_parse(bad[i], strlen(bad[i]), &value) == -1);
        assert(value == 12345);
    }
    assert(vinix_dcp_bl_parse("20\0", 3, &value) == -1);
    assert(vinix_dcp_bl_parse("00000000000000020", 17, &value) == -1);
    assert(vinix_dcp_bl_parse(NULL, 1, &value) == -1);
    assert(vinix_dcp_bl_parse("20", 2, NULL) == -1);
    /* Every byte is checked; do not treat a NUL as end of a write. */
    for (i = 0; i < 256; ++i) {
        unsigned char text[3] = {'2', '0', (unsigned char)i};
        int valid = (i >= '0' && i <= '9') || i == '\n';
        assert((vinix_dcp_bl_parse(text, 3, &value) == 0) == valid);
    }
}

/* Independent packed-layout description of the upstream dcp_swap prefix.
 * Assert actual offsetof/sizeof, rather than merely duplicating offsets. */
struct rectangle { uint32_t x, y, w, h; };
#define SWAP_PREFIX \
    uint64_t timestamps[8]; uint64_t flags[2]; uint32_t swap_id; \
    uint32_t surface_ids[4]; struct rectangle src[4]; \
    uint32_t surface_flags[4], surface_unknown[4]; struct rectangle dst[4]; \
    uint32_t enabled, completed, background; \
    unsigned char unknown_110[0x1b8]; uint32_t unknown_2c8; \
    unsigned char unknown_2cc[0x14]; uint32_t unknown_2e0
struct __attribute__((packed)) swap12 {
    SWAP_PREFIX;
    uint16_t unknown_2e2;
    uint64_t bl_unk;
    uint32_t bl_value;
    uint8_t bl_power;
    uint8_t tail[0x2d];
};
struct __attribute__((packed)) swap13 {
    SWAP_PREFIX;
    uint8_t unknown_2e2[3];
    uint64_t bl_unk;
    uint32_t bl_value;
    uint8_t bl_power;
    uint8_t tail[0x2d];
    uint8_t new_tail[0x13f];
    uint64_t unknown_final;
};

static void test_layout(void)
{
    unsigned char buffer[0x500], original[0x500];
    unsigned layout;
    size_t i, size, off;
    assert(sizeof(struct swap12) == 0x320);
    assert(sizeof(struct swap13) == 0x468);
    assert(offsetof(struct swap12, bl_unk) == 0x2e6);
    assert(offsetof(struct swap13, bl_unk) == 0x2e7);
    for (layout = 1; layout <= 2; ++layout) {
        size = layout == 1 ? sizeof(struct swap12) : sizeof(struct swap13);
        off = 1 + (layout == 1 ? offsetof(struct swap12, bl_unk) : offsetof(struct swap13, bl_unk));
        memset(buffer, 0xa5, sizeof(buffer));
        memcpy(original, buffer, sizeof(buffer));
        assert(vinix_dcp_bl_patch_swap(layout, 99, buffer + 1, size) == 0);
        for (i = 0; i < sizeof(buffer); ++i)
            if (i < off || i >= off + 13)
                assert(buffer[i] == original[i]);
        assert(buffer[off] == 1);
        for (i = 1; i < 8; ++i)
            assert(buffer[off + i] == 0);
        assert(buffer[off + 8] == 0xd0);
        assert(buffer[off + 9] == 0x58);
        assert(buffer[off + 10] == 0xf0);
        assert(buffer[off + 11] == 0x58);
        assert(buffer[off + 12] == 0x40);
        memcpy(buffer, original, sizeof(buffer));
        for (i = 0; i < size; ++i) {
            assert(vinix_dcp_bl_patch_swap(layout, 99, buffer + 1, i) == -1);
            assert(memcmp(buffer, original, sizeof(buffer)) == 0);
        }
        assert(vinix_dcp_bl_patch_swap(layout, 510, buffer, size) == -1);
        assert(memcmp(buffer, original, sizeof(buffer)) == 0);
    }
    assert(vinix_dcp_bl_patch_swap(0, 99, buffer, sizeof(buffer)) == -2);
    assert(vinix_dcp_bl_patch_swap(3, 99, buffer, sizeof(buffer)) == -2);
    assert(vinix_dcp_bl_patch_swap(1, 99, NULL, 0x320) == -1);
}

static void test_initialization(void)
{
    struct vinix_dcp_bl *bl = new_state(1, 400, 65536, 1);
    unsigned char *original = malloc(vinix_dcp_bl_state_size());
    unsigned char swap[0x468];
    uint64_t token = 99;
    assert(original);
    memcpy(original, bl, vinix_dcp_bl_state_size());
    assert(vinix_dcp_bl_init(bl, 1, 400, 0, 0, 0) == -1);
    assert(vinix_dcp_bl_init(bl, 1, 1, 100, 0, 0) == -1);
    assert(vinix_dcp_bl_init(bl, 3, 400, 100, 0, 0) == -2);
    assert(memcmp(bl, original, vinix_dcp_bl_state_size()) == 0);
    assert(vinix_dcp_bl_init(bl, 1, 400, 100, 40100, 1) == -1);
    assert(memcmp(bl, original, vinix_dcp_bl_state_size()) == 0);
    assert(vinix_dcp_bl_request(bl, 200) == -3);
    assert(vinix_dcp_bl_prepare(bl, swap, sizeof(swap), &token) == -3 && token == 99);
    assert(vinix_dcp_bl_set_online(bl, 1) == 0);
    assert(vinix_dcp_bl_prepare(bl, swap, sizeof(swap), &token) == 1 && token == 99);
    contains(bl, "requested_nits=unknown\n");
    contains(bl, "actual_nits=50\n");
    contains(bl, "pending=0\n");
    assert(vinix_dcp_bl_write(bl, "401", 3) == -1);
    contains(bl, "requested_nits=unknown\n");
    free(original);
    free(bl);
    bl = new_state(2, 1600, 100, 0);
    contains(bl, "max_nits=509\n");
    contains(bl, "actual_nits=unknown\n");
    free(bl);
}

static void test_transactions(void)
{
    struct vinix_dcp_bl *bl = new_state(1, 400, 1000, 1);
    unsigned char swap[0x468];
    uint64_t a = 0, b = 0, c = 0, saved = 77;
    assert(vinix_dcp_bl_set_online(bl, 1) == 0);
    assert(vinix_dcp_bl_write(bl, "100\n", 4) == 0);
    assert(vinix_dcp_bl_prepare(bl, swap, 10, &saved) == -1 && saved == 77);
    contains(bl, "pending=1\n");
    assert(vinix_dcp_bl_prepare(bl, swap, sizeof(swap), &a) == 0 && a != 0);
    assert(vinix_dcp_bl_prepare(bl, swap, sizeof(swap), &saved) == -4 && saved == 77);
    assert(vinix_dcp_bl_request(bl, 200) == 0); /* newer write while swap is active */
    assert(vinix_dcp_bl_complete(bl, a, 1) == 0);
    contains(bl, "requested_nits=200\n");
    contains(bl, "pending=1\n");
    contains(bl, "actual_nits=50\n"); /* never fabricated */
    assert(vinix_dcp_bl_prepare(bl, swap, sizeof(swap), &b) == 0 && b > a);
    assert(vinix_dcp_bl_complete(bl, a, 1) == -5); /* stale ACK */
    assert(vinix_dcp_bl_complete(bl, b, 0) == 0); /* real error response */
    contains(bl, "pending=1\n");
    assert(vinix_dcp_bl_prepare(bl, swap, sizeof(swap), &c) == 0 && c > b);
    assert(vinix_dcp_bl_complete(bl, b, 1) == -5); /* old retry's ACK */
    assert(vinix_dcp_bl_complete(bl, c, 1) == 0);
    contains(bl, "pending=0\n");
    contains(bl, "actual_nits=50\n");
    assert(vinix_dcp_bl_publish(bl, 199999) == 0);
    contains(bl, "actual_nits=199\n");
    assert(vinix_dcp_bl_prepare(bl, swap, sizeof(swap), &saved) == 1 && saved == 77);
    assert(vinix_dcp_bl_complete(bl, c, 1) == -5);
    free(bl);
}

static void test_recovery(void)
{
    struct vinix_dcp_bl *bl = new_state(2, 400, 100, 0);
    unsigned char swap[0x468];
    uint64_t old = 0, next = 0;
    assert(vinix_dcp_bl_set_online(bl, 1) == 0);
    assert(vinix_dcp_bl_request(bl, 100) == 0);
    assert(vinix_dcp_bl_prepare(bl, swap, sizeof(swap), &old) == 0);
    assert(vinix_dcp_bl_set_online(bl, 0) == 0);
    contains(bl, "actual_nits=unknown\n");
    contains(bl, "online=0\n");
    assert(vinix_dcp_bl_publish(bl, 10000) == -3);
    assert(vinix_dcp_bl_complete(bl, old, 1) == -3);
    assert(vinix_dcp_bl_write(bl, "200", 3) == -3);
    assert(vinix_dcp_bl_set_online(bl, 1) == 0);
    contains(bl, "requested_nits=100\n");
    assert(vinix_dcp_bl_prepare(bl, swap, sizeof(swap), &next) == 0 && next > old);
    assert(vinix_dcp_bl_complete(bl, old, 1) == -5);
    assert(vinix_dcp_bl_complete(bl, next, 1) == 0);
    contains(bl, "pending=0\n");
    assert(vinix_dcp_bl_set_online(bl, 0) == 0);
    assert(vinix_dcp_bl_set_online(bl, 1) == 0);
    contains(bl, "pending=1\n"); /* reapply across firmware restart */
    free(bl);
}

static void test_format_bounds(void)
{
    struct vinix_dcp_bl *bl = new_state(2, 400, 1, 0);
    char valid[VINIX_DCP_BL_TEXT_CAPACITY], guard[VINIX_DCP_BL_TEXT_CAPACITY];
    size_t i;
    int length;
    assert(vinix_dcp_bl_set_online(bl, 1) == 0);
    assert(vinix_dcp_bl_publish(bl, UINT32_MAX) == 0);
    length = vinix_dcp_bl_format(bl, valid, sizeof(valid));
    assert(length > 0);
    for (i = 0; i <= (size_t)length; ++i) {
        size_t j;
        memset(guard, 0x5a, sizeof(guard));
        assert(vinix_dcp_bl_format(bl, guard, i) == -1);
        for (j = 0; j < sizeof(guard); ++j)
            assert(guard[j] == 0x5a);
    }
    assert(vinix_dcp_bl_format(bl, guard, (size_t)length + 1) == length);
    assert(strcmp(valid, guard) == 0);
    free(bl);
}

int main(void)
{
    test_calibration();
    test_parser();
    test_layout();
    test_initialization();
    test_transactions();
    test_recovery();
    test_format_bounds();
    puts("PASS: 7 groups (calibration, parser, wire layouts, init, transactions, recovery, formatting)");
    return 0;
}
