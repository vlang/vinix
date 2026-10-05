// SPDX-License-Identifier: GPL-2.0-or-later
#include "../../kernel/c/apple_spi_keyboard.h"
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

#define read_le16(...) vinix_spi_core_read_le16(__VA_ARGS__)
uint16_t read_le16(const uint8_t *p);
#define crc16(...) vinix_spi_core_crc16(__VA_ARGS__)
uint16_t crc16(const uint8_t *p, size_t n);
#define has_key(...) vinix_spi_core_has_key(__VA_ARGS__)
int has_key(const uint8_t keys[6], uint8_t key);
#define cancel_repeat(...) vinix_spi_core_cancel_repeat(__VA_ARGS__)
void cancel_repeat(struct decoder *d);
#define reset_input(...) vinix_spi_core_reset_input(__VA_ARGS__)
void reset_input(struct decoder *d);
#define sequence(...) vinix_spi_core_sequence(__VA_ARGS__)
void sequence(struct key_bytes *out, const char *s);
#define decimal(...) vinix_spi_core_decimal(__VA_ARGS__)
void decimal(struct key_bytes *out, unsigned value);
#define csi_u(...) vinix_spi_core_csi_u(__VA_ARGS__)
void csi_u(struct key_bytes *out, unsigned codepoint,
    unsigned modifiers);
#define modified_arrow(...) vinix_spi_core_modified_arrow(__VA_ARGS__)
void modified_arrow(struct key_bytes *out, char final,
    unsigned modifiers);
#define encode_key(...) vinix_spi_core_encode_key(__VA_ARGS__)
struct key_bytes encode_key(uint8_t key, uint8_t modifiers,
    int caps, int fn, int application_cursor);
#define append_key(...) vinix_spi_core_append_key(__VA_ARGS__)
int append_key(uint8_t *out, size_t capacity, size_t *used,
    struct key_bytes key);
#define accept_report(...) vinix_spi_core_accept_report(__VA_ARGS__)
size_t accept_report(struct decoder *d, const uint8_t report[10],
    uint64_t now, int app, uint8_t *out, size_t capacity);
#define decode_packet(...) vinix_spi_core_decode_packet(__VA_ARGS__)
size_t decode_packet(struct decoder *d, const uint8_t *packet,
    size_t length, uint64_t now, int app, uint8_t *out, size_t capacity);
#define repeat_key(...) vinix_spi_core_repeat_key(__VA_ARGS__)
size_t repeat_key(struct decoder *d, uint64_t now, int app,
    uint8_t *out, size_t capacity);
#define reg_read(...) vinix_spi_core_reg_read(__VA_ARGS__)
uint32_t reg_read(struct spi_keyboard *k, unsigned offset);
#define reg_write(...) vinix_spi_core_reg_write(__VA_ARGS__)
void reg_write(struct spi_keyboard *k, unsigned offset, uint32_t value);
#define set_enable(...) vinix_spi_core_set_enable(__VA_ARGS__)
void set_enable(struct spi_keyboard *k, int enabled);
#define start_keyboard(...) vinix_spi_core_start_keyboard(__VA_ARGS__)
int start_keyboard(struct spi_keyboard *k, uint32_t input_hz,
    uint32_t maximum_hz);
#define transfer_bytes(...) vinix_spi_core_transfer_bytes(__VA_ARGS__)
int transfer_bytes(struct spi_keyboard *k, const uint8_t *output,
    uint8_t *input, size_t length);
#define end_transfer(...) vinix_spi_core_end_transfer(__VA_ARGS__)
void end_transfer(struct spi_keyboard *k, int ok);
#define read_packet(...) vinix_spi_core_read_packet(__VA_ARGS__)
int read_packet(struct spi_keyboard *k, uint8_t packet[PACKET_SIZE]);
#define enable_touchpad(...) vinix_spi_core_enable_touchpad(__VA_ARGS__)
void enable_touchpad(struct spi_keyboard *k, uint64_t now);
#define boot_packet(...) vinix_spi_core_boot_packet(__VA_ARGS__)
int boot_packet(const uint8_t p[PACKET_SIZE]);
#define packet_envelope_valid(...) vinix_spi_core_packet_envelope_valid(__VA_ARGS__)
int packet_envelope_valid(const uint8_t p[PACKET_SIZE]);
#define read_error(...) vinix_spi_core_read_error(__VA_ARGS__)
int read_error(struct spi_keyboard *k);
#define poll_keyboard(...) vinix_spi_core_poll_keyboard(__VA_ARGS__)
int poll_keyboard(struct spi_keyboard *k, uint8_t *out,
    size_t capacity, int application_cursor);
