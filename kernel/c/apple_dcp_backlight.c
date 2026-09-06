/* SPDX-License-Identifier: GPL-2.0-only OR MIT
 * Copyright (C) The Asahi Linux Contributors
 *
 * Calibration and wire-layout reference:
 * AsahiLinux/linux drivers/gpu/drm/apple/dcp_backlight.c (blob
 * 9eb0c7d4eb5345178f802e55dc8e8a3dbdbea8cd), iomfb_template.h (blob
 * 8efab49cc53d08964a5da5476fb99c050923aaa2), and iomfb_template.c
 * (blob cf40e273a2f43cd6576857f45e89a9edb4e5c841).
 *
 * This is the backlight portion of a driver, not a DCP takeover/RPC
 * implementation. It deliberately cannot send mailbox messages or touch
 * GPIO/PWM registers. See tools/apple-backlight/README.md for integration.
 */
#include "apple_dcp_backlight.h"

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define SCALE 1024U

static const uint32_t brightness_part1[] = {
    0x0000000, 0x0810038, 0x0f000bd, 0x143011c,
    0x1850165, 0x1bc01a1, 0x1eb01d4, 0x2140200,
    0x2380227, 0x2590249, 0x2770269, 0x2930285,
    0x2ac02a0, 0x2c402b8, 0x2d902cf, 0x2ee02e4,
    0x30102f8, 0x314030b, 0x325031c, 0x335032d,
    0x345033d, 0x354034d, 0x362035b, 0x3700369,
    0x37d0377, 0x38a0384, 0x3960390, 0x3a2039c,
    0x3ad03a7, 0x3b803b3, 0x3c303bd, 0x3cd03c8,
    0x3d703d2, 0x3e103dc, 0x3ea03e5, 0x3f303ef,
    0x3fc03f8, 0x4050400, 0x40d0409, 0x4150411,
    0x41d0419, 0x4250421, 0x42d0429, 0x4340431,
    0x43c0438, 0x443043f, 0x44a0446, 0x451044d,
    0x4570454, 0x45e045b, 0x4640461, 0x46b0468,
    0x471046e, 0x4770474, 0x47d047a, 0x4830480,
    0x4890486, 0x48e048b, 0x4940491, 0x4990497,
    0x49f049c, 0x4a404a1, 0x4a904a7, 0x4ae04ac,
    0x4b304b1, 0x4b804b6, 0x4bd04bb, 0x4c204c0,
    0x4c704c5, 0x4cc04c9, 0x4d004ce, 0x4d504d3,
    0x4d904d7, 0x4de04dc, 0x4e204e0, 0x4e704e4,
    0x4eb04e9, 0x4ef04ed, 0x4f304f1, 0x4f704f5,
    0x4fb04f9, 0x4ff04fd, 0x5030501, 0x5070505,
    0x50b0509, 0x50f050d, 0x5130511, 0x5160515,
    0x51a0518, 0x51e051c, 0x5210520, 0x5250523,
    0x5290527, 0x52c052a, 0x52f052e, 0x5330531,
    0x5360535, 0x53a0538, 0x53d053b, 0x540053f,
    0x5440542, 0x5470545, 0x54a0548, 0x54d054c,
    0x550054f, 0x5530552, 0x5560555, 0x5590558,
    0x55c055b, 0x55f055e, 0x5620561, 0x5650564,
    0x5680567, 0x56b056a, 0x56e056d, 0x571056f,
    0x5740572, 0x5760575, 0x5790578, 0x57c057b,
    0x57f057d, 0x5810580, 0x5840583, 0x5870585,
    0x5890588, 0x58c058b, 0x58f058d
};
static const uint32_t brightness_part12[] = { 0x58f058d, 0x59d058f };
static const uint32_t brightness_part2[] = {
    0x59d058f, 0x5b805ab, 0x5d105c5, 0x5e805dd,
    0x5fe05f3, 0x6120608, 0x625061c, 0x637062e,
    0x6480640, 0x6580650, 0x6680660, 0x677066f,
    0x685067e, 0x693068c, 0x6a00699, 0x6ac06a6,
    0x6b806b2, 0x6c406be, 0x6cf06ca, 0x6da06d5,
    0x6e506df, 0x6ef06ea, 0x6f906f4, 0x70206fe,
    0x70c0707, 0x7150710, 0x71e0719, 0x7260722,
    0x72f072a, 0x7370733, 0x73f073b, 0x7470743,
    0x74e074a, 0x7560752, 0x75d0759, 0x7640760,
    0x76b0768, 0x772076e, 0x7780775, 0x77f077c,
    0x7850782, 0x78c0789, 0x792078f, 0x7980795,
    0x79e079b, 0x7a407a1, 0x7aa07a7, 0x7af07ac,
    0x7b507b2, 0x7ba07b8, 0x7c007bd, 0x7c507c2,
    0x7ca07c8, 0x7cf07cd, 0x7d407d2, 0x7d907d7,
    0x7de07dc, 0x7e307e1, 0x7e807e5, 0x7ec07ea,
    0x7f107ef, 0x7f607f3, 0x7fa07f8, 0x7fe07fc
};

