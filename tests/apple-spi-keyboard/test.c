/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define VINIX_APPLE_SPI_TEST
/* Test the exact production implementation, not a reimplemented model. */
#include "../../kernel/c/apple_spi_keyboard.c"

static unsigned tests;
static void le16(uint8_t *p, uint16_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }
static void seal_packet(uint8_t p[256]) { le16(p + 254, crc16(p, 254)); }
static void message(uint8_t m[20], uint8_t mods, uint8_t fn, const uint8_t keys[6])
{
    memset(m, 0, 20);
    m[0] = 0x10; m[1] = 1; m[6] = 10; m[8] = 1; m[9] = mods; m[17] = fn;
    memcpy(m + 11, keys, 6);
    le16(m + 18, crc16(m, 18));
}
static void fragment(uint8_t p[256], const uint8_t m[20], unsigned offset, unsigned n)
{
    memset(p, 0, 256);
    p[0] = 0x20; p[1] = 1;
    le16(p + 2, (uint16_t)offset); le16(p + 4, (uint16_t)(20 - offset - n));
    le16(p + 6, (uint16_t)n); memcpy(p + 8, m + offset, n); seal_packet(p);
}
static void packet(uint8_t p[256], uint8_t mods, uint8_t fn, const uint8_t keys[6])
{
    uint8_t m[20]; message(m, mods, fn, keys); fragment(p, m, 0, 20);
}
static size_t feed(struct decoder *d, uint64_t now, uint8_t mods, uint8_t fn,
    const uint8_t keys[6], uint8_t out[128])
{
    uint8_t p[256]; packet(p, mods, fn, keys);
    return decode_packet(d, p, 256, now, 0, out, 128);
}
static size_t single(struct decoder *d, uint64_t now, uint8_t mods, uint8_t fn,
    uint8_t key, uint8_t out[128])
{
    uint8_t keys[6] = {key, 0, 0, 0, 0, 0};
    return feed(d, now, mods, fn, keys, out);
}
static void expect_bytes(struct key_bytes b, const uint8_t *bytes, size_t n)
{
    assert(b.len == n); assert(memcmp(b.data, bytes, n) == 0);
}
static void test_crc(void)
{
    assert(crc16((const uint8_t *)"123456789", 9) == 0xbb3d);
    assert(crc16((const uint8_t *)"", 0) == 0);
    uint8_t p[256], keys[6] = {4}; packet(p, 0, 0, keys);
    assert(crc16(p, 256) == 0 && crc16(p + 8, 20) == 0);
    assert(read_le16(p + 6) == 20 && read_le16(p + 14) == 10);
    p[127] ^= 1; assert(crc16(p, 256) != 0);
}
static void test_press_release_duplicate(void)
{
    struct decoder d = {0}; uint8_t out[128];
    assert(single(&d, 100, 0, 0, 4, out) == 1 && out[0] == 'a');
    uint64_t repeat = d.repeat_at;
    assert(single(&d, 200, 0, 0, 4, out) == 0 && d.repeat_at == repeat);
    assert(single(&d, 300, 0, 0, 0, out) == 0 && d.repeat_key == 0);
    assert(single(&d, 400, 0, 0, 4, out) == 1 && out[0] == 'a');
}
static void test_six_keys_reordering(void)
{
    struct decoder d = {0}; uint8_t out[128], a[6] = {4, 5, 6, 7, 8, 9};
    uint8_t b[6] = {9, 7, 8, 5, 4, 6};
    assert(feed(&d, 1, 0, 0, a, out) == 6 && !memcmp(out, "abcdef", 6));
    assert(feed(&d, 2, 0, 0, b, out) == 0);
    memset(&d, 0, sizeof(d));
    uint8_t duplicates[6] = {4, 4, 4, 5, 5, 4};
    assert(feed(&d, 3, 0, 0, duplicates, out) == 2 && !memcmp(out, "ab", 2));
}
static void test_modifiers_and_caps(void)
{
    struct decoder d = {0}; uint8_t out[128];
    assert(single(&d, 1, 0x22, 0, 4, out) == 1 && out[0] == 'A');
    assert(single(&d, 2, 0x20, 0, 0, out) == 0); /* release only left Shift */
    assert(single(&d, 3, 0x20, 0, 5, out) == 1 && out[0] == 'B');
    single(&d, 4, 0, 0, 0, out);
    assert(single(&d, 5, 0, 0, 57, out) == 0 && d.caps);
    assert(single(&d, 6, 0, 0, 57, out) == 0 && d.caps);
    single(&d, 7, 0, 0, 0, out);
    assert(single(&d, 8, 0, 0, 4, out) == 1 && out[0] == 'A');
    single(&d, 9, 0, 0, 0, out);
    assert(single(&d, 10, 2, 0, 4, out) == 1 && out[0] == 'a');
    single(&d, 11, 0, 0, 0, out);
    assert(single(&d, 12, 0, 0, 30, out) == 1 && out[0] == '1');
    single(&d, 13, 0, 0, 0, out);
    assert(single(&d, 14, 0, 0, 57, out) == 0 && !d.caps);
}
static void test_ascii_controls(void)
{
    for (unsigned key = 4; key <= 29; ++key) {
        struct key_bytes b = encode_key((uint8_t)key, 0x10, 0, 0, 0);
        assert(b.len == 1 && b.data[0] == key - 3);
    }
    struct key_bytes b = encode_key(6, 0x11, 0, 0, 0);
    assert(b.len == 1 && b.data[0] == 3); /* both Ctrl keys */
    b = encode_key(4, 0x40, 0, 0, 0); expect_bytes(b, (const uint8_t *)"\033a", 2);
    b = encode_key(44, 1, 0, 0, 0); assert(b.len == 1 && b.data[0] == 0);
    b = encode_key(31, 1, 0, 0, 0); assert(b.len == 1 && b.data[0] == 0);
    b = encode_key(56, 3, 0, 0, 0); assert(b.len == 1 && b.data[0] == 127);
    b = encode_key(40, 0, 0, 0, 0); assert(b.len == 1 && b.data[0] == '\r');
    b = encode_key(42, 0, 0, 0, 0); assert(b.len == 1 && b.data[0] == '\b');
    b = encode_key(43, 2, 0, 0, 0); expect_bytes(b, (const uint8_t *)"\033[Z", 3);
    for (unsigned i = 0; i < 10; ++i) {
        b = encode_key((uint8_t)(30 + i), 2, 1, 0, 0);
        assert(b.len == 1 && b.data[0] == (uint8_t)"!@#$%^&*()"[i]);
    }
}
static void test_navigation_fn_and_function_keys(void)
{
    expect_bytes(encode_key(82, 0, 0, 0, 0), (const uint8_t *)"\033[A", 3);
    expect_bytes(encode_key(82, 0, 0, 0, 1), (const uint8_t *)"\033OA", 3);
    expect_bytes(encode_key(80, 0, 0, 1, 0), (const uint8_t *)"\033[H", 3);
    expect_bytes(encode_key(79, 0, 0, 1, 1), (const uint8_t *)"\033OF", 3);
    expect_bytes(encode_key(81, 0, 0, 1, 0), (const uint8_t *)"\033[6~", 4);
    expect_bytes(encode_key(82, 0, 0, 1, 0), (const uint8_t *)"\033[5~", 4);
    expect_bytes(encode_key(42, 0, 0, 1, 0), (const uint8_t *)"\033[3~", 4);
    expect_bytes(encode_key(58, 0, 0, 0, 0), (const uint8_t *)"\033OP", 3);
    expect_bytes(encode_key(69, 0, 0, 0, 0), (const uint8_t *)"\033[24~", 5);
    expect_bytes(encode_key(69, 4, 0, 0, 0), (const uint8_t *)"\033\033[24~", 6);
    assert(encode_key(255, 0, 0, 0, 0).len == 0);
}
/* Cmd-Tab, and the release of Cmd that closes the window switcher. Neither is
 * a byte a terminal has ever produced, so the whole of what the desktop sees
 * is checked here rather than only that something came out. */
