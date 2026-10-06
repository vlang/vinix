// SPDX-License-Identifier: MIT
// PADDLE: a complete bare-metal PS2 brick-breaking game.
// All gameplay and drawing run on the emulated Emotion Engine. The IOP polls
// a real DualShock command through SIO2 and keeps the score on the memory card.
typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long long u64;
#define WORD(address) (*(volatile u32 *)(address))
#define QUAD(address) (*(volatile u64 *)(address))
#include "iop-image.h"

struct Packet { u64 data, reg; };
static struct Packet packet[8192] __attribute__((aligned(16)));
static unsigned used, sequence;
static int paddle = 274, ball_x = 320, ball_y = 397, dx = 3, dy = -4;
static unsigned score, lives = 3, mode, flying, age;
static unsigned bricks[40];
static volatile u32 *const saved = (volatile u32 *)0x1c000800;
static const char characters[] = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
static const u8 font[36][5] = {
    {7,5,5,5,7},{2,6,2,2,7},{7,1,7,4,7},{7,1,7,1,7},{5,5,7,1,1},
    {7,4,7,1,7},{7,4,7,5,7},{7,1,2,2,2},{7,5,7,5,7},{7,5,7,1,7},
    {2,5,7,5,5},{6,5,6,5,6},{7,4,4,4,7},{6,5,5,5,6},{7,4,6,4,7},
    {7,4,6,4,4},{7,4,5,5,7},{5,5,7,5,5},{7,2,2,2,7},{1,1,1,5,7},
    {5,5,6,5,5},{4,4,4,4,7},{5,7,7,5,5},{5,7,7,7,5},{7,5,5,5,7},
    {7,5,7,4,4},{7,5,5,7,1},{6,5,6,5,5},{7,4,7,1,7},{7,2,2,2,2},
    {5,5,5,5,7},{5,5,5,5,2},{5,5,7,7,5},{5,5,2,5,5},{5,5,2,2,2},
    {7,1,2,4,7},
};
static void reg(unsigned id, u64 value) {
    packet[used].data = value;
    packet[used++].reg = id;
}
static u64 rgb(unsigned value) {
    return ((value >> 16) & 255) | (value & 0xff00) | ((u64)(value & 255) << 16) | 0x80000000;
}
static void rectangle(int x, int y, int width, int height, unsigned color) {
    reg(0x00, 6); // Untextured sprite.
    reg(0x01, rgb(color));
    reg(0x05, ((u64)(unsigned)y << 20) | ((unsigned)x << 4));
    reg(0x05, ((u64)(unsigned)(y + height) << 20) | ((unsigned)(x + width) << 4));
}
static void text(int x, int y, const char *value, int scale, unsigned color) {
    for (; *value; ++value, x += 4 * scale) {
        unsigned glyph;
        for (glyph = 0; glyph < 36 && characters[glyph] != *value; ++glyph) {}
        if (glyph == 36) continue;
        for (unsigned row = 0; row < 5; ++row)
            for (unsigned col = 0; col < 3; ++col)
                if (font[glyph][row] & (4 >> col))
                    rectangle(x + (int)col * scale, y + (int)row * scale, scale, scale, color);
    }
}
static void number(int x, int y, unsigned value, unsigned color) {
    char digits[8];
    unsigned n = 0;
    do { digits[n++] = (char)('0' + value % 10); value /= 10; } while (value && n < 7);
    for (unsigned i = 0; i < n / 2; ++i) {
        char c = digits[i]; digits[i] = digits[n - i - 1]; digits[n - i - 1] = c;
    }
    digits[n] = 0;
    text(x, y, digits, 3, color);
}
static void send(void) {
    packet[0].data = (used - 1) | (7ull << 28); // DMAC END source-chain tag.
    packet[0].reg = 0;
    packet[1].data = (used - 2) | 0x8000ull | (1ull << 60);
    packet[1].reg = 0x0e; // GIF PACKED A+D.
    __asm__ volatile("sync" ::: "memory");
    WORD(0x1000a030) = (u32)(unsigned long)packet;
    WORD(0x1000a020) = 0;
    WORD(0x1000a000) = 0x105;
    while (WORD(0x1000a000) & 0x100) {}
}
static unsigned input(unsigned save) {
    sequence = (sequence + 1) & 0x7fff;
    u32 command = (sequence << 16) | (save ? 0x80000000 : 0);
    WORD(0x1000f200) = command;
    while ((WORD(0x1000f210) & 0xffff0000) != command) {}
    return (~WORD(0x1000f210)) & 0xffff;
}
static void restart(void) {
    paddle = 274;
    ball_x = 320;
    ball_y = 397;
    dx = 3; dy = -4;
    score = 0; lives = 3; mode = 1; flying = 1;
    for (unsigned i = 0; i < 40; ++i) bricks[i] = 1;
    ++saved[1];
    input(1);
}
static void update(unsigned buttons) {
    ++age;
    if (!mode || mode == 2) {
        if (buttons & (0x0008 | 0x4000)) restart();
        return;
    }
    if (buttons & 0x80) paddle -= 6;
    if (buttons & 0x20) paddle += 6;
    if (paddle < 24) paddle = 24;
    if (paddle > 520) paddle = 520;
    if (!flying) {
        ball_x = paddle + 46;
        if (buttons & 0x4000) flying = 1;
        return;
    }
    ball_x += dx;
    ball_y += dy;
    if (ball_x < 28 || ball_x > 608) dx = -dx;
    if (ball_y < 58) dy = -dy;
    if (dy > 0 && ball_y >= 394 && ball_y <= 405 && ball_x >= paddle - 8 && ball_x <= paddle + 100) {
        dy = -4;
        dx = ball_x < paddle + 46 ? -3 : 3;
    }
    if (ball_y > 442) {
        flying = 0;
        ball_y = 397;
        dx = 3; dy = -4;
        if (!--lives) mode = 2;
    }
    unsigned remaining = 0;
    for (unsigned i = 0; i < 40; ++i) {
        if (!bricks[i]) continue;
        ++remaining;
        int x = 32 + (int)(i % 8) * 72, y = 88 + (int)(i / 8) * 29;
        if (ball_x >= x - 6 && ball_x <= x + 68 && ball_y >= y - 6 && ball_y <= y + 24) {
            bricks[i] = 0;
            score += 10;
            dy = -dy;
            if (score > saved[0]) { saved[0] = score; input(1); }
            break;
        }
    }
    if (!remaining) {
        for (unsigned i = 0; i < 40; ++i) bricks[i] = 1;
        flying = 0; ball_y = 397; dx = 3; dy = -4;
    }
}
static void draw(void) {
    static const unsigned colors[5] = {0xff6978,0xffa85c,0xffdb72,0x63d9bc,0x739cff};
    used = 2;
    reg(0x4c, 10ull << 16); // 640-wide PSMCT32 framebuffer at VRAM zero.
    reg(0x4e, 1ull << 32); // Disable depth writes.
    reg(0x40, (639ull << 16) | (479ull << 48));
    reg(0x18, 0);
    reg(0x47, 0);
    reg(0x1a, 1);
    rectangle(0, 0, 640, 480, 0x0b1025);
    for (unsigned i = 0; i < 38; ++i) {
        int x = 26 + (int)((i * 137) % 580), y = 55 + (int)((i * 79 + age / 3) % 382);
        rectangle(x, y, 2, 2, 0x455170);
    }
    rectangle(18, 50, 4, 394, 0x314572);
    rectangle(618, 50, 4, 394, 0x314572);
    rectangle(18, 50, 604, 4, 0x314572);
    text(26, 20, "SCORE", 3, 0x91a2c9);
    number(98, 20, score, 0xffffff);
    text(242, 20, "BEST", 3, 0x91a2c9);
    number(302, 20, saved[0], 0xffdb72);
    text(480, 20, "LIVES", 3, 0x91a2c9);
    number(558, 20, lives, 0xffffff);
    for (unsigned i = 0; i < 40; ++i) {
        if (mode && !bricks[i]) continue;
        int x = 32 + (int)(i % 8) * 72, y = 88 + (int)(i / 8) * 29;
        rectangle(x, y, 66, 22, colors[i / 8]);
        rectangle(x + 3, y + 3, 60, 3, 0xffffff);
    }
    rectangle(paddle, 410, 96, 12, 0x63d9bc);
    rectangle(paddle + 5, 412, 86, 3, 0xc4ffee);
    rectangle(ball_x - 5, ball_y - 5, 10, 10, 0xffffff);
    text(82, 455, "LEFT RIGHT MOVE   CROSS LAUNCH", 3, 0x91a2c9);
    if (!mode || mode == 2) {
        rectangle(108, 234, 424, 139, 0x182443);
        rectangle(108, 234, 424, 4, 0x739cff);
        text(mode ? 148 : 200, 257, mode ? "GAME OVER" : "PADDLE", mode ? 9 : 10, 0xffffff);
        text(182, 324, "PRESS START", 6, 0x63d9bc);
    }
    send();
}
__attribute__((noreturn)) void game_main(void) {
    // The BIOS-free loader starts the IOP in an idle loop at RAM zero. Upload
    // our worker and replace that loop only after the complete program exists.
    volatile u8 *iop = (volatile u8 *)0x1c001000;
    for (unsigned i = 0; i < sizeof(iop_image); ++i) iop[i] = iop_image[i];
    __asm__ volatile("sync" ::: "memory");
    WORD(0x1c000000) = 0x08000400; // j 0x1000, with the existing nop delay slot.
    input(0);
    QUAD(0x12000000) = 1; // Enable display circuit 1.
    QUAD(0x12000020) = 0; // Non-interlaced.
    QUAD(0x12000070) = 10ull << 9;
    QUAD(0x12000080) = (639ull << 32) | (479ull << 44);
    WORD(0x1000e000) = 1;
    for (;;) {
        draw();
        QUAD(0x12001000) = 8;
        while (!(QUAD(0x12001000) & 8)) {}
        update(input(0));
    }
}