struct vinix_dcp_bl {
    unsigned layout;
    uint32_t maximum, scale, requested, actual;
    uint64_t generation, active_generation, next_token, active_token;
    int online, have_request, actual_valid, pending, inflight;
};

/* Interpolate the PACKED calibration word, then multiply it by sixteen.
 * Interpolating the halves separately changes the established calibration.
 * The caller handles endpoints so index + 1 is always within the table. */
static uint32_t interpolate(uint32_t val, uint32_t low, uint32_t high,
                             const uint32_t *table, size_t count)
{
    uint32_t position = (uint32_t)(count - 1) * ((val - low) * SCALE) / (high - low);
    size_t index = position / SCALE;
    uint32_t fraction = position % SCALE;
    return (uint32_t)(((uint64_t)fraction * table[index + 1] +
        (uint64_t)(SCALE - fraction) * table[index]) / SCALE);
}

int vinix_dcp_bl_nits_to_dac(uint32_t nits, uint32_t *dac)
{
    uint32_t value;
    if (!dac || nits < VINIX_DCP_BL_MIN_NITS || nits > VINIX_DCP_BL_MAX_NITS)
        return VINIX_DCP_BL_INVALID;
    if (nits == 2)
        value = brightness_part1[0];
    else if (nits == 99)
        value = brightness_part1[ARRAY_SIZE(brightness_part1) - 1];
    else if (nits == 103)
        value = brightness_part2[0];
    else if (nits < 99)
        value = interpolate(nits, 2, 99, brightness_part1, ARRAY_SIZE(brightness_part1));
    else if (nits < 103)
        value = interpolate(nits, 99, 103, brightness_part12, ARRAY_SIZE(brightness_part12));
    else
        value = interpolate(nits, 103, 510, brightness_part2, ARRAY_SIZE(brightness_part2));
    *dac = value * 16U;
    return VINIX_DCP_BL_OK;
}

int vinix_dcp_bl_parse(const void *text, size_t length, uint32_t *nits)
{
    const unsigned char *p = text;
    uint32_t value = 0;
    size_t i;
    if (!p || !nits || !length || length > VINIX_DCP_BL_WRITE_LIMIT)
        return VINIX_DCP_BL_INVALID;
    if (p[length - 1] == '\n')
        --length;
    if (!length)
        return VINIX_DCP_BL_INVALID;
    for (i = 0; i < length; ++i) {
        uint32_t digit;
        if (p[i] < '0' || p[i] > '9')
            return VINIX_DCP_BL_INVALID;
        digit = (uint32_t)(p[i] - '0');
        if (value > (VINIX_DCP_BL_MAX_NITS - digit) / 10U)
            return VINIX_DCP_BL_INVALID;
        value = value * 10U + digit;
    }
    if (value < VINIX_DCP_BL_MIN_NITS)
        return VINIX_DCP_BL_INVALID;
    *nits = value;
    return VINIX_DCP_BL_OK;
}