static void test_command_tab(void)
{
    struct decoder d = {0}; uint8_t out[128];
    expect_bytes(encode_key(43, 0x08, 0, 0, 0), (const uint8_t *)"\033[9;9u", 6);
    expect_bytes(encode_key(43, 0x80, 0, 0, 0), (const uint8_t *)"\033[9;9u", 6);
    expect_bytes(encode_key(43, 0x0a, 0, 0, 0), (const uint8_t *)"\033[9;10u", 7);
    /* Without Cmd it is still a tab, and Shift-Tab still back-tab. */
    expect_bytes(encode_key(43, 0, 0, 0, 0), (const uint8_t *)"\t", 1);
    expect_bytes(encode_key(43, 2, 0, 0, 0), (const uint8_t *)"\033[Z", 3);

    /* Cmd down alone says nothing; each Tab is one chord; letting Cmd go ends
     * it once, and a Cmd that was never chorded with ends nothing. */
    assert(single(&d, 100, 0x08, 0, 0, out) == 0);
    assert(single(&d, 200, 0x08, 0, 43, out) == 6 && !memcmp(out, "\033[9;9u", 6));
    assert(single(&d, 300, 0x08, 0, 0, out) == 0);
    assert(single(&d, 400, 0x0a, 0, 43, out) == 7 && !memcmp(out, "\033[9;10u", 7));
    assert(single(&d, 500, 0, 0, 0, out) == 12
        && !memcmp(out, "\033[57444;1:3u", 12));
    assert(single(&d, 600, 0, 0, 0, out) == 0);
    assert(single(&d, 700, 0x08, 0, 0, out) == 0);
    assert(single(&d, 800, 0, 0, 0, out) == 0);

    /* Held down, Cmd-Tab repeats like any other key: the switcher walks on. */
    assert(single(&d, 1000, 0x08, 0, 43, out) == 6);
    assert(repeat_key(&d, 1000 + REPEAT_DELAY, 0, out, 128) == 6
        && !memcmp(out, "\033[9;9u", 6));
}

