/* SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Apple SPI shared keyboard/touchpad transport and console decoder.
 * Register/protocol reference: U-Boot drivers/spi/apple_spi.c and
 * drivers/input/apple_spi_kbd.c, Copyright (C) 2021 Mark Kettenis and
 * Copyright The Asahi Linux Contributors, GPL-2.0-or-later.
 * Message/packet CRC framing is also documented by the Asahi Linux
 * drivers/hid/spi-hid/spi-hid-apple-core.c transport.
 *
 * No allocation, DMA, firmware upload, interrupt handler, or USB dependency.
 * The small I/O interface is used unchanged by the production driver and the
 * host tests. DT discovery and locking belong to apple.spi_keyboard in V.
 */
#include "apple_spi_keyboard.h"

#if defined(__AARCH64__) || defined(VINIX_APPLE_SPI_TEST)

#include "apple_spi_touchpad.h"

#define SPI_CTRL       0x000
#define SPI_CFG        0x004
#define SPI_STATUS     0x008
#define SPI_PIN        0x00c
#define SPI_TXDATA     0x010
#define SPI_RXDATA     0x020
#define SPI_CLKDIV     0x030
#define SPI_RXCNT      0x034
#define SPI_WORD_DELAY 0x038
#define SPI_TXCNT      0x04c
#define SPI_FIFOSTAT   0x10c
#define SPI_IE_XFER    0x130
#define SPI_IF_XFER    0x134
#define SPI_IE_FIFO    0x138
#define SPI_IF_FIFO    0x13c
#define SPI_SHIFTCFG   0x150
#define SPI_PINCFG     0x154
#define SPI_RUN        1u
#define SPI_RESET      12u
#define SPI_CS_HIGH    2u
#define FIFO_DEPTH     16u
#define PACKET_SIZE    256u
#define MESSAGE_SIZE   20u /* 8-byte header + 10-byte report + 2-byte CRC */
#define TRANSFER_US    5000u
#define POLL_US        2000u
/* How long the transport stays down before it is brought back up. Long enough
 * that genuinely dead hardware is not hammered, short enough that a user who
 * looked away does not come back to a machine that takes no input. */
#define REVIVE_US      2000000u
#define FRAGMENT_US    100000u
#define REPEAT_DELAY   500000u
#define REPEAT_PERIOD  33333u

struct key_bytes {
    /* Long enough for the longest sequence a key can produce, which is the
     * report that Cmd has been let go rather than anything on a keycap. */
    uint8_t data[16];
    size_t len;
};

struct decoder {
    uint8_t keys[6];
    uint8_t modifiers;
    uint8_t fn;
    uint8_t caps;
    uint8_t repeat_key;
    /* Whether a chord was sent while Cmd was down. The desktop's window
     * switcher is drawn for as long as Cmd is held, so unlike every other
     * modifier this one's release has to be reported -- but only to someone
     * who asked, which is what pressing Cmd-Tab counts as. */
    uint8_t gui_chorded;
    uint64_t repeat_at;
    uint8_t message[MESSAGE_SIZE];
    size_t message_used;
    uint64_t fragment_at;
    uint64_t reports;
};

struct io_ops {
    uint32_t (*read32)(void *, uint64_t);
    void (*write32)(void *, uint64_t, uint32_t);
    uint64_t (*now_us)(void *);
    void (*delay_us)(void *, uint32_t);
};

struct spi_keyboard {
    struct io_ops io;
    void *cookie;
    uint64_t spi;
    uint64_t enable;
    uint64_t ready;
    int enable_low;
    int ready_low;
    int active;
    unsigned errors;
    /* What start_keyboard was given, so the transport can be brought back
     * without the device-tree work being done again. */
    uint32_t input_hz;
    uint32_t maximum_hz;
    /* When to try that, or 0 for not scheduled. */
    uint64_t revive_at;
    uint64_t next_poll;
    uint64_t next_transfer;
    struct decoder decoder;
    struct touchpad touchpad;
};