/* Packed structs differ by ONE byte at bl_unk. Do not cast an unaligned
 * buffer to native integer pointers and do not guess a version range. */
static int layout_info(unsigned layout, size_t *offset, size_t *size)
{
    switch (layout) {
    case VINIX_DCP_BL_LAYOUT_12_3:
        *offset = 0x2e6;
        *size = 0x320;
        return VINIX_DCP_BL_OK;
    case VINIX_DCP_BL_LAYOUT_13_3:
        *offset = 0x2e7;
        *size = 0x468;
        return VINIX_DCP_BL_OK;
    default:
        return VINIX_DCP_BL_UNSUPPORTED;
    }
}

int vinix_dcp_bl_patch_swap(unsigned layout, uint32_t nits, void *swap, size_t length)
{
    unsigned char *p = swap;
    size_t offset, size, i;
    uint32_t dac;
    int result = layout_info(layout, &offset, &size);
    if (result != VINIX_DCP_BL_OK)
        return result;
    if (!p || length < size || vinix_dcp_bl_nits_to_dac(nits, &dac) != VINIX_DCP_BL_OK)
        return VINIX_DCP_BL_INVALID;
    /* bl_unk = 1 (LE64), bl_value = calibrated DAC (LE32), bl_power = 0x40.
     * No other flags, surfaces, timestamps, or background bytes are touched. */
    p[offset] = 1;
    for (i = 1; i < 8; ++i)
        p[offset + i] = 0;
    for (i = 0; i < 4; ++i)
        p[offset + 8 + i] = (unsigned char)(dac >> (8 * i));
    p[offset + 12] = 0x40;
    return VINIX_DCP_BL_OK;
}

size_t vinix_dcp_bl_state_size(void)
{
    return sizeof(struct vinix_dcp_bl);
}

int vinix_dcp_bl_init(struct vinix_dcp_bl *bl, unsigned layout,
                      uint32_t panel_max_nits, uint32_t brightness_scale,
                      uint32_t initial_raw_nits, int initial_valid)
{
    size_t offset, size;
    uint32_t maximum, actual = 0;
    int result;
    if (!bl || panel_max_nits < VINIX_DCP_BL_MIN_NITS || !brightness_scale)
        return VINIX_DCP_BL_INVALID;
    result = layout_info(layout, &offset, &size);
    if (result != VINIX_DCP_BL_OK)
        return result;
    maximum = panel_max_nits < VINIX_DCP_BL_MAX_NITS ? panel_max_nits : VINIX_DCP_BL_MAX_NITS;
    if (initial_valid) {
        actual = initial_raw_nits / brightness_scale;
        /* Readback may be below the writable minimum, including blanked. */
        if (actual > panel_max_nits)
            return VINIX_DCP_BL_INVALID;
    }
    *bl = (struct vinix_dcp_bl){
        .layout = layout, .maximum = maximum, .scale = brightness_scale,
        .actual = actual, .actual_valid = !!initial_valid,
    };
    return VINIX_DCP_BL_OK;
}

int vinix_dcp_bl_set_online(struct vinix_dcp_bl *bl, int online)
{
    if (!bl || !bl->scale)
        return VINIX_DCP_BL_INVALID;
    online = !!online;
    if (online == bl->online)
        return VINIX_DCP_BL_OK;
    bl->online = online;
    bl->inflight = 0;
    bl->active_token = 0;
    bl->pending = bl->have_request;
    if (!online)
        bl->actual_valid = 0;
    return VINIX_DCP_BL_OK;
}

int vinix_dcp_bl_request(struct vinix_dcp_bl *bl, uint32_t nits)
{
    if (!bl || !bl->scale || nits < VINIX_DCP_BL_MIN_NITS || nits > bl->maximum)
        return VINIX_DCP_BL_INVALID;
    if (!bl->online)
        return VINIX_DCP_BL_OFFLINE;
    if (bl->generation == UINT64_MAX)
        return VINIX_DCP_BL_OVERFLOW;
    ++bl->generation;
    bl->requested = nits;
    bl->have_request = 1;
    bl->pending = 1;
    return VINIX_DCP_BL_OK;
}