static void test_repeat(void)
{
    struct decoder d = {0}; uint8_t out[128];
    single(&d, 100, 0, 0, 4, out);
    assert(repeat_key(&d, 100 + REPEAT_DELAY - 1, 0, out, 128) == 0);
    assert(repeat_key(&d, 100 + REPEAT_DELAY, 0, out, 128) == 1 && out[0] == 'a');
    assert(repeat_key(&d, 100 + REPEAT_DELAY + 1, 0, out, 128) == 0);
    single(&d, 101 + REPEAT_DELAY, 2, 0, 4, out); /* held key, new modifier */
    assert(repeat_key(&d, 100 + REPEAT_DELAY + REPEAT_PERIOD, 0, out, 128) == 1 && out[0] == 'A');
    assert(repeat_key(&d, 9999999999ULL, 0, out, 128) == 1); /* one, not a burst */
    single(&d, 10000000000ULL, 0, 0, 0, out);
    assert(repeat_key(&d, 10001000000ULL, 0, out, 128) == 0);
}
static void test_rollover(void)
{
    struct decoder d = {0}; uint8_t out[128];
    single(&d, 1, 0, 0, 4, out);
    for (uint8_t error = 1; error <= 3; ++error) {
        assert(single(&d, 2, 0, 0, error, out) == 0);
        assert(has_key(d.keys, 4));
        assert(repeat_key(&d, 1000000, 0, out, 128) == 0);
    }
    assert(single(&d, 1000001, 0, 0, 4, out) == 0);
    assert(repeat_key(&d, 1500001, 0, out, 128) == 1);
    assert(single(&d, 1500002, 0, 0, 0, out) == 0 && d.repeat_key == 0);
}
static void test_crc_and_identity_rejection(void)
{
    struct decoder d = {0}; uint8_t p[256], out[128], keys[6] = {4};
    packet(p, 0, 0, keys); p[11] ^= 1;
    assert(decode_packet(&d, p, 256, 1, 0, out, 128) == 0 && d.reports == 0);
    seal_packet(p); /* Good packet CRC, bad message CRC. */
    assert(decode_packet(&d, p, 256, 2, 0, out, 128) == 0 && d.reports == 0);
    for (unsigned i = 0; i < 4; ++i) {
        packet(p, 0, 0, keys);
        if (i == 0) p[0] = 0x40;
        if (i == 1) p[1] = 2;
        if (i == 2) p[8] = 0x51;
        if (i == 3) p[16] = 2;
        le16(p + 26, crc16(p + 8, 18)); seal_packet(p);
        assert(decode_packet(&d, p, 256, 3, 0, out, 128) == 0 && d.reports == 0);
    }
    single(&d, 100, 0, 0, 4, out);
    packet(p, 0, 0, keys); p[254] ^= 1;
    decode_packet(&d, p, 256, 101, 0, out, 128);
    assert(repeat_key(&d, 1000000, 0, out, 128) == 0);
    assert(has_key(d.keys, 4)); /* Do not manufacture a release. */
}
static void test_fragmentation(void)
{
    uint8_t m[20], p[256], out[128], keys[6] = {4}; message(m, 0, 0, keys);
    for (unsigned split = 1; split < 20; ++split) {
        struct decoder d = {0};
        fragment(p, m, 0, split);
        assert(decode_packet(&d, p, 256, 1, 0, out, 128) == 0);
        fragment(p, m, split, 20 - split);
        assert(decode_packet(&d, p, 256, 2, 0, out, 128) == 1 && out[0] == 'a');
        assert(d.message_used == 0);
    }
    struct decoder d = {0};
    fragment(p, m, 10, 10);
    assert(decode_packet(&d, p, 256, 1, 0, out, 128) == 0);
    fragment(p, m, 0, 10); decode_packet(&d, p, 256, 2, 0, out, 128);
    fragment(p, m, 11, 9);
    assert(decode_packet(&d, p, 256, 3, 0, out, 128) == 0 && d.message_used == 0);
    fragment(p, m, 0, 10); decode_packet(&d, p, 256, 4, 0, out, 128);
    fragment(p, m, 10, 10);
    assert(decode_packet(&d, p, 256, 4 + FRAGMENT_US, 0, out, 128) == 0);
    fragment(p, m, 0, 20);
    assert(decode_packet(&d, p, 256, 5 + FRAGMENT_US, 0, out, 128) == 1);
}
static void test_lengths_and_output_bounds(void)
{
    uint8_t p[256], keys[6] = {69, 68, 67, 66, 65, 64}, guarded[32];
    for (size_t length = 0; length <= 256; ++length) {
        struct decoder d = {0}; packet(p, 4, 0, keys);
        if (length != 256) assert(decode_packet(&d, p, length, 1, 0, guarded, 32) == 0);
    }
    for (size_t cap = 0; cap <= 16; ++cap) {
        struct decoder d = {0}; packet(p, 4, 0, keys); memset(guarded, 0xa5, 32);
        size_t n = decode_packet(&d, p, 256, 1, 0, guarded + 4, cap);
        assert(n <= cap && n % 6 == 0);
        for (size_t i = 0; i < 4; ++i) assert(guarded[i] == 0xa5);
        for (size_t i = 4 + cap; i < 32; ++i) assert(guarded[i] == 0xa5);
    }
    const uint16_t bad[] = {0, 21, 246, 247, 255, 256, 65535};
    for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
        struct decoder d = {0}; packet(p, 0, 0, keys); le16(p + 6, bad[i]); seal_packet(p);
        assert(decode_packet(&d, p, 256, 1, 0, guarded, 32) == 0);
    }
}

