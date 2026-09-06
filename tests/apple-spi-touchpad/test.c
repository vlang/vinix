/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define VINIX_APPLE_SPI_TEST
#include "../../kernel/c/apple_spi_keyboard.c"

static unsigned groups;
static void seal(uint8_t p[256]) { tp_put16(p + 254, tp_crc(p, 254)); }
static void seal_message(uint8_t *m, size_t n) { tp_put16(m + n - 2, tp_crc(m, n - 2)); }
static size_t make_message(uint8_t *m, unsigned slots, unsigned fingers, unsigned buttons)
{
    size_t n = 10 + TP_REPORT_HEADER + slots * TP_FINGER_SIZE;
    assert(n <= TP_MESSAGE_MAX);
    memset(m, 0, n);
    m[0] = 0x10; m[1] = 2;
    tp_put16(m + 6, (uint16_t)(n - 10));
    m[8] = 2; m[8 + 30] = (uint8_t)fingers; m[8 + 31] = (uint8_t)buttons;
    seal_message(m, n);
    return n;
}
static void set_finger(uint8_t *m, unsigned i, int x, int y, int major)
{
    uint8_t *f = m + 8 + TP_REPORT_HEADER + i * TP_FINGER_SIZE;
    tp_put16(f + 4, (uint16_t)x); tp_put16(f + 6, (uint16_t)y);
    tp_put16(f + 18, (uint16_t)major);
    seal_message(m, (size_t)tp_le16(m + 6) + 10);
}
static void make_fragment(uint8_t p[256], const uint8_t *m, size_t total,
    size_t offset, size_t n)
{
    assert(offset + n <= total && n <= 246);
    memset(p, 0, 256); p[0] = 0x20; p[1] = 2;
    tp_put16(p + 2, (uint16_t)offset);
    tp_put16(p + 4, (uint16_t)(total - offset - n));
    tp_put16(p + 6, (uint16_t)n);
    memcpy(p + 8, m + offset, n); seal(p);
}
static void feed_message(struct touchpad *t, const uint8_t *m, size_t n, uint64_t now)
{
    uint8_t p[256];
    for (size_t offset = 0; offset < n;) {
        size_t count = n - offset > 246 ? 246 : n - offset;
        make_fragment(p, m, n, offset, count);
        tp_decode(t, p, 256, now++); offset += count;
    }
}
static void finger(struct touchpad *t, int x, int y, unsigned button, uint64_t now)
{
    uint8_t m[TP_MESSAGE_MAX]; size_t n = make_message(m, 1, 1, button);
    set_finger(m, 0, x, y, 30); feed_message(t, m, n, now);
}
static void lift(struct touchpad *t, uint64_t now)
{
    uint8_t m[TP_MESSAGE_MAX]; size_t n = make_message(m, 0, 0, 0);
    feed_message(t, m, n, now);
}
static void keyboard_packet(uint8_t p[256], uint8_t key)
{
    uint8_t m[20] = {0x10, 1, 0, 0, 0, 0, 10, 0, 1, 0, 0};
    m[11] = key; seal_message(m, 20);
    make_fragment(p, m, 20, 0, 20); p[1] = 1; seal(p);
}