#define kernel_read32(...) vinix_spi_core_kernel_read32(__VA_ARGS__)
uint32_t kernel_read32(void *cookie, uint64_t address);
#define kernel_write32(...) vinix_spi_core_kernel_write32(__VA_ARGS__)
void kernel_write32(void *cookie, uint64_t address, uint32_t value);
#define kernel_now_us(...) vinix_spi_core_kernel_now_us(__VA_ARGS__)
uint64_t kernel_now_us(void *cookie);
#define kernel_delay_us(...) vinix_spi_core_kernel_delay_us(__VA_ARGS__)
void kernel_delay_us(void *cookie, uint32_t us);
#define tp_le16(...) vinix_spi_core_tp_le16(__VA_ARGS__)
uint16_t tp_le16(const uint8_t *p);
#define tp_s16(...) vinix_spi_core_tp_s16(__VA_ARGS__)
int tp_s16(const uint8_t *p);
#define tp_s8(...) vinix_spi_core_tp_s8(__VA_ARGS__)
int tp_s8(uint8_t n);
#define tp_put16(...) vinix_spi_core_tp_put16(__VA_ARGS__)
void tp_put16(uint8_t *p, uint16_t n);
#define tp_crc(...) vinix_spi_core_tp_crc(__VA_ARGS__)
uint16_t tp_crc(const uint8_t *p, size_t n);
#define tp_buttons(...) vinix_spi_core_tp_buttons(__VA_ARGS__)
void tp_buttons(struct touchpad *t, uint32_t buttons);
#define tp_discontinuity(...) vinix_spi_core_tp_discontinuity(__VA_ARGS__)
void tp_discontinuity(struct touchpad *t);
#define tp_bad(...) vinix_spi_core_tp_bad(__VA_ARGS__)
void tp_bad(struct touchpad *t);
#define tp_restart(...) vinix_spi_core_tp_restart(__VA_ARGS__)
void tp_restart(struct touchpad *t, uint64_t now);
#define tp_init(...) vinix_spi_core_tp_init(__VA_ARGS__)
void tp_init(struct touchpad *t, uint64_t first_poll);
#define tp_tick(...) vinix_spi_core_tp_tick(__VA_ARGS__)
void tp_tick(struct touchpad *t, uint64_t now);
#define tp_mode_due(...) vinix_spi_core_tp_mode_due(__VA_ARGS__)
int tp_mode_due(const struct touchpad *t, uint64_t now);
#define tp_mode_packet(...) vinix_spi_core_tp_mode_packet(__VA_ARGS__)
void tp_mode_packet(struct touchpad *t, uint8_t p[TP_PACKET_SIZE],
    uint64_t now);
#define tp_clamp(...) vinix_spi_core_tp_clamp(__VA_ARGS__)
int tp_clamp(int value, int maximum);
#define tp_move(...) vinix_spi_core_tp_move(__VA_ARGS__)
void tp_move(struct touchpad *t, int dx, int dy, int gain);
#define tp_report(...) vinix_spi_core_tp_report(__VA_ARGS__)
int tp_report(struct touchpad *t, const uint8_t *r, size_t n,
    uint64_t now);
#define tp_decode(...) vinix_spi_core_tp_decode(__VA_ARGS__)
void tp_decode(struct touchpad *t, const uint8_t *p, size_t size,
    uint64_t now);
#define tp_snapshot(...) vinix_spi_core_tp_snapshot(__VA_ARGS__)
int tp_snapshot(struct touchpad *t, int32_t out[8]);
