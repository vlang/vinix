/* SPDX-License-Identifier: GPL-2.0-or-later
 * Apple SPI touchpad protocol and relative-pointer decoder.
 *
 * Protocol references: Asahi Linux spi-hid-apple-core.c (The Asahi Linux
 * Contributors) and hid-magicmouse.c (Michael Poole, Chase Douglas and
 * contributors). This is a bounded, allocation-free implementation, not a
 * Linux input-layer port. See docs/apple-spi-touchpad.md for references.
 *
 * Internal to apple_spi_keyboard.c: one owner, one lock, one SPI controller.
 * Kept here so the existing keyboard host tests exercise the complete driver
 * without extra link dependencies. No packed structs or unaligned loads.
 */
#ifndef VINIX_APPLE_SPI_TOUCHPAD_INTERNAL_H
#define VINIX_APPLE_SPI_TOUCHPAD_INTERNAL_H

#include <stddef.h>
#include <stdint.h>

#define TP_PACKET_SIZE 256u
#define TP_PACKET_DATA 246u
#define TP_REPORT_HEADER 46u /* 8-byte mouse prefix + 38-byte vendor header */
#define TP_FINGER_SIZE 30u
#define TP_MAX_FINGERS 16u
#define TP_MESSAGE_MAX (10u + TP_REPORT_HEADER + TP_FINGER_SIZE * TP_MAX_FINGERS)
#define TP_FRAGMENT_US 100000u
#define TP_REBASE_US 100000u
#define TP_RETRY_US 1000000u
#define TP_MODE_ATTEMPTS 3u
/* Logical 16:10 pointer space, NOT a claim about sensor dimensions. The
 * desktop scales this range to its framebuffer. Integer subpixel positions
 * retain slow motion between frames without floating point. */
#define TP_MAX_X 65535
#define TP_MAX_Y 40959
#define TP_GAIN 8
#define TP_BOOT_GAIN 32
#define TP_MAX_STEP 2048

struct touchpad {
    uint8_t message[TP_MESSAGE_MAX];
    size_t used;
    size_t total;
    uint64_t fragment_at;
    uint64_t report_at;
    uint64_t mode_at;
    uint64_t reports;
    uint64_t native_reports;
    uint64_t bad_packets;
    uint64_t resets;
    unsigned mode_attempts;
    unsigned mode_errors;
    uint8_t next_id;
    int requested;
    int mode_enabled;
    int present;
    int tracking;
    int previous_x;
    int previous_y;
    int x;
    int y;
    uint32_t buttons;
    uint32_t pressed;
    uint32_t released;
};

static uint16_t tp_le16(const uint8_t *p)
{
    return (uint16_t)((uint16_t)p[0] | (uint16_t)((uint16_t)p[1] << 8));
}

static int tp_s16(const uint8_t *p)
{
    unsigned n = tp_le16(p);
    return n < 0x8000u ? (int)n : (int)n - 0x10000;
}

static int tp_s8(uint8_t n)
{
    return n < 0x80u ? (int)n : (int)n - 0x100;
}

static void tp_put16(uint8_t *p, uint16_t n)
{
    p[0] = (uint8_t)n;
    p[1] = (uint8_t)(n >> 8);
}

static uint16_t tp_crc(const uint8_t *p, size_t n)
{
    uint16_t crc = 0;
    while (n--) {
        crc ^= *p++;
        for (unsigned b = 0; b < 8; ++b)
            crc = (uint16_t)((crc >> 1) ^ ((crc & 1u) ? 0xa001u : 0));
    }
    return crc;
}

static void tp_buttons(struct touchpad *t, uint32_t buttons)
{
    buttons &= 7u;
    t->pressed |= buttons & ~t->buttons;
    t->released |= t->buttons & ~buttons;
    t->buttons = buttons;
}

/* On a known discontinuity, discard the motion baseline and release buttons.
 * Keep position and accumulated edges, including a release owed to userspace.
 * Do not release a stationary held click merely because the device is quiet. */
