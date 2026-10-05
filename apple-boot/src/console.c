// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Diagnostics on iBoot's framebuffer. A MacBook has no serial port, so a
 * photo of the screen is the only report from a failed boot: stage squares
 * along the top edge, and on failure a red band with hex values drawn in a
 * 5x7 digit font. All writes are aligned 32-bit stores, which is all the
 * MMU-off Device mapping allows. */
#include "lib.h"
#include "loader.h"

static struct {
    uint32_t *pixels;
    uint64_t stride; /* in pixels */
    uint64_t width;
    uint64_t height;
    int thirty_bit;
    unsigned scale;
    unsigned last_stage;
} fb;

/* HD44780-style 5x7 glyphs for 0-9 and A-F, one row per byte, bit 4 left. */
static const uint8_t hex_glyphs[16][7] = {
    {0x0e, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0e}, {0x04, 0x0c, 0x04, 0x04, 0x04, 0x04, 0x0e},
    {0x0e, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1f}, {0x1f, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0e},
    {0x02, 0x06, 0x0a, 0x12, 0x1f, 0x02, 0x02}, {0x1f, 0x10, 0x1e, 0x01, 0x01, 0x11, 0x0e},
    {0x06, 0x08, 0x10, 0x1e, 0x11, 0x11, 0x0e}, {0x1f, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08},
    {0x0e, 0x11, 0x11, 0x0e, 0x11, 0x11, 0x0e}, {0x0e, 0x11, 0x11, 0x0f, 0x01, 0x02, 0x0c},
    {0x0e, 0x11, 0x11, 0x1f, 0x11, 0x11, 0x11}, {0x1e, 0x11, 0x11, 0x1e, 0x11, 0x11, 0x1e},
    {0x0e, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0e}, {0x1c, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1c},
    {0x1f, 0x10, 0x10, 0x1e, 0x10, 0x10, 0x1f}, {0x1f, 0x10, 0x10, 0x1e, 0x10, 0x10, 0x10},
};

static const uint8_t stage_colours[8][3] = {
    {0x20, 0xc0, 0x20}, {0x20, 0x60, 0xff}, {0xff, 0xd0, 0x20}, {0x20, 0xd0, 0xd0},
    {0xd0, 0x30, 0xd0}, {0xff, 0xff, 0xff}, {0xff, 0x80, 0x20}, {0x80, 0x80, 0x80},
};

static uint32_t colour(unsigned red, unsigned green, unsigned blue)
{
    if (fb.thirty_bit)
        return (uint32_t)red << 22 | (uint32_t)green << 12 | (uint32_t)blue << 2;
    return (uint32_t)red << 16 | (uint32_t)green << 8 | (uint32_t)blue;
}

static void fill(uint64_t x, uint64_t y, uint64_t width, uint64_t height, uint32_t value)
{
    if (!fb.pixels || x >= fb.width || y >= fb.height)
        return;
    if (x + width > fb.width)
        width = fb.width - x;
    if (y + height > fb.height)
        height = fb.height - y;
    for (uint64_t row = 0; row < height; row++) {
        uint32_t *line = fb.pixels + (y + row) * fb.stride + x;
        for (uint64_t column = 0; column < width; column++)
            line[column] = value;
    }
}

void console_init(const struct boot_video *video)
{
    unsigned depth = (unsigned)(video->depth & 0xff);

    fb.pixels = NULL;
    if (!video->base || !video->width || !video->height || video->stride < video->width * 4)
        return;
    if (depth != 32 && depth != 30)
        return;
    fb.pixels = (uint32_t *)(uintptr_t)video->base;
    fb.stride = video->stride / 4;
    fb.width = video->width;
    fb.height = video->height;
    fb.thirty_bit = depth == 30;
    fb.scale = video->width >= 2000 ? 6 : 3;
}

void console_stage(unsigned stage)
{
    uint64_t size = 8 * (uint64_t)fb.scale;
    const uint8_t *rgb = stage_colours[stage % 8];

    fb.last_stage = stage;
    fill(size + stage * size * 3 / 2, size, size, size, colour(rgb[0], rgb[1], rgb[2]));
}

static void draw_digit(uint64_t x, uint64_t y, unsigned digit, uint32_t value)
{
    for (unsigned row = 0; row < 7; row++) {
        for (unsigned column = 0; column < 5; column++) {
            if (hex_glyphs[digit & 15][row] & (0x10 >> column))
                fill(x + column * fb.scale, y + row * fb.scale, fb.scale, fb.scale, value);
        }
    }
}

static void draw_hex(uint64_t x, uint64_t y, uint64_t number, unsigned digits, uint32_t value)
{
    for (unsigned index = 0; index < digits; index++) {
        unsigned digit = (unsigned)(number >> (4 * (digits - 1 - index))) & 15;
        draw_digit(x + index * 6 * fb.scale, y, digit, value);
    }
}

void console_hex(unsigned row, unsigned label, uint64_t value)
{
    uint64_t line = 8 * fb.scale * (3 + row);
    uint64_t x = 8 * fb.scale;
    uint32_t white = colour(0xff, 0xff, 0xff);

    fill(x, line, 30 * 6 * fb.scale, 8 * fb.scale, colour(0, 0, 0));
    draw_hex(x, line, label, 2, colour(0xff, 0xd0, 0x20));
    draw_hex(x + 4 * 6 * fb.scale, line, value, 16, white);
}

void loader_fail(unsigned code, uint64_t value)
{
    uint64_t band = 8 * fb.scale * 12;
    uint32_t red = colour(0xd0, 0x10, 0x10);
    uint32_t white = colour(0xff, 0xff, 0xff);

    fill(0, band, fb.width, 10 * fb.scale, red);
    draw_hex(8 * fb.scale, band + fb.scale, fb.last_stage, 2, white);
    draw_hex(8 * fb.scale + 4 * 6 * fb.scale, band + fb.scale, code, 4, white);
    draw_hex(8 * fb.scale + 10 * 6 * fb.scale, band + fb.scale, value, 16, white);
    halt_forever();
}

/* Called from the vector table with the vector index and syndrome. */
void loader_exception(uint64_t vector, uint64_t esr, uint64_t elr, uint64_t far)
{
    console_hex(6, 0xe1, esr);
    console_hex(7, 0xe2, elr);
    console_hex(8, 0xe3, far);
    loader_fail(0xe000 | (unsigned)vector, esr);
}