static void test_mode_wire_packet(void)
{
    static const uint8_t prefix[] = {0x40,2,0,0,0,0,12,0,0x52,2,0,0,2,0,2,0,2,1,0x7b,0x11};
    struct touchpad t; tp_init(&t, 100); uint8_t p[256];
    assert(tp_crc((const uint8_t *)"123456789", 9) == 0xbb3d);
    tp_mode_packet(&t, p, 1000);
    assert(!memcmp(p, prefix, sizeof(prefix)) && p[254] == 0x23 && p[255] == 0xab);
    for (size_t i = sizeof(prefix); i < 254; ++i) assert(p[i] == 0);
    assert(tp_crc(p, 256) == 0 && tp_crc(p + 8, 12) == 0);
    assert(t.mode_attempts == 1 && t.next_id == 1 && !t.mode_enabled);
    t.next_id = 255; tp_mode_packet(&t, p, 2000);
    assert(p[11] == 255 && t.next_id == 0 && tp_crc(p, 256) == 0);
}
static void test_relative_native_motion(void)
{
    struct touchpad t; tp_init(&t, 0);
    int x = t.x, y = t.y;
    finger(&t, -300, 1000, 0, 100);
    assert(t.x == x && t.y == y && t.tracking && t.mode_enabled);
    finger(&t, -290, 1020, 0, 200);
    assert(t.x == x + 80 && t.y == y - 160);
    uint8_t m[TP_MESSAGE_MAX]; size_t n = make_message(m, 1, 1, 0);
    set_finger(m, 0, -290, 1020, 30);
    m[8 + 2] = 127; m[8 + 3] = 128; seal_message(m, n);
    feed_message(&t, m, n, 300);
    assert(t.x == x + 80 && t.y == y - 160); /* no duplicate prefix movement */
}
static void test_lifts_stale_and_jumps(void)
{
    struct touchpad t; tp_init(&t, 0); finger(&t, 100, 100, 0, 1);
    int x = t.x, y = t.y;
    lift(&t, 2); finger(&t, -5000, 6000, 0, 3);
    assert(t.x == x && t.y == y);
    finger(&t, -4990, 6000, 0, 4); assert(t.x == x + 80);
    finger(&t, 6000, 100, 0, 5); assert(t.x == x + 80);
    finger(&t, 6001, 100, 0, 6); assert(t.x == x + 88);
    finger(&t, 6020, 100, 0, 6 + TP_REBASE_US); assert(t.x == x + 88);
    finger(&t, 6021, 100, 0, 7 + TP_REBASE_US); assert(t.x == x + 96);
}
static void test_contacts_and_padding(void)
{
    struct touchpad t; tp_init(&t, 0); finger(&t, 0, 0, 0, 1);
    int x = t.x;
    uint8_t m[TP_MESSAGE_MAX]; size_t n = make_message(m, 2, 2, 0);
    set_finger(m, 0, 100, 0, 20); set_finger(m, 1, 800, 0, 20);
    feed_message(&t, m, n, 2); assert(!t.tracking && t.x == x);
    finger(&t, 800, 0, 0, 3); assert(t.x == x);
    finger(&t, 801, 0, 0, 4); assert(t.x == x + 8);
    /* A zero-area record is not an active finger; advertised slots can be padded. */
    n = make_message(m, 3, 2, 0);
    set_finger(m, 0, 2000, 0, 0); set_finger(m, 1, 802, 0, 20);
    feed_message(&t, m, n, 5); assert(t.x == x + 16 && t.tracking);
    set_finger(m, 1, 900, 0, 0); feed_message(&t, m, n, 6);
    assert(!t.tracking && t.x == x + 16);
}
static void test_buttons_and_snapshot(void)
{
    struct touchpad t; tp_init(&t, 0); int32_t p[10];
    for (unsigned i = 0; i < 10; ++i) p[i] = 0x12345678;
    assert(!tp_snapshot(&t, p + 1));
    finger(&t, 0, 0, 1, 1); finger(&t, 0, 0, 0, 2);
    assert(tp_snapshot(&t, p + 1));
    assert(p[0] == 0x12345678 && p[9] == 0x12345678);
    assert(p[5] == 0 && p[6] == 1 && p[7] == 1 && p[8] == 0);
    assert(tp_snapshot(&t, p + 1) && p[6] == 0 && p[7] == 0);
    finger(&t, 0, 0, 1, 3); tp_snapshot(&t, p + 1);
    tp_tick(&t, 99999999); /* Quiet stationary click must not be released. */
    assert(t.buttons == 1);
    tp_discontinuity(&t); assert(tp_snapshot(&t, p + 1));
    assert(p[5] == 0 && p[7] == 1 && t.present);
    assert(!tp_snapshot(&t, NULL));
}
static void test_boot_mouse_and_clamping(void)
{
    struct touchpad t; tp_init(&t, 0);
    uint8_t r[8] = {2, 7, 0x80, 0x7f};
    int x = t.x, y = t.y;
    assert(tp_report(&t, r, sizeof(r), 1));
    assert(t.x == x - 128 * TP_BOOT_GAIN && t.y == y + 127 * TP_BOOT_GAIN);
    assert(t.buttons == 7 && !t.mode_enabled && !t.tracking);
    t.x = 1; t.y = TP_MAX_Y - 1;
    assert(tp_report(&t, r, sizeof(r), 2) && t.x == 0 && t.y == TP_MAX_Y);
    finger(&t, -32768, -32768, 0, 3);
    finger(&t, -32767, -32767, 0, 4);
    assert(t.x == TP_GAIN && t.y == TP_MAX_Y - TP_GAIN);
    finger(&t, 32767, 32767, 0, 5);
    assert(t.x == TP_GAIN && t.y == TP_MAX_Y - TP_GAIN); /* rebase, no overflow */
    t.x = TP_MAX_X - 1; t.y = 1;
    finger(&t, 32766, 32766, 0, 6);
    assert(t.x == TP_MAX_X - 1 - TP_GAIN && t.y == 1 + TP_GAIN);
}
static void test_all_fragment_splits(void)
{
    uint8_t m[TP_MESSAGE_MAX], p[256], k[256], out[128];
    size_t n = make_message(m, 1, 1, 1); set_finger(m, 0, 200, 300, 40);
    for (size_t split = 1; split < n; ++split) {
        struct touchpad t; tp_init(&t, 0); struct decoder d = {0};
        make_fragment(p, m, n, 0, split); tp_decode(&t, p, 256, 1);
        assert(!t.present && t.used == split);
        keyboard_packet(k, 4);
        tp_decode(&t, k, 256, 2);
        assert(decode_packet(&d, k, 256, 2, 0, out, 128) == 1 && out[0] == 'a');
        k[0] = 0x40; k[1] = 2; seal(k); tp_decode(&t, k, 256, 3);
        assert(t.used == split);
        make_fragment(p, m, n, split, n - split); tp_decode(&t, p, 256, 4);
        assert(t.present && t.buttons == 1 && t.used == 0 && t.reports == 1);
    }
}
static void test_max_contacts_three_packets(void)
{
    struct touchpad t; tp_init(&t, 0); uint8_t m[TP_MESSAGE_MAX];
    size_t n = make_message(m, 16, 16, 1); assert(n == 536);
    for (unsigned i = 0; i < 16; ++i) set_finger(m, i, (int)i * 100, 200, 10);
    feed_message(&t, m, n, 1);
    assert(t.native_reports == 1 && !t.tracking && t.buttons == 1 && t.used == 0);
}
static void test_fragment_order_total_timeout(void)
{
    uint8_t m[TP_MESSAGE_MAX], p[256]; size_t n = make_message(m, 1, 1, 0);
    struct touchpad t; tp_init(&t, 0);
    make_fragment(p, m, n, 10, n - 10); tp_decode(&t, p, 256, 1); assert(!t.used);
    make_fragment(p, m, n, 0, 10); tp_decode(&t, p, 256, 2);
    make_fragment(p, m, n, 11, n - 11); tp_decode(&t, p, 256, 3); assert(!t.used);
    make_fragment(p, m, n, 0, 10); tp_decode(&t, p, 256, 4);
    make_fragment(p, m, n, 10, n - 10); tp_put16(p + 4, 1); seal(p);
    tp_decode(&t, p, 256, 5); assert(!t.used && !t.present);
    make_fragment(p, m, n, 0, 10); tp_decode(&t, p, 256, 6);
    make_fragment(p, m, n, 10, n - 10); tp_decode(&t, p, 256, 6 + TP_FRAGMENT_US);
    assert(!t.used && !t.present);
    make_fragment(p, m, n, 0, 10); tp_decode(&t, p, 256, 200000);
    tp_tick(&t, 200000 + TP_FRAGMENT_US); assert(!t.used);
    feed_message(&t, m, n, 400000); assert(t.present && t.reports == 1);
}
static void test_bad_crc_lengths_and_identity(void)
{
    uint8_t m[TP_MESSAGE_MAX], p[256]; size_t n = make_message(m, 1, 1, 0);
    const unsigned bad[] = {0, 247, 255, 256, 65535};
    for (unsigned field = 2; field <= 6; field += 2) {
        for (unsigned i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
            if (field != 6 && bad[i] == 0) continue;
            struct touchpad t; tp_init(&t, 0);
            make_fragment(p, m, n, 0, n); tp_put16(p + field, (uint16_t)bad[i]); seal(p);
            tp_decode(&t, p, 256, 1); assert(!t.present);
        }
    }
    for (size_t size = 0; size < 256; ++size) {
        struct touchpad t; tp_init(&t, 0); make_fragment(p, m, n, 0, n);
        tp_decode(&t, p, size, 1); assert(!t.present);
    }
    for (unsigned field = 0; field < 7; ++field) {
        struct touchpad t; tp_init(&t, 0); n = make_message(m, 1, 1, 0);
        if (field == 0) m[0] = 0x52;
        if (field == 1) m[1] = 1;
        if (field == 2) m[2] = 1;
        if (field == 3) m[8] = 1;
        if (field == 4) m[8 + 30] = 2;
        if (field == 5) tp_put16(m + 6, (uint16_t)(n - 11));
        seal_message(m, n);
        if (field == 6) m[n - 1] ^= 0x80; /* good outer, bad inner CRC */
        feed_message(&t, m, n, 1); assert(!t.present);
    }
    struct touchpad t; tp_init(&t, 0); n = make_message(m, 1, 1, 0);
    make_fragment(p, m, n, 0, n); p[254] ^= 1; tp_decode(&t, p, 256, 1);
    assert(!t.present);
    make_fragment(p, m, n, 0, n); p[0] = 0x40; seal(p); tp_decode(&t, p, 256, 2);
    assert(!t.present);
    /* A malformed non-integral finger record length is not a valid report. */
    tp_put16(m + 6, (uint16_t)(n - 11)); seal_message(m, n - 1);
    feed_message(&t, m, n - 1, 3); assert(!t.present);
}
static void test_reset_and_retry_state(void)
{
    struct touchpad t; tp_init(&t, 0); uint8_t p[256], m[11] = {0x10,2,0,0,0,0,1,0,0x60};
    assert(!tp_mode_due(&t, 9999999)); t.requested = 1;
    assert(!tp_mode_due(&t, 19999) && tp_mode_due(&t, 20000));
    for (unsigned i = 0; i < 3; ++i) {
        uint64_t now = t.mode_at; assert(tp_mode_due(&t, now));
        tp_mode_packet(&t, p, now); assert(!tp_mode_due(&t, now + 1));
    }
    assert(!tp_mode_due(&t, t.mode_at + TP_RETRY_US));
    finger(&t, 0, 0, 1, 5000000); assert(t.mode_enabled);
    seal_message(m, sizeof(m)); feed_message(&t, m, sizeof(m), 6000000);
    assert(t.buttons == 0 && t.released == 1 && !t.mode_enabled && t.mode_attempts == 0);
    assert(t.requested && tp_mode_due(&t, 6010000));
}

