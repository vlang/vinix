// SPDX-License-Identifier: MIT
// Original N64 PADDLE: gameplay, pixels, controller polling and SRAM writes all
// execute on the emulated R4300. No host gameplay or drawing hook is used.
typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
#define WORD(address) (*(volatile u32 *)(address))
#define WIDTH 320
#define HEIGHT 240
static volatile u16 *pixels;
static volatile u8 *const pif = (volatile u8 *)0xa02f0000;
static volatile u32 *const record = (volatile u32 *)0xa02f0100;
static volatile u32 *const commands = (volatile u32 *)0xa02f0200;
static unsigned best, games, score, lives, mode, flying, age, buffer;
static int paddle = 136, ball_x = 160, ball_y = 199, dx = 2, dy = -2;
static unsigned bricks[40];
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

static void pi_transfer(unsigned reading) {
    while (WORD(0xa4600010) & 3) {}
    WORD(0xa4600000) = 0x002f0100;
    WORD(0xa4600004) = 0x08000000;
    WORD(reading ? 0xa460000c : 0xa4600008) = 15;
    while (WORD(0xa4600010) & 3) {}
    WORD(0xa4600010) = 2;
}
static void save(void) {
    record[0] = 0x4e504144; // NPAD: big-endian private record in dedicated SRAM.
    record[1] = best;
    record[2] = games;
    record[3] = record[0] ^ record[1] ^ record[2];
    __asm__ volatile("sync" ::: "memory");
    pi_transfer(0);
}
static unsigned input(int *stick) {
    while (WORD(0xa4800018) & 3) {}
    for (unsigned i = 0; i < 64; ++i) pif[i] = 0;
    pif[0] = 1; pif[1] = 4; pif[2] = 1; // Joybus read-controller command.
    pif[7] = 0xfe; pif[63] = 1;
    __asm__ volatile("sync" ::: "memory");
    WORD(0xa4800000) = 0x002f0000;
    WORD(0xa4800010) = 0x1fc007c0;
    while (WORD(0xa4800018) & 3) {}
    WORD(0xa4800018) = 0;
    WORD(0xa4800000) = 0x002f0000;
    WORD(0xa4800004) = 0x1fc007c0;
    while (WORD(0xa4800018) & 3) {}
    WORD(0xa4800018) = 0;
    *stick = (signed char)pif[5];
    return ((unsigned)pif[3] << 8) | pif[4];
}
static u16 color(unsigned value) {
    return (u16)(((value >> 8) & 0xf800) | ((value >> 5) & 0x7c0) |
                 ((value >> 2) & 0x3e) | 1);
}
static void clear(unsigned origin) {
    // Submit actual RDP fill-cycle commands through DP DMA. FullSync raises
    // the MI DP interrupt only after the clear completes; foreground CPU
    // drawing then overlays a fully covered RGBA5551 framebuffer.
    unsigned ink = color(0x0b1025);
    commands[0] = 0xff100000 | (WIDTH - 1); // SetColorImage: RGBA, 16-bit.
    commands[1] = origin;
    commands[2] = 0xed000000; // SetScissor, coordinates in 10.2 fixed point.
    commands[3] = (WIDTH * 4 << 12) | (HEIGHT * 4);
    commands[4] = 0xef300000; commands[5] = 0; // SetOtherModes: fill cycle.
    commands[6] = 0xf7000000; commands[7] = ink | (ink << 16);
    commands[8] = 0xf6000000 | ((WIDTH - 1) * 4 << 12) | ((HEIGHT - 1) * 4);
    commands[9] = 0; // FillRectangle, inclusive lower-right in fill cycle.
    commands[10] = 0xe9000000; commands[11] = 0; // FullSync.
    __asm__ volatile("sync" ::: "memory");
    WORD(0xa4300000) = 0x800; // Clear any previous MI DP interrupt.
    WORD(0xa410000c) = 0x15; // Clear XBUS-DMA, freeze and flush.
    WORD(0xa4100000) = 0x002f0200;
    WORD(0xa4100004) = 0x002f0230;
    while (!(WORD(0xa4300008) & 0x20)) {}
}
static void rectangle(int x, int y, int width, int height, unsigned value) {
    u16 ink = color(value);
    for (int row = y; row < y + height; ++row)
        for (int col = x; col < x + width; ++col)
            pixels[row * WIDTH + col] = ink;
}
static void text(int x, int y, const char *value, int scale, unsigned ink) {
    for (; *value; ++value, x += 4 * scale) {
        unsigned glyph;
        for (glyph = 0; glyph < 36 && characters[glyph] != *value; ++glyph) {}
        if (glyph == 36) continue;
        for (unsigned row = 0; row < 5; ++row)
            for (unsigned col = 0; col < 3; ++col)
                if (font[glyph][row] & (4 >> col))
                    rectangle(x + (int)col * scale, y + (int)row * scale, scale, scale, ink);
    }
}
static void number(int x, int y, unsigned value, unsigned ink) {
    char digits[8];
    unsigned n = 0;
    do { digits[n++] = (char)('0' + value % 10); value /= 10; } while (value && n < 7);
    for (unsigned i = 0; i < n / 2; ++i) {
        char c = digits[i]; digits[i] = digits[n - i - 1]; digits[n - i - 1] = c;
    }
    digits[n] = 0;
    text(x, y, digits, 2, ink);
}
static void restart(void) {
    paddle = 136; ball_x = 160; ball_y = 199; dx = 2; dy = -2;
    score = 0; lives = 3; mode = 1; flying = 1;
    for (unsigned i = 0; i < 40; ++i) bricks[i] = 1;
    ++games;
    save();
}
static void update(unsigned buttons, int stick) {
    ++age;
    if (!mode || mode == 2) {
        if (buttons & 0x9000) restart(); // Start or A.
        return;
    }
    if ((buttons & 0x0200) || stick < -16) paddle -= 4;
    if ((buttons & 0x0100) || stick > 16) paddle += 4;
    if (paddle < 12) paddle = 12;
    if (paddle > 260) paddle = 260;
    if (!flying) {
        ball_x = paddle + 24;
        if (buttons & 0x8000) flying = 1;
        return;
    }
    ball_x += dx; ball_y += dy;
    if (ball_x < 14 || ball_x > 304) dx = -dx;
    if (ball_y < 29) dy = -dy;
    if (dy > 0 && ball_y >= 198 && ball_y <= 203 && ball_x >= paddle - 4 && ball_x <= paddle + 52) {
        dy = -2; dx = ball_x < paddle + 24 ? -2 : 2;
    }
    if (ball_y > 221) {
        flying = 0; ball_y = 199; dx = 2; dy = -2;
        if (!--lives) mode = 2;
    }
    unsigned remaining = 0;
    for (unsigned i = 0; i < 40; ++i) {
        if (!bricks[i]) continue;
        ++remaining;
        int x = 16 + (int)(i % 8) * 36, y = 44 + (int)(i / 8) * 15;
        if (ball_x >= x - 3 && ball_x <= x + 34 && ball_y >= y - 3 && ball_y <= y + 12) {
            bricks[i] = 0; score += 10; dy = -dy;
            if (score > best) { best = score; save(); }
            break;
        }
    }
    if (!remaining) {
        for (unsigned i = 0; i < 40; ++i) bricks[i] = 1;
        flying = 0; ball_y = 199; dx = 2; dy = -2;
    }
}
static void draw(void) {
    static const unsigned colors[5] = {0xff6978,0xffa85c,0xffdb72,0x63d9bc,0x739cff};
    unsigned origin = buffer ? 0x00140000 : 0x00100000;
    pixels = (volatile u16 *)(0xa0000000 | origin);
    clear(origin);
    for (unsigned i = 0; i < 38; ++i) {
        int x = 13 + (int)((i * 67) % 290), y = 28 + (int)((i * 39 + age / 3) % 188);
        rectangle(x, y, 1, 1, 0x455170);
    }
    rectangle(9, 25, 2, 197, 0x314572);
    rectangle(309, 25, 2, 197, 0x314572);
    rectangle(9, 25, 302, 2, 0x314572);
    text(13, 10, "SCORE", 2, 0x91a2c9);
    number(58, 10, score, 0xffffff);
    text(125, 10, "BEST", 2, 0x91a2c9);
    number(161, 10, best, 0xffdb72);
    text(238, 10, "LIVES", 2, 0x91a2c9);
    number(283, 10, lives, 0xffffff);
    for (unsigned i = 0; i < 40; ++i) {
        if (mode && !bricks[i]) continue;
        int x = 16 + (int)(i % 8) * 36, y = 44 + (int)(i / 8) * 15;
        rectangle(x, y, 33, 11, colors[i / 8]);
        rectangle(x + 2, y + 2, 29, 2, 0xffffff);
    }
    rectangle(paddle, 205, 48, 6, 0x63d9bc);
    rectangle(paddle + 3, 206, 42, 2, 0xc4ffee);
    rectangle(ball_x - 2, ball_y - 2, 5, 5, 0xffffff);
    text(20, 224, "DPAD OR STICK MOVE  A LAUNCH", 2, 0x91a2c9);
    if (!mode || mode == 2) {
        rectangle(54, 117, 212, 69, 0x182443);
        rectangle(54, 117, 212, 2, 0x739cff);
        text(mode ? 80 : 112, 130, mode ? "GAME OVER" : "PADDLE", 4, 0xffffff);
        text(94, 163, "PRESS START", 3, 0x63d9bc);
    }
    __asm__ volatile("sync" ::: "memory");
    WORD(0xa4400004) = origin;
    buffer ^= 1;
}
__attribute__((noreturn)) void game_main(void) {
    WORD(0xa4400000) = 0x3202; // 16-bit framebuffer, no AA.
    WORD(0xa4400004) = 0x00100000;
    WORD(0xa4400008) = WIDTH;
    WORD(0xa440000c) = 2;
    WORD(0xa4400014) = 0x03e52239;
    WORD(0xa4400018) = 525;
    WORD(0xa440001c) = 0x00000c15;
    WORD(0xa4400020) = 0x0c150c15;
    WORD(0xa4400024) = 0x006c02ec;
    WORD(0xa4400028) = 0x002501ff;
    WORD(0xa440002c) = 0x000e0204;
    WORD(0xa4400030) = 0x00000200;
    WORD(0xa4400034) = 0x00000400;
    WORD(0xa4600024) = 0x40; // Cartridge domain-2 SRAM bus timing.
    WORD(0xa4600028) = 0x12;
    WORD(0xa460002c) = 7;
    WORD(0xa4600030) = 3;
    pi_transfer(1);
    if (record[0] == 0x4e504144 && record[3] == (record[0] ^ record[1] ^ record[2])) {
        best = record[1]; games = record[2];
    }
    lives = 3;
    for (;;) {
        draw();
        while (WORD(0xa4400010) < 480) {}
        while (WORD(0xa4400010) >= 480) {}
        int stick;
        unsigned buttons = input(&stick);
        update(buttons, stick);
    }
}