static uint16_t read_le16(const uint8_t *p)
{
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

/* CRC-16/ARC: reflected polynomial 0xa001, initial value 0. Appending the
 * little-endian CRC makes the CRC of the complete packet/message zero. */
static uint16_t crc16(const uint8_t *p, size_t n)
{
    uint16_t crc = 0;
    while (n--) {
        crc ^= *p++;
        for (unsigned b = 0; b < 8; ++b)
            crc = (uint16_t)((crc >> 1) ^ ((crc & 1u) ? 0xa001u : 0));
    }
    return crc;
}

static int has_key(const uint8_t keys[6], uint8_t key)
{
    for (unsigned i = 0; i < 6; ++i)
        if (keys[i] == key)
            return 1;
    return 0;
}

static void cancel_repeat(struct decoder *d)
{
    d->repeat_at = 0;
    d->message_used = 0;
}

static void reset_input(struct decoder *d)
{
    cancel_repeat(d);
    d->repeat_key = 0;
    d->gui_chorded = 0;
    d->modifiers = 0;
    d->fn = 0;
    for (unsigned i = 0; i < 6; ++i)
        d->keys[i] = 0;
    /* Caps Lock is logical console state, not a physically held key. */
}

static void sequence(struct key_bytes *out, const char *s)
{
    while (*s && out->len < sizeof(out->data))
        out->data[out->len++] = (uint8_t)*s++;
}

static void decimal(struct key_bytes *out, unsigned value)
{
    unsigned divisor = 1;
    while (divisor <= value / 10)
        divisor *= 10;
    do {
        if (out->len >= sizeof(out->data))
            return;
        out->data[out->len++] = (uint8_t)('0' + value / divisor % 10);
        divisor /= 10;
    } while (divisor);
}

static void csi_u(struct key_bytes *out, unsigned codepoint,
    unsigned modifiers)
{
    sequence(out, "\033[");
    decimal(out, codepoint);
    sequence(out, ";");
    decimal(out, 1 + modifiers);
    sequence(out, "u");
}

static struct key_bytes encode_key(uint8_t key, uint8_t modifiers,
    int caps, int fn, int application_cursor)
{
    struct key_bytes out = {{0}, 0};
    int shift = !!(modifiers & 0x22u);
    int ctrl = !!(modifiers & 0x11u);
    int alt = !!(modifiers & 0x44u);
    int gui = !!(modifiers & 0x88u);
    uint8_t c = 0;
    int printable = 0;
    const char *s = NULL;

    /* Fn is an extra byte in Apple's report, not a HID modifier bit. */
    if (fn) {
        switch (key) {
        case 42: key = 76; break; /* Fn-Backspace: forward delete */
        case 79: key = 77; break; /* Fn-Right: End */
        case 80: key = 74; break; /* Fn-Left: Home */
        case 81: key = 78; break; /* Fn-Down: Page Down */
        case 82: key = 75; break; /* Fn-Up: Page Up */
        default: break;
        }
    }

    /* Preserve GUI chords in the console stream for graphical compositors. */
    if (gui && key == 43) {
        csi_u(&out, 9, 8u | (unsigned)shift);
        return out;
    }

    if (key >= 4 && key <= 29) {
        c = (uint8_t)((shift ^ !!caps ? 'A' : 'a') + key - 4);
        printable = 1;
    } else if (key >= 30 && key <= 39) {
        c = (uint8_t)(shift ? "!@#$%^&*()" : "1234567890")[key - 30];
        printable = 1;
    } else {
        switch (key) {
        case 40: case 88: c = '\r'; break;
        case 41: c = 0x1b; break;
        case 42: c = '\b'; break; /* Vinix's current canonical erase byte */
        case 43: if (shift) s = "\033[Z"; else c = '\t'; break;
        case 44: c = ' '; printable = 1; break;
        case 45: c = shift ? '_' : '-'; printable = 1; break;
        case 46: c = shift ? '+' : '='; printable = 1; break;
        case 47: c = shift ? '{' : '['; printable = 1; break;
        case 48: c = shift ? '}' : ']'; printable = 1; break;
        case 49: case 100: c = shift ? '|' : '\\'; printable = 1; break;
        case 50: c = shift ? '~' : '#'; printable = 1; break;
        case 51: c = shift ? ':' : ';'; printable = 1; break;
        case 52: c = shift ? '"' : '\''; printable = 1; break;
        case 53: c = shift ? '~' : '`'; printable = 1; break;
        case 54: c = shift ? '<' : ','; printable = 1; break;
        case 55: c = shift ? '>' : '.'; printable = 1; break;
        case 56: c = shift ? '?' : '/'; printable = 1; break;
        case 58: s = "\033OP"; break;
        case 59: s = "\033OQ"; break;
        case 60: s = "\033OR"; break;
        case 61: s = "\033OS"; break;
        case 62: s = "\033[15~"; break;
        case 63: s = "\033[17~"; break;
        case 64: s = "\033[18~"; break;
        case 65: s = "\033[19~"; break;
        case 66: s = "\033[20~"; break;
        case 67: s = "\033[21~"; break;
        case 68: s = "\033[23~"; break;
        case 69: s = "\033[24~"; break;
        case 73: s = "\033[2~"; break;
        case 74: s = application_cursor ? "\033OH" : "\033[H"; break;
        case 75: s = "\033[5~"; break;
        case 76: s = "\033[3~"; break;
        case 77: s = application_cursor ? "\033OF" : "\033[F"; break;
        case 78: s = "\033[6~"; break;
        case 79: s = application_cursor ? "\033OC" : "\033[C"; break;
        case 80: s = application_cursor ? "\033OD" : "\033[D"; break;
        case 81: s = application_cursor ? "\033OB" : "\033[B"; break;
        case 82: s = application_cursor ? "\033OA" : "\033[A"; break;
        default: return out; /* Unknown/reserved/lock/media keys */
        }
    }
    if (gui && c) {
        unsigned mods = 8u | (unsigned)shift | ((unsigned)alt << 1) |
            ((unsigned)ctrl << 2);
        csi_u(&out, c, mods);
        return out;
    }
    if (alt)
        out.data[out.len++] = 0x1b;
    if (s) {
        sequence(&out, s);
        return out;
    }
    if (ctrl && printable) {
        if ((c >= '@' && c <= '_') || (c >= 'a' && c <= 'z'))
            c &= 0x1fu;
        else if (c == ' ' || c == '2') c = 0;
        else if (c == '6') c = 0x1e;
        else if (c == '-') c = 0x1f;
        else if (c == '?' || c == '8') c = 0x7f;
    }
    out.data[out.len++] = c;
    return out;
}

static int append_key(uint8_t *out, size_t capacity, size_t *used,
    struct key_bytes key)
{
    /* Drop a whole sequence rather than leaving a partial terminal escape. */
    if (key.len == 0 || *used > capacity || key.len > capacity - *used)
        return 0;
    for (size_t i = 0; i < key.len; ++i)
        out[(*used)++] = key.data[i];
    return 1;
}

static size_t accept_report(struct decoder *d, const uint8_t report[10],
    uint64_t now, int app, uint8_t *out, size_t capacity)
{
    uint8_t keys[6] = {0};
    size_t used = 0;
    d->modifiers = report[1];
    d->fn = !!report[9];
    ++d->reports;
    /* Cmd let go. Nothing on a terminal has ever wanted to hear about a
     * modifier's release, so this only goes out when a chord was sent while it
     * was down. It is the left Super key in the CSI-u functional encoding,
     * with an event type of 3, "released". */
    if (d->gui_chorded && !(d->modifiers & 0x88u)) {
        struct key_bytes release = {{0}, 0};
        d->gui_chorded = 0;
        sequence(&release, "\033[57444;1:3u");
        append_key(out, capacity, &used, release);
    }
    for (unsigned i = 0; i < 6; ++i) {
        uint8_t key = report[i + 3];
        /* ErrorRollOver, POSTFail, ErrorUndefined are not key releases.
         * Keep the last good set but suppress repeat until a good report. */
        if (key >= 1 && key <= 3) {
            d->repeat_at = 0;
            return 0;
        }
        if (key && !has_key(keys, key))
            keys[i] = key;
    }
    if (has_key(keys, 57) && !has_key(d->keys, 57))
        d->caps = !d->caps;
    if (d->repeat_key && !has_key(keys, d->repeat_key)) {
        d->repeat_key = 0;
        d->repeat_at = 0;
    }
    for (unsigned i = 0; i < 6; ++i) {
        uint8_t key = keys[i];
        if (!key || key == 57 || has_key(d->keys, key))
            continue;
        struct key_bytes bytes = encode_key(key, d->modifiers, d->caps, d->fn, app);
        if (append_key(out, capacity, &used, bytes)) {
            d->repeat_key = key;
            d->repeat_at = now + REPEAT_DELAY;
            if (d->modifiers & 0x88u)
                d->gui_chorded = 1;
        }
    }
    for (unsigned i = 0; i < 6; ++i)
        d->keys[i] = keys[i];
    if (d->repeat_key && d->repeat_at == 0)
        d->repeat_at = now + REPEAT_DELAY;
    return used;
}

/* Returns bytes produced. Touchpad, management, boot status and write
 * responses never become keystrokes. Only the known 20-byte keyboard message
 * is reassembled; arbitrary-sized HID descriptors/reports are out of scope. */
static size_t decode_packet(struct decoder *d, const uint8_t *packet,
    size_t length, uint64_t now, int app, uint8_t *out, size_t capacity)
{
    if (length != PACKET_SIZE) {
        cancel_repeat(d);
        return 0;
    }
    if (packet[0] != 0x20 || packet[1] != 1)
        return 0;
    if (crc16(packet, PACKET_SIZE) != 0) {
        cancel_repeat(d);
        return 0;
    }
    size_t offset = read_le16(packet + 2);
    size_t remaining = read_le16(packet + 4);
    size_t n = read_le16(packet + 6);
    if (!n || n > MESSAGE_SIZE || offset > MESSAGE_SIZE ||
        remaining > MESSAGE_SIZE || offset + n + remaining != MESSAGE_SIZE) {
        cancel_repeat(d);
        return 0;
    }
    if (offset == 0) {
        d->message_used = 0;
        d->fragment_at = now;
    } else if (d->message_used == 0 || now - d->fragment_at >= FRAGMENT_US) {
        cancel_repeat(d);
        return 0;
    }
    if (offset != d->message_used || n > MESSAGE_SIZE - offset) {
        cancel_repeat(d);
        return 0;
    }
    for (size_t i = 0; i < n; ++i)
        d->message[offset + i] = packet[8 + i];
    d->message_used += n;
    if (remaining) {
        d->repeat_at = 0;
        return 0;
    }
    d->message_used = 0;
    const uint8_t *m = d->message;
    if (crc16(m, MESSAGE_SIZE) || m[0] != 0x10 || m[1] != 1 ||
        read_le16(m + 6) != 10 || m[8] != 1) {
        cancel_repeat(d);
        return 0;
    }
    return accept_report(d, m + 8, now, app, out, capacity);
}

static size_t repeat_key(struct decoder *d, uint64_t now, int app,
    uint8_t *out, size_t capacity)
{
    size_t used = 0;
    if (!d->repeat_at || now < d->repeat_at || d->message_used)
        return 0;
    if (!d->repeat_key || !has_key(d->keys, d->repeat_key)) {
        d->repeat_at = 0;
        return 0;
    }
    append_key(out, capacity, &used,
        encode_key(d->repeat_key, d->modifiers, d->caps, d->fn, app));
    /* Never emit an unbounded catch-up burst after a scheduler stall. */
    d->repeat_at = now + REPEAT_PERIOD;
    return used;
}

static uint32_t reg_read(struct spi_keyboard *k, unsigned offset)
{
    return k->io.read32(k->cookie, k->spi + offset);
}

static void reg_write(struct spi_keyboard *k, unsigned offset, uint32_t value)
{
    k->io.write32(k->cookie, k->spi + offset, value);
}

static void set_enable(struct spi_keyboard *k, int enabled)
{
    uint32_t v = k->io.read32(k->cookie, k->enable);
    /* GPIO MODE=OUT(1), PERIPH=0. Preserve pull/drive and unrelated bits. */
    v &= ~(1u | (7u << 1) | (3u << 5));
    v |= 2u | (uint32_t)(!!enabled ^ !!k->enable_low);
    k->io.write32(k->cookie, k->enable, v);
}

static int start_keyboard(struct spi_keyboard *k, uint32_t input_hz,
    uint32_t maximum_hz)
{
    if (!input_hz || !maximum_hz || maximum_hz > 8000000u)
        return 0;
    k->input_hz = input_hz;
    k->maximum_hz = maximum_hz;
    uint64_t divider = ((uint64_t)input_hz + maximum_hz - 1) / maximum_hz;
    if (divider < 2) divider = 2;
    if (divider > 0x7ff) return 0; /* Do not silently exceed the DT maximum. */

    k->active = 0;
    reg_write(k, SPI_CTRL, 0);
    reg_write(k, SPI_PIN, SPI_CS_HIGH);
    reg_write(k, SPI_IE_XFER, 0);
    reg_write(k, SPI_IE_FIFO, 0);
    reg_write(k, SPI_SHIFTCFG, reg_read(k, SPI_SHIFTCFG) & ~(1u << 24));
    reg_write(k, SPI_PINCFG,
        (reg_read(k, SPI_PINCFG) & ~(1u << 9)) | (1u << 1));
    reg_write(k, SPI_CTRL, SPI_RESET);
    /* Match Apple's/U-Boot's PIO FIFO configuration: mode 1, 8-bit words,
     * 8-byte threshold, mode-0 clock. No interrupt-enable bits are set. */
    reg_write(k, SPI_CFG, 1u << 5);
    reg_write(k, SPI_CLKDIV, (uint32_t)divider);
    reg_write(k, SPI_WORD_DELAY, 0);
    reg_write(k, SPI_STATUS, 7);
    reg_write(k, SPI_IF_XFER, 3);
    reg_write(k, SPI_IF_FIFO, 0x30330);
    reg_write(k, SPI_CTRL, 0);

    set_enable(k, 1);
    k->io.delay_us(k->cookie, 5000);
    set_enable(k, 0);
    k->io.delay_us(k->cookie, 5000);
    set_enable(k, 1);
    /* Let the controller boot without a 50-ms busy wait in kernel init. */
    k->next_poll = k->io.now_us(k->cookie) + 50000;
    k->next_transfer = k->next_poll;
    k->errors = 0;
    reset_input(&k->decoder);
    tp_init(&k->touchpad, k->next_poll);
    k->active = 1;
    return 1;
}

/* A single FIFO stage. CS belongs to the caller so a write and its status
 * read can share one selection, with the required direction-change delay. */
static int transfer_bytes(struct spi_keyboard *k, const uint8_t *output,
    uint8_t *input, size_t length)
{
    size_t tx = 0, rx = 0;
    int ok = 0;
    if (!length || length > PACKET_SIZE) return 0;
    reg_write(k, SPI_CTRL, SPI_RESET);
    reg_write(k, SPI_TXCNT, (uint32_t)length);
    reg_write(k, SPI_RXCNT, (uint32_t)length);
    for (; tx < FIFO_DEPTH && tx < length; ++tx)
        reg_write(k, SPI_TXDATA, output ? output[tx] : 0);
    uint64_t start = k->io.now_us(k->cookie);
    reg_write(k, SPI_CTRL, SPI_RUN);

    for (unsigned spins = 0; spins < 100000; ++spins) {
        uint32_t status = reg_read(k, SPI_FIFOSTAT);
        unsigned n = (status >> 24) & 0xffu;
        if (n > FIFO_DEPTH || n > length - rx) break;
        while (n--) {
            uint8_t byte = (uint8_t)reg_read(k, SPI_RXDATA);
            if (input) input[rx] = byte;
            ++rx;
        }
        status = reg_read(k, SPI_FIFOSTAT);
        unsigned level = (status >> 8) & 0xffu;
        if (level > FIFO_DEPTH) break;
        n = FIFO_DEPTH - level;
        while (n-- && tx < length) {
            reg_write(k, SPI_TXDATA, output ? output[tx] : 0);
            ++tx;
        }
        if (rx == length && tx == length) { ok = 1; break; }
        if (k->io.now_us(k->cookie) - start >= TRANSFER_US) break;
    }
    reg_write(k, SPI_CTRL, 0);
    return ok;
}

static void end_transfer(struct spi_keyboard *k, int ok)
{
    reg_write(k, SPI_CTRL, 0);
    k->io.delay_us(k->cookie, 100);
    reg_write(k, SPI_PIN, SPI_CS_HIGH);
    k->next_transfer = k->io.now_us(k->cookie) + 250;
    if (!ok) reg_write(k, SPI_CTRL, SPI_RESET);
}

static int read_packet(struct spi_keyboard *k, uint8_t packet[PACKET_SIZE])
{
    reg_write(k, SPI_PIN, 0);
    k->io.delay_us(k->cookie, 100);
    int ok = transfer_bytes(k, NULL, packet, PACKET_SIZE);
    end_transfer(k, ok);
    return ok;
}

static void enable_touchpad(struct spi_keyboard *k, uint64_t now)
{
    uint8_t packet[PACKET_SIZE];
    uint8_t status[4] = {0};
    tp_mode_packet(&k->touchpad, packet, now);
    reg_write(k, SPI_PIN, 0);
    k->io.delay_us(k->cookie, 100);
    int ok = transfer_bytes(k, packet, NULL, PACKET_SIZE);
    if (ok) {
        /* No CS edge here: Asahi's write and status are one SPI message. */
        k->io.delay_us(k->cookie, 200);
        ok = transfer_bytes(k, NULL, status, sizeof(status));
    }
    end_transfer(k, ok);
    if (!ok || status[0] != 0xac || status[1] != 0x27 ||
        status[2] != 0x68 || status[3] != 0xd5)
        ++k->touchpad.mode_errors;
    /* A failed feature write does NOT disable keyboard reads. Retries are
     * bounded independently and native reports can arrive despite bad status. */
}

static int boot_packet(const uint8_t p[PACKET_SIZE])
{
    return read_le16(p + 2) == 0 && read_le16(p + 4) == 0 &&
        read_le16(p + 6) == 4 && p[8] == 0xa0 && p[9] == 0x80 &&
        p[10] == 0 && p[11] == 0 && crc16(p, PACKET_SIZE) == 0;
}

static int packet_envelope_valid(const uint8_t p[PACKET_SIZE])
{
    /* A completed PIO transaction is not necessarily a packet: an idle or
     * wedged HID controller can clock a buffer full of zeroes. Keep unknown
     * device/report IDs forward-compatible, but require the Apple read flag,
     * a payload that fits this packet and a valid outer CRC. */
    size_t n = read_le16(p + 6);
    return p[0] == 0x20 && n != 0 && n <= PACKET_SIZE - 10 &&
        crc16(p, PACKET_SIZE) == 0;
}

static int read_error(struct spi_keyboard *k)
{
    reset_input(&k->decoder);
    tp_discontinuity(&k->touchpad);
    if (++k->errors >= 3) {
        /* Down, but not for good: both devices share this transport. */
        k->active = 0;
        k->revive_at = k->io.now_us(k->cookie) + REVIVE_US;
        return -2;
    }
    k->next_poll = k->io.now_us(k->cookie) + 20000;
    return -1;
}

static int poll_keyboard(struct spi_keyboard *k, uint8_t *out,
    size_t capacity, int application_cursor)
{
    if (!out || capacity == 0)
        return 0;
    if (!k->active) {
        /* Bring it back when the cool-off has passed. Re-running the start
         * sequence reprograms a controller that may itself have reset. */
        if (!k->revive_at || k->io.now_us(k->cookie) < k->revive_at)
            return 0;
        if (!start_keyboard(k, k->input_hz, k->maximum_hz)) {
            k->revive_at = k->io.now_us(k->cookie) + REVIVE_US;
            return 0;
        }
        k->revive_at = 0;
        return -3;
    }
    size_t used = 0;
    uint64_t now = k->io.now_us(k->cookie);
    tp_tick(&k->touchpad, now);
    if (k->decoder.message_used && now - k->decoder.fragment_at >= FRAGMENT_US)
        cancel_repeat(&k->decoder);
    if (now >= k->next_poll && now >= k->next_transfer) {
        k->next_poll = now + POLL_US;
        // Do not insert a feature command in the middle of either report.
        if (!k->errors && !k->decoder.message_used && tp_mode_due(&k->touchpad, now)) {
            enable_touchpad(k, now);
            now = k->io.now_us(k->cookie);
            return (int)repeat_key(&k->decoder, now, application_cursor, out, capacity);
        }
        int ready = 1;
        if (k->ready) {
            uint32_t v = k->io.read32(k->cookie, k->ready);
            ready = !!(v & 1u) ^ !!k->ready_low;
        }
        /* The ready line is the HID interrupt. Do not periodically clock the
         * controller while it is inactive; timer-only polling is reserved for
         * device trees that do not supply the line at all. */
        if (ready) {
            uint8_t packet[PACKET_SIZE];
            if (!read_packet(k, packet))
                return read_error(k);
            /* With a ready line, a successful transfer that did not return a
             * valid packet is a transport failure too. Previously all-zero
             * reads cleared the error count and left input dead indefinitely. */
            if (k->ready && !packet_envelope_valid(packet))
                return read_error(k);
            k->errors = 0;
            now = k->io.now_us(k->cookie);
            if (boot_packet(packet)) {
                reset_input(&k->decoder);
                tp_restart(&k->touchpad, now);
            } else {
                tp_decode(&k->touchpad, packet, sizeof(packet), now);
                used = decode_packet(&k->decoder, packet, sizeof(packet), now,
                    application_cursor, out, capacity);
            }
        }
    }
    used += repeat_key(&k->decoder, now, application_cursor, out + used, capacity - used);
    return (int)used;
}

#ifdef __AARCH64__
/* Use the same width-exact MMIO routines as aarch64.kio; ordinary volatile
 * pointer accesses used to produce invalid paired/64-bit accesses on M1. */
extern uint32_t vinix_mmio_read32(void *);
extern void vinix_mmio_write32(void *, uint32_t);
static struct spi_keyboard keyboard;
static uint64_t counter_frequency;

static uint32_t kernel_read32(void *cookie, uint64_t address)
{
    (void)cookie;
    uint32_t v = vinix_mmio_read32((void *)(uintptr_t)address);
    __asm__ volatile("dmb ish" ::: "memory");
    return v;
}

static void kernel_write32(void *cookie, uint64_t address, uint32_t value)
{
    (void)cookie;
    __asm__ volatile("dmb ish" ::: "memory");
    vinix_mmio_write32((void *)(uintptr_t)address, value);
}

static uint64_t kernel_now_us(void *cookie)
{
    (void)cookie;
    uint64_t count;
    /* CNTVCT, not CNTPCT: the latter may trap under the M1 EL2 handoff. */
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(count));
    return (count / counter_frequency) * 1000000 +
        (count % counter_frequency) * 1000000 / counter_frequency;
}