#define BASE 0x100000u
#define ENABLE 0x200000u
struct mock {
    uint32_t regs[0x170 / 4], enable;
    uint64_t now, asserted, deasserted, last_clock;
    uint8_t incoming[256], status[4], fifo[16];
    uint8_t sent[32][256];
    size_t lengths[32], sent_n[32];
    unsigned tx_level, rx_level, rx_head, cursor, stages, cs_down, cs_up, reads;
    int selected, run, stall_length, invalid_fifo, frozen;
};
static uint32_t mock_read(void *cookie, uint64_t addr)
{
    struct mock *m = cookie; ++m->reads; if (!m->frozen) ++m->now;
    if (addr == ENABLE) return m->enable;
    assert(addr >= BASE && addr < BASE + sizeof(m->regs) && !(addr & 3));
    unsigned off = (unsigned)(addr - BASE);
    if (off == SPI_FIFOSTAT) {
        if (m->invalid_fifo) return m->invalid_fifo == 1 ? 17u << 24 : 17u << 8;
        size_t length = m->regs[SPI_TXCNT / 4];
        if (m->run && m->stall_length != (int)length && m->tx_level &&
            m->rx_level < 16 && m->cursor < length) {
            --m->tx_level;
            const uint8_t *source = length == 4 ? m->status : m->incoming;
            m->fifo[(m->rx_head + m->rx_level++) % 16] = source[m->cursor++];
            m->last_clock = m->now;
        }
        return (m->rx_level << 24) | (m->tx_level << 8);
    }
    if (off == SPI_RXDATA) {
        assert(m->rx_level); --m->rx_level;
        uint8_t value = m->fifo[m->rx_head]; m->rx_head = (m->rx_head + 1) % 16;
        return value;
    }
    return m->regs[off / 4];
}
static void mock_write(void *cookie, uint64_t addr, uint32_t value)
{
    struct mock *m = cookie; if (!m->frozen) ++m->now;
    if (addr == ENABLE) { m->enable = value; return; }
    assert(addr >= BASE && addr < BASE + sizeof(m->regs) && !(addr & 3));
    unsigned off = (unsigned)(addr - BASE);
    if (off == SPI_PIN && value == 0) {
        assert(!m->selected);
        if (m->cs_down && !m->frozen) assert(m->now - m->deasserted >= 250);
        m->selected = 1; ++m->cs_down; m->asserted = m->now;
    }
    if (off == SPI_PIN && value == SPI_CS_HIGH && m->selected) {
        if (!m->frozen) assert(m->now - m->last_clock >= 100);
        m->selected = 0; ++m->cs_up; m->deasserted = m->now;
    }
    if (off == SPI_CTRL) {
        m->run = !!(value & SPI_RUN);
        if (value & SPI_RESET) m->tx_level = m->rx_level = m->rx_head = m->cursor = 0;
    }
    if (off == SPI_TXCNT) {
        assert(m->selected && m->stages < 32);
        if (value == 4 && !m->frozen) assert(m->now - m->last_clock >= 200);
        m->lengths[m->stages++] = value;
    }
    if (off == SPI_TXDATA) {
        assert(m->selected && m->tx_level < 16 && m->stages);
        if (!m->frozen) assert(m->now - m->asserted >= 100);
        size_t *used = &m->sent_n[m->stages - 1];
        assert(*used < m->lengths[m->stages - 1] && value <= 255);
        m->sent[m->stages - 1][(*used)++] = (uint8_t)value;
        ++m->tx_level;
    }
    m->regs[off / 4] = value;
}
static uint64_t mock_now(void *cookie)
{
    struct mock *m = cookie; if (!m->frozen) ++m->now; return m->now;
}
static void mock_delay(void *cookie, uint32_t us) { ((struct mock *)cookie)->now += us; }
static struct spi_keyboard setup(struct mock *m)
{
    memset(m, 0, sizeof(*m)); m->regs[SPI_PIN / 4] = SPI_CS_HIGH;
    m->status[0] = 0xac; m->status[1] = 0x27; m->status[2] = 0x68; m->status[3] = 0xd5;
    struct spi_keyboard k = {0};
    k.io = (struct io_ops){mock_read, mock_write, mock_now, mock_delay};
    k.cookie = m; k.spi = BASE; k.enable = ENABLE;
    assert(start_keyboard(&k, 120000000, 8000000));
    k.touchpad.requested = 1;
    return k;
}
static int poll_next(struct spi_keyboard *k, uint8_t *out)
{
    struct mock *m = k->cookie;
    if (m->now < k->next_poll) m->now = k->next_poll;
    if (m->now < k->next_transfer) m->now = k->next_transfer;
    return poll_keyboard(k, out, 128, 0);
}
static void test_spi_write_status_cs(void)
{
    struct mock m; struct spi_keyboard k = setup(&m); uint8_t out[128];
    m.now = k.touchpad.mode_at;
    assert(poll_next(&k, out) == 0 && k.active && k.errors == 0);
    assert(m.stages == 2 && m.lengths[0] == 256 && m.lengths[1] == 4);
    assert(m.sent_n[0] == 256 && m.sent_n[1] == 4);
    assert(m.cs_down == 1 && m.cs_up == 1 && !m.selected && !m.run);
    assert(m.sent[0][0] == 0x40 && m.sent[0][1] == 2 && tp_crc(m.sent[0], 256) == 0);
    assert(k.touchpad.mode_errors == 0 && !k.touchpad.mode_enabled);
    for (unsigned i = 0; i < 4; ++i) assert(m.sent[1][i] == 0);
}
static void test_spi_write_failures(void)
{
    for (int stage = 0; stage < 3; ++stage) {
        struct mock m; struct spi_keyboard k = setup(&m); uint8_t out[128];
        if (stage == 0) m.status[0] ^= 1;
        if (stage == 1) m.stall_length = 256;
        if (stage == 2) m.stall_length = 4;
        m.now = k.touchpad.mode_at; uint64_t start = m.now;
        assert(poll_next(&k, out) == 0);
        assert(m.now - start < 2 * TRANSFER_US + 2000);
        assert(k.active && !k.errors && k.touchpad.mode_errors == 1);
        assert(!m.run && !m.selected && m.cs_down == m.cs_up);
        assert(m.stages == (stage == 1 ? 1u : 2u));
        m.stall_length = 0; keyboard_packet(m.incoming, 4);
        assert(poll_next(&k, out) == 1 && out[0] == 'a');
    }
}
static void test_spi_bad_fifo_and_frozen_clock(void)
{
    for (int invalid = 1; invalid <= 2; ++invalid) {
        struct mock m; struct spi_keyboard k = setup(&m); uint8_t out[128];
        m.invalid_fifo = invalid; m.now = k.touchpad.mode_at;
        assert(poll_next(&k, out) == 0 && k.touchpad.mode_errors == 1);
        assert(!m.selected && !m.run && k.active);
    }
    struct mock m; struct spi_keyboard k = setup(&m); uint8_t out[128];
    m.now = k.touchpad.mode_at; m.frozen = 1; m.stall_length = 256;
    assert(poll_next(&k, out) == 0 && k.touchpad.mode_errors == 1);
    assert(m.reads < 250000 && !m.selected && !m.run);
}
static void test_shared_poll_to_pointer(void)
{
    struct mock m; struct spi_keyboard k = setup(&m); uint8_t out[128], msg[TP_MESSAGE_MAX];
    keyboard_packet(m.incoming, 4);
    assert(poll_next(&k, out) == 1 && out[0] == 'a');
    size_t n = make_message(msg, 1, 1, 1); set_finger(msg, 0, 100, 300, 30);
    make_fragment(m.incoming, msg, n, 0, n);
    assert(poll_next(&k, out) == 0 && k.touchpad.native_reports == 1);
    set_finger(msg, 0, 110, 320, 30); make_fragment(m.incoming, msg, n, 0, n);
    assert(poll_next(&k, out) == 0);
    int32_t p[8]; assert(tp_snapshot(&k.touchpad, p));
    assert(p[0] == (TP_MAX_X + 1) / 2 + 80 && p[1] == (TP_MAX_Y + 1) / 2 - 160);
    assert(p[4] == 1 && p[5] == 1 && k.decoder.reports == 1 && has_key(k.decoder.keys, 4));
    keyboard_packet(m.incoming, 0); assert(poll_next(&k, out) == 0);
    assert(!k.decoder.repeat_key);
}
static void test_feature_waits_for_fragments(void)
{
    struct mock m; struct spi_keyboard k = setup(&m); uint8_t out[128], msg[TP_MESSAGE_MAX];
    size_t n = make_message(msg, 1, 1, 0);
    k.touchpad.fragment_at = k.touchpad.mode_at;
    k.touchpad.used = 10; k.touchpad.total = n;
    memcpy(k.touchpad.message, msg, 10);
    make_fragment(m.incoming, msg, n, 10, n - 10); m.now = k.touchpad.mode_at;
    assert(poll_next(&k, out) == 0 && k.touchpad.reports == 1);
    assert(m.sent[0][0] == 0 && k.touchpad.mode_attempts == 0);
    /* Likewise for an incomplete keyboard report: a release is not stolen. */
    k.touchpad.mode_enabled = 0; k.touchpad.mode_at = m.now;
    keyboard_packet(m.incoming, 4);
    memcpy(k.decoder.message, m.incoming + 8, 10);
    k.decoder.message_used = 10; k.decoder.fragment_at = m.now;
    uint8_t key_msg[20]; memcpy(key_msg, m.incoming + 8, 20);
    make_fragment(m.incoming, key_msg, 20, 10, 10); m.incoming[1] = 1; seal(m.incoming);
    assert(poll_next(&k, out) == 1 && out[0] == 'a');
    assert(k.touchpad.mode_attempts == 0);
}
static void test_disable_preserves_release(void)
{
    struct mock m; struct spi_keyboard k = setup(&m); uint8_t out[128];
    finger(&k.touchpad, 0, 0, 1, 1); int32_t p[8]; tp_snapshot(&k.touchpad, p);
    m.stall_length = 256;
    for (unsigned i = 1; i <= 3; ++i)
        assert(poll_next(&k, out) == (i == 3 ? -2 : -1));
    assert(!k.active && tp_snapshot(&k.touchpad, p) && p[4] == 0 && p[6] == 1);
    assert(tp_snapshot(&k.touchpad, p) && p[6] == 0);
}
static void test_boot_notification_dispatch(void)
{
    struct mock m; struct spi_keyboard k = setup(&m); uint8_t out[128];
    finger(&k.touchpad, 0, 0, 1, 1);
    keyboard_packet(m.incoming, 4); assert(poll_next(&k, out) == 1);
    memset(m.incoming, 0, 256); m.incoming[0] = 0x20;
    m.incoming[6] = 4; m.incoming[8] = 0xa0; m.incoming[9] = 0x80; seal(m.incoming);
    assert(poll_next(&k, out) == 0);
    assert(k.touchpad.resets == 1 && !k.touchpad.buttons && !k.decoder.repeat_key);
    assert(!k.touchpad.mode_enabled && k.touchpad.requested);
}
static uint32_t rng = 0x124873ab;
static uint32_t random32(void) { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng; }
static void test_mutation_fuzz(void)
{
    struct touchpad t; tp_init(&t, 0); uint8_t m[TP_MESSAGE_MAX], p[256];
    for (unsigned i = 0; i < 100000; ++i) {
        unsigned slots = random32() % 17;
        size_t n = make_message(m, slots, slots, random32() & 1);
        for (unsigned j = 0; j < slots; ++j)
            set_finger(m, j, (int)(random32() & 0xffff) - 32768,
                (int)(random32() & 0xffff) - 32768, (int)(random32() & 0x7fff));
        unsigned edits = random32() % 5;
        while (edits--) m[random32() % n] ^= (uint8_t)random32();
        if (i & 1) seal_message(m, n);
        for (size_t off = 0; off < n;) {
            size_t len = n - off > 246 ? 246 : n - off;
            make_fragment(p, m, n, off, len);
            unsigned changes = random32() % 4;
            while (changes--) p[random32() % 256] ^= (uint8_t)random32();
            if (i & 2) seal(p);
            size_t size = i % 7 ? 256 : random32() % 256;
            tp_decode(&t, p, size, (uint64_t)i * 4000);
            assert(t.used <= TP_MESSAGE_MAX && t.total <= TP_MESSAGE_MAX);
            assert(t.x >= 0 && t.x <= TP_MAX_X && t.y >= 0 && t.y <= TP_MAX_Y);
            assert(t.buttons <= 7 && t.pressed <= 7 && t.released <= 7);
            off += len;
        }
        tp_tick(&t, (uint64_t)i * 4000);
        int32_t state[8]; tp_snapshot(&t, state);
    }
}
static void run(void (*test)(void), const char *name)
{
    test(); printf("ok %u - %s\n", ++groups, name);
}
int main(void)
{
    run(test_mode_wire_packet, "golden mode command, both CRCs, sequence wrap");
    run(test_relative_native_motion, "signed native coordinates, relative motion, inverted Y");
    run(test_lifts_stale_and_jumps, "lift, stale frame and jump rebasing");
    run(test_contacts_and_padding, "multiple contacts, zero area and padded slots");
    run(test_buttons_and_snapshot, "click edges, stationary hold, release and snapshot bounds");
    run(test_boot_mouse_and_clamping, "boot mouse fallback, signed extremes and clamping");
    run(test_all_fragment_splits, "all 85 splits with keyboard and write-response interleaving");
    run(test_max_contacts_three_packets, "16 contacts reassembled across three SPI packets");
    run(test_fragment_order_total_timeout, "fragment order, total consistency and expiry");
    run(test_bad_crc_lengths_and_identity, "malformed lengths, CRCs and report identities");
    run(test_reset_and_retry_state, "opt-in mode request, bounded retries and reset recovery");
    run(test_spi_write_status_cs, "PIO command plus four-byte status with continuous CS");
    run(test_spi_write_failures, "bad status and write/status timeouts preserve keyboard");
    run(test_spi_bad_fifo_and_frozen_clock, "invalid FIFO counts and stalled counter are bounded");
    run(test_shared_poll_to_pointer, "shared SPI poll to keyboard and pointer snapshots");
    run(test_feature_waits_for_fragments, "mode writes do not interrupt either device's fragments");
    run(test_disable_preserves_release, "transport disable preserves final button release");
    run(test_boot_notification_dispatch, "boot notification resets both input paths");
    run(test_mutation_fuzz, "100000 deterministic mutated touchpad messages");
    printf("PASS: %u touchpad test groups\n", groups);
    return 0;
}