#define FAKE_SPI 0x100000u
#define FAKE_ENABLE 0x200000u
#define FAKE_READY 0x300000u
struct fake {
    uint64_t now, asserted_at, deasserted_at, first_tx, last_clock;
    uint32_t regs[0x170 / 4], enable, ready;
    uint8_t incoming[256], rx_fifo[16];
    unsigned tx_level, rx_head, rx_level, cursor;
    unsigned reads, writes, assertions, releases, enables;
    uint32_t enable_values[8];
    int run, stall, invalid_fifo;
};
static uint32_t fake_read(void *cookie, uint64_t address)
{
    struct fake *f = cookie; ++f->reads; ++f->now;
    if (address == FAKE_ENABLE) return f->enable;
    if (address == FAKE_READY) return f->ready;
    assert(address >= FAKE_SPI && address < FAKE_SPI + sizeof(f->regs));
    unsigned off = (unsigned)(address - FAKE_SPI); assert((off & 3) == 0);
    if (off == SPI_FIFOSTAT) {
        if (f->invalid_fifo) return 17u << 24;
        if (f->run && !f->stall && f->tx_level && f->rx_level < 16 && f->cursor < 256) {
            --f->tx_level;
            f->rx_fifo[(f->rx_head + f->rx_level++) % 16] = f->incoming[f->cursor++];
            f->last_clock = f->now;
        }
        return (f->rx_level << 24) | (f->tx_level << 8);
    }
    if (off == SPI_RXDATA) {
        assert(f->rx_level > 0); --f->rx_level;
        uint8_t v = f->rx_fifo[f->rx_head]; f->rx_head = (f->rx_head + 1) % 16; return v;
    }
    return f->regs[off / 4];
}
static void fake_write(void *cookie, uint64_t address, uint32_t value)
{
    struct fake *f = cookie; ++f->writes; ++f->now;
    if (address == FAKE_ENABLE) {
        f->enable = value;
        if (f->enables < 8) f->enable_values[f->enables++] = value;
        return;
    }
    assert(address >= FAKE_SPI && address < FAKE_SPI + sizeof(f->regs));
    unsigned off = (unsigned)(address - FAKE_SPI); assert((off & 3) == 0);
    if (off == SPI_CTRL) {
        f->run = !!(value & SPI_RUN);
        if (value & SPI_RESET) f->tx_level = f->rx_level = f->rx_head = f->cursor = 0;
    }
    if (off == SPI_PIN && value == 0) {
        if (f->assertions) assert(f->now - f->deasserted_at >= 250);
        f->asserted_at = f->now; f->first_tx = 0; ++f->assertions;
    }
    if (off == SPI_PIN && value == SPI_CS_HIGH && f->regs[off / 4] == 0) {
        assert(f->now - f->asserted_at >= 200);
        if (f->last_clock >= f->asserted_at) assert(f->now - f->last_clock >= 100);
        f->deasserted_at = f->now; ++f->releases;
    }
    if (off == SPI_TXDATA) {
        assert(value == 0 && f->tx_level < 16);
        assert(f->now - f->asserted_at >= 100);
        if (!f->first_tx) f->first_tx = f->now;
        ++f->tx_level;
    }
    f->regs[off / 4] = value;
}
static uint64_t fake_now(void *cookie) { return ((struct fake *)cookie)->now++; }
static void fake_delay(void *cookie, uint32_t us) { ((struct fake *)cookie)->now += us; }
static struct spi_keyboard setup(struct fake *f, int active_low)
{
    memset(f, 0, sizeof(*f)); f->regs[SPI_PIN / 4] = SPI_CS_HIGH; f->enable = 0xa500;
    struct spi_keyboard k = {0};
    k.io = (struct io_ops){fake_read, fake_write, fake_now, fake_delay};
    k.cookie = f; k.spi = FAKE_SPI; k.enable = FAKE_ENABLE; k.enable_low = active_low;
    return k;
}
static void test_spi_setup_and_reset(void)
{
    for (int low = 0; low <= 1; ++low) {
        struct fake f; struct spi_keyboard k = setup(&f, low);
        assert(start_keyboard(&k, 120000000, 8000000));
        assert(k.active && f.enables == 3 && f.now >= 10000);
        assert(f.regs[SPI_CLKDIV / 4] == 15 && f.regs[SPI_CFG / 4] == 32);
        assert(f.regs[SPI_IE_FIFO / 4] == 0 && f.regs[SPI_IE_XFER / 4] == 0);
        assert((f.enable_values[0] & 1) == (uint32_t)(1 ^ low));
        assert((f.enable_values[1] & 1) == (uint32_t)low);
        assert((f.enable_values[2] & 1) == (uint32_t)(1 ^ low));
        assert((f.enable & 0x6e) == 2 && (f.enable & 0xff00) == 0xa500);
    }
    struct fake f; struct spi_keyboard k = setup(&f, 0);
    assert(!start_keyboard(&k, 0, 8000000) && f.writes == 0);
    assert(!start_keyboard(&k, 120000000, 0) && f.writes == 0);
    assert(!start_keyboard(&k, 120000000, 8000001) && f.writes == 0);
    assert(!start_keyboard(&k, 120000000, 1) && f.writes == 0);
}
static void test_spi_end_to_end(void)
{
    struct fake f; struct spi_keyboard k = setup(&f, 0); uint8_t out[128], keys[6] = {4};
    assert(start_keyboard(&k, 120000000, 8000000)); packet(f.incoming, 2, 0, keys);
    unsigned writes = f.writes;
    assert(poll_keyboard(&k, out, 128, 0) == 0 && f.writes == writes); /* boot delay */
    f.now = k.next_poll;
    assert(poll_keyboard(&k, out, 128, 0) == 1 && out[0] == 'A');
    assert(f.assertions == 1 && f.releases == 1 && !f.run && f.cursor == 256);
    assert(f.regs[SPI_TXCNT / 4] == 256 && f.regs[SPI_RXCNT / 4] == 256);
    assert(k.decoder.reports == 1 && f.regs[SPI_PIN / 4] == SPI_CS_HIGH);
    writes = f.writes;
    assert(poll_keyboard(&k, out, 128, 0) == 0 && f.writes == writes);
    f.now = k.next_poll;
    assert(poll_keyboard(&k, out, 128, 0) == 0 && k.decoder.reports == 2); /* held */
    memset(keys, 0, 6); packet(f.incoming, 0, 0, keys); f.now = k.next_poll;
    assert(poll_keyboard(&k, out, 128, 0) == 0 && k.decoder.repeat_key == 0);
}
static void test_spi_timeout_backoff_disable(void)
{
    struct fake f; struct spi_keyboard k = setup(&f, 0); uint8_t out[128];
    start_keyboard(&k, 120000000, 8000000); f.stall = 1;
    for (unsigned i = 1; i <= 3; ++i) {
        f.now = k.next_poll;
        uint64_t start = f.now;
        assert(poll_keyboard(&k, out, 128, 0) == (i == 3 ? -2 : -1));
        assert(f.now - start >= TRANSFER_US && f.now - start < TRANSFER_US + 1000);
        assert(f.regs[SPI_PIN / 4] == SPI_CS_HIGH && !f.run && k.errors == i);
        assert(f.assertions == f.releases && k.decoder.repeat_at == 0);
        unsigned writes = f.writes;
        assert(poll_keyboard(&k, out, 128, 0) == 0 && f.writes == writes);
    }
    assert(!k.active);
    /* Down, and staying down while the cool-off runs. */
    unsigned reads = f.reads;
    assert(poll_keyboard(&k, out, 128, 0) == 0 && f.reads == reads);
    /* Past it, brought back rather than left dead for the rest of the boot.
     * Nothing used to clear `active`, so three bad reads cost the machine its
     * keyboard and its touchpad together while the desktop carried on drawing
     * -- input simply stopped and never returned. */
    f.stall = 0;
    f.now += REVIVE_US + 1;
    assert(poll_keyboard(&k, out, 128, 0) == -3);
    assert(k.active && k.errors == 0 && k.revive_at == 0);
    /* And it works afterwards, rather than merely claiming to be up. */
    uint8_t keys[6] = {4};
    packet(f.incoming, 0, 0, keys);
    f.now = k.next_poll;
    assert(poll_keyboard(&k, out, 128, 0) == 1 && out[0] == 'a');
}
static void test_spi_invalid_fifo_and_recovery(void)
{
    struct fake f; struct spi_keyboard k = setup(&f, 0); uint8_t out[128], keys[6] = {4};
    start_keyboard(&k, 120000000, 8000000); f.invalid_fifo = 1; f.now = k.next_poll;
    assert(poll_keyboard(&k, out, 128, 0) == -1 && !f.run);
    f.invalid_fifo = 0; packet(f.incoming, 0, 0, keys); f.now = k.next_poll;
    assert(poll_keyboard(&k, out, 128, 0) == 1 && out[0] == 'a' && k.errors == 0);
}
static void test_ready_gpio_fallback_and_repeat(void)
{
    struct fake f; struct spi_keyboard k = setup(&f, 0); uint8_t out[128], keys[6] = {4};
    k.ready = FAKE_READY; k.ready_low = 1;
    start_keyboard(&k, 120000000, 8000000); f.ready = 0;
    packet(f.incoming, 0, 0, keys); f.now = k.next_poll;
    assert(poll_keyboard(&k, out, 128, 0) == 1);
    f.ready = 1; f.now = k.next_poll; unsigned assertions = f.assertions;
    assert(poll_keyboard(&k, out, 128, 0) == 0 && f.assertions == assertions);
    f.now = k.last_transfer + FALLBACK_US;
    assert(poll_keyboard(&k, out, 128, 0) == 0 && f.assertions == assertions + 1);
    f.now = k.decoder.repeat_at;
    assert(poll_keyboard(&k, out, 128, 0) == 1 && out[0] == 'a');
}
static uint32_t random_state = 0x75c29631;
static uint32_t random32(void)
{
    random_state ^= random_state << 13; random_state ^= random_state >> 17;
    random_state ^= random_state << 5; return random_state;
}
static void test_seeded_mutation_fuzz(void)
{
    struct decoder d = {0}; uint8_t p[320], out[128], keys[6];
    for (unsigned i = 0; i < 100000; ++i) {
        for (unsigned j = 0; j < 6; ++j) keys[j] = (uint8_t)random32();
        packet(p, (uint8_t)random32(), (uint8_t)random32(), keys);
        unsigned mutations = random32() % 8;
        while (mutations--) p[random32() % 256] ^= (uint8_t)random32();
        if (i & 1) seal_packet(p);
        size_t length = i % 4 ? 256 : random32() % sizeof(p);
        size_t capacity = random32() % sizeof(out);
        size_t n = decode_packet(&d, p, length, (uint64_t)i * 4000, i & 1, out, capacity);
        assert(n <= capacity && d.message_used <= MESSAGE_SIZE);
        n = repeat_key(&d, (uint64_t)i * 4000, i & 1, out, capacity);
        assert(n <= capacity);
    }
}
static void run(void (*test)(void), const char *name)
{
    test(); ++tests; printf("ok %u - %s\n", tests, name);
}
int main(void)
{
    run(test_crc, "CRC-16 known answer and framing");
    run(test_press_release_duplicate, "press, release, duplicate reports");
    run(test_six_keys_reordering, "six keys, slot reorder, duplicate usages");
    run(test_modifiers_and_caps, "independent modifiers and Caps Lock");
    run(test_ascii_controls, "ASCII, control bytes, Option, NUL");
    run(test_navigation_fn_and_function_keys, "navigation, DECCKM, Fn, function keys");
    run(test_command_tab, "Cmd-Tab chords and the release that ends them");
    run(test_repeat, "repeat timing, modifiers, no catch-up burst");
    run(test_rollover, "rollover errors and recovery");
    run(test_crc_and_identity_rejection, "packet/message CRC and identity rejection");
    run(test_fragmentation, "all fragment splits, order and expiry");
    run(test_lengths_and_output_bounds, "length and output capacity bounds");
    run(test_spi_setup_and_reset, "SPI setup, divider and reset polarity");
    run(test_spi_end_to_end, "mock-MMIO SPI to console bytes");
    run(test_spi_timeout_backoff_disable, "bounded timeout, CS cleanup, backoff, disable");
    run(test_spi_invalid_fifo_and_recovery, "invalid FIFO count and recovery");
    run(test_ready_gpio_fallback_and_repeat, "ready GPIO, fallback polling and repeat");
    run(test_seeded_mutation_fuzz, "100000 deterministic mutated packets");
    printf("PASS: %u test groups\n", tests);
    return 0;
}