static void tp_discontinuity(struct touchpad *t)
{
    t->used = 0;
    t->total = 0;
    t->tracking = 0;
    tp_buttons(t, 0);
}

static void tp_bad(struct touchpad *t)
{
    ++t->bad_packets;
    tp_discontinuity(t);
}

static void tp_restart(struct touchpad *t, uint64_t now)
{
    tp_discontinuity(t);
    t->mode_enabled = 0;
    t->mode_attempts = 0;
    t->mode_at = now + 10000u;
    ++t->resets;
}

static void tp_init(struct touchpad *t, uint64_t first_poll)
{
    *t = (struct touchpad){0};
    t->x = (TP_MAX_X + 1) / 2;
    t->y = (TP_MAX_Y + 1) / 2;
    /* First drain the boot notification instead of writing during startup. */
    t->mode_at = first_poll + 20000u;
}

static void tp_tick(struct touchpad *t, uint64_t now)
{
    if (t->used && now - t->fragment_at >= TP_FRAGMENT_US)
        tp_bad(t);
}

static int tp_mode_due(const struct touchpad *t, uint64_t now)
{
    return t->requested && !t->mode_enabled && !t->used &&
        t->mode_attempts < TP_MODE_ATTEMPTS && now >= t->mode_at;
}

/* SET_REPORT(HID_FEATURE_REPORT), report 2, payload {2, 1}. Framed reply
 * length is 2. The 4-byte SPI status is a separate stage under the SAME CS.
 * A valid input report, not the SPI status alone, confirms native mode. */
static void tp_mode_packet(struct touchpad *t, uint8_t p[TP_PACKET_SIZE],
    uint64_t now)
{
    for (size_t i = 0; i < TP_PACKET_SIZE; ++i)
        p[i] = 0;
    p[0] = 0x40;
    p[1] = 2;
    tp_put16(p + 6, 12);
    p[8] = 0x52;
    p[9] = 2;
    p[11] = t->next_id++;
    tp_put16(p + 12, 2);
    tp_put16(p + 14, 2);
    p[16] = 2;
    p[17] = 1;
    tp_put16(p + 18, tp_crc(p + 8, 10));
    tp_put16(p + 254, tp_crc(p, 254));
    ++t->mode_attempts;
    t->mode_at = now + TP_RETRY_US;
}

static int tp_clamp(int value, int maximum)
{
    return value < 0 ? 0 : value > maximum ? maximum : value;
}

static void tp_move(struct touchpad *t, int dx, int dy, int gain)
{
    /* Callers bound deltas to signed 16-bit differences or signed 8 bits. */
    t->x = tp_clamp(t->x + dx * gain, TP_MAX_X);
    t->y = tp_clamp(t->y + dy * gain, TP_MAX_Y);
}