int vinix_dcp_bl_write(struct vinix_dcp_bl *bl, const void *text, size_t length)
{
    uint32_t nits;
    int result = vinix_dcp_bl_parse(text, length, &nits);
    return result == VINIX_DCP_BL_OK ? vinix_dcp_bl_request(bl, nits) : result;
}

int vinix_dcp_bl_prepare(struct vinix_dcp_bl *bl, void *swap, size_t length, uint64_t *token)
{
    int result;
    if (!bl || !token || !bl->scale)
        return VINIX_DCP_BL_INVALID;
    if (!bl->online)
        return VINIX_DCP_BL_OFFLINE;
    if (bl->inflight)
        return VINIX_DCP_BL_BUSY;
    if (!bl->pending)
        return VINIX_DCP_BL_IDLE;
    if (bl->next_token == UINT64_MAX)
        return VINIX_DCP_BL_OVERFLOW;
    result = vinix_dcp_bl_patch_swap(bl->layout, bl->requested, swap, length);
    if (result != VINIX_DCP_BL_OK)
        return result;
    bl->active_generation = bl->generation;
    bl->active_token = ++bl->next_token;
    bl->inflight = 1;
    *token = bl->active_token;
    return VINIX_DCP_BL_OK;
}

int vinix_dcp_bl_complete(struct vinix_dcp_bl *bl, uint64_t token, int accepted)
{
    if (!bl || !bl->scale)
        return VINIX_DCP_BL_INVALID;
    if (!bl->online)
        return VINIX_DCP_BL_OFFLINE;
    if (!token || !bl->inflight || token != bl->active_token)
        return VINIX_DCP_BL_STALE;
    bl->pending = !accepted || bl->generation != bl->active_generation;
    bl->inflight = 0;
    bl->active_token = 0;
    return VINIX_DCP_BL_OK;
}

int vinix_dcp_bl_publish(struct vinix_dcp_bl *bl, uint32_t raw_nits)
{
    if (!bl || !bl->scale)
        return VINIX_DCP_BL_INVALID;
    if (!bl->online)
        return VINIX_DCP_BL_OFFLINE;
    /* Report firmware measurements as measurements, not a requested value.
     * A measured value may exceed the writable (calibrated) range. */
    bl->actual = raw_nits / bl->scale;
    bl->actual_valid = 1;
    return VINIX_DCP_BL_OK;
}

static size_t append_string(char *out, size_t pos, const char *s)
{
    while (*s)
        out[pos++] = *s++;
    return pos;
}

static size_t append_number(char *out, size_t pos, uint32_t value)
{
    char digits[10];
    size_t length = 0;
    do {
        digits[length++] = (char)('0' + value % 10U);
        value /= 10U;
    } while (value);
    while (length)
        out[pos++] = digits[--length];
    return pos;
}

int vinix_dcp_bl_format(const struct vinix_dcp_bl *bl, char *text, size_t capacity)
{
    char local[VINIX_DCP_BL_TEXT_CAPACITY];
    size_t n = 0, i;
    if (!bl || !bl->scale || !text)
        return VINIX_DCP_BL_INVALID;
    n = append_string(local, n, "requested_nits=");
    n = bl->have_request ? append_number(local, n, bl->requested) : append_string(local, n, "unknown");
    n = append_string(local, n, "\nactual_nits=");
    n = bl->actual_valid ? append_number(local, n, bl->actual) : append_string(local, n, "unknown");
    n = append_string(local, n, "\nmin_nits=2\nmax_nits=");
    n = append_number(local, n, bl->maximum);
    n = append_string(local, n, "\npending=");
    n = append_number(local, n, (uint32_t)bl->pending);
    n = append_string(local, n, "\nonline=");
    n = append_number(local, n, (uint32_t)bl->online);
    n = append_string(local, n, "\n");
    if (capacity <= n)
        return VINIX_DCP_BL_INVALID;
    for (i = 0; i < n; ++i)
        text[i] = local[i];
    text[n] = '\0';
    return (int)n;
}