static void kernel_delay_us(void *cookie, uint32_t us)
{
    uint64_t start = kernel_now_us(cookie);
    while (kernel_now_us(cookie) - start < us)
        __asm__ volatile("yield" ::: "memory");
}

int vinix_apple_spi_keyboard_init(uint64_t spi_base, uint64_t enable_reg,
    int enable_active_low, uint64_t ready_reg, int ready_active_low,
    uint32_t input_hz, uint32_t maximum_hz)
{
    if (keyboard.active || !spi_base || !enable_reg ||
        (spi_base & 3) || (enable_reg & 3) || (ready_reg & 3))
        return 0;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(counter_frequency));
    if (!counter_frequency || counter_frequency > UINT32_MAX)
        return 0;
    keyboard = (struct spi_keyboard){0};
    keyboard.io = (struct io_ops){kernel_read32, kernel_write32,
        kernel_now_us, kernel_delay_us};
    keyboard.spi = spi_base;
    keyboard.enable = enable_reg;
    keyboard.enable_low = enable_active_low;
    keyboard.ready = ready_reg;
    keyboard.ready_low = ready_active_low;
    return start_keyboard(&keyboard, input_hz, maximum_hz);
}

int vinix_apple_spi_keyboard_poll(uint8_t *out, size_t capacity, int app)
{
    return poll_keyboard(&keyboard, out, capacity, app);
}

uint64_t vinix_apple_spi_keyboard_reports(void)
{
    return keyboard.decoder.reports;
}

uint64_t vinix_apple_spi_touchpad_reports(void)
{
    return keyboard.touchpad.reports;
}

int vinix_apple_spi_touchpad_read(int32_t out[8])
{
    if (out) keyboard.touchpad.requested = 1;
    return tp_snapshot(&keyboard.touchpad, out);
}
#endif /* __AARCH64__ */
#endif /* __AARCH64__ || VINIX_APPLE_SPI_TEST */