static int tp_report(struct touchpad *t, const uint8_t *r, size_t n,
    uint64_t now)
{
    if (n == 0) return 0;
    if (r[0] == 0x60) {
        tp_restart(t, now);
        return 1;
    }
    if (r[0] != 2) return 0;

    /* Boot mouse reports use signed relative bytes. Native reports contain
     * this same prefix, but its deltas MUST NOT be added to finger motion. */
    if (n == 8) {
        t->tracking = 0;
        t->present = 1;
        ++t->reports;
        tp_buttons(t, r[1]);
        tp_move(t, tp_s8(r[2]), tp_s8(r[3]), TP_BOOT_GAIN);
        t->report_at = now;
        return 1;
    }
    if (n < TP_REPORT_HEADER ||
        (n - TP_REPORT_HEADER) % TP_FINGER_SIZE != 0)
        return 0;
    size_t slots = (n - TP_REPORT_HEADER) / TP_FINGER_SIZE;
    unsigned fingers = r[30];
    if (slots > TP_MAX_FINGERS || fingers > slots)
        return 0;

    unsigned contacts = 0;
    int x = 0, y = 0;
    for (unsigned i = 0; i < fingers; ++i) {
        const uint8_t *f = r + TP_REPORT_HEADER + i * TP_FINGER_SIZE;
        if (tp_s16(f + 18) <= 0) continue; /* touch_major: actual contact */
        x = tp_s16(f + 4);
        y = -tp_s16(f + 6); /* Apple's sensor Y axis points upwards. */
        ++contacts;
    }

    t->present = 1;
    t->mode_enabled = 1;
    ++t->reports;
    ++t->native_reports;
    tp_buttons(t, r[31] & 1u);
    if (contacts == 1) {
        if (t->tracking && now - t->report_at < TP_REBASE_US) {
            int dx = x - t->previous_x;
            int dy = y - t->previous_y;
            /* There is no documented stable contact ID in these records.
             * Rebase on implausible jumps instead of moving across the screen. */
            if (dx >= -TP_MAX_STEP && dx <= TP_MAX_STEP &&
                dy >= -TP_MAX_STEP && dy <= TP_MAX_STEP)
                tp_move(t, dx, dy, TP_GAIN);
        }
        t->previous_x = x;
        t->previous_y = y;
        t->tracking = 1;
    } else {
        /* Zero fingers = lift. Multiple fingers = no cursor motion. Never
         * choose an arbitrary array slot as a persistent tracking identity. */
        t->tracking = 0;
    }
    t->report_at = now;
    return 1;
}

static void tp_decode(struct touchpad *t, const uint8_t *p, size_t size,
    uint64_t now)
{
    if (size != TP_PACKET_SIZE) { tp_bad(t); return; }
    /* Keyboard and write responses cannot mutate pointer/fragment state. */
    if (p[0] != 0x20 || p[1] != 2) return;
    if (tp_crc(p, size) != 0) { tp_bad(t); return; }
    size_t offset = tp_le16(p + 2);
    size_t remaining = tp_le16(p + 4);
    size_t n = tp_le16(p + 6);
    if (!n || n > TP_PACKET_DATA || offset > TP_MESSAGE_MAX ||
        n > TP_MESSAGE_MAX - offset || remaining > TP_MESSAGE_MAX - offset - n) {
        tp_bad(t);
        return;
    }
    size_t total = offset + n + remaining;
    if (total < 11) { tp_bad(t); return; }
    if (offset == 0) {
        if (t->used) tp_discontinuity(t); /* missing end of previous report */
        t->total = total;
        t->fragment_at = now;
    } else if (!t->used || now - t->fragment_at >= TP_FRAGMENT_US) {
        tp_bad(t);
        return;
    }
    if (offset != t->used || total != t->total) {
        tp_bad(t);
        return;
    }
    for (size_t i = 0; i < n; ++i)
        t->message[offset + i] = p[8 + i];
    t->used += n;
    if (remaining) return;
    t->used = 0;
    t->total = 0;
    const uint8_t *m = t->message;
    if (tp_crc(m, total) || tp_le16(m + 6) != total - 10 ||
        m[0] != 0x10 || m[2] != 0 ||
        (m[8] != 0x60 && m[1] != 2)) {
        tp_bad(t);
        return;
    }
    if (!tp_report(t, m + 8, total - 10, now)) tp_bad(t);
}

/* Plain 32-bit words avoid coupling the C decoder to a V struct layout.
 * Called under the same lock as poll. Edges are consumed exactly once. */
static inline int tp_snapshot(struct touchpad *t, int32_t out[8])
{
    if (!out || !t->present) return 0;
    out[0] = t->x;
    out[1] = t->y;
    out[2] = TP_MAX_X;
    out[3] = TP_MAX_Y;
    out[4] = (int32_t)t->buttons;
    out[5] = (int32_t)t->pressed;
    out[6] = (int32_t)t->released;
    out[7] = 0; /* Wheel/gesture synthesis is deliberately not implemented. */
    t->pressed = 0;
    t->released = 0;
    return 1;
}

#endif
