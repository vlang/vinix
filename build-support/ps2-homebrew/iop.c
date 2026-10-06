// SPDX-License-Identifier: MIT
// Bare-metal R3000 controller/card worker. Runs on the emulated PS2 IOP.
typedef unsigned char u8;
typedef unsigned int u32;
#define WORD(address) (*(volatile u32 *)(address))
#define BYTE(address) (*(volatile u8 *)(address))

static u8 response[144];
static u8 request[64];
static volatile u32 *const saved = (volatile u32 *)0x800;

static void transact(unsigned port, unsigned length) {
    WORD(0x1f808268) = 12;
    WORD(0x1f808200) = port | (length << 8) | (length << 18);
    WORD(0x1f808204) = 0;
    for (unsigned i = 0; i < length; ++i) BYTE(0x1f808260) = request[i];
    WORD(0x1f808268) = 1;
    for (unsigned i = 0; i < 144; ++i) response[i] = BYTE(0x1f808264);
    WORD(0x1f808280) = 3;
}
static void card_address(unsigned command) {
    request[0] = 0x81;
    request[1] = command;
    request[2] = 16; // Private homebrew save record in sector 16.
    request[3] = request[4] = request[5] = 0;
    request[6] = 16;
    request[7] = request[8] = 0;
    transact(2, 9);
}
static u32 read_word(unsigned offset) {
    return response[offset] | ((u32)response[offset + 1] << 8) |
        ((u32)response[offset + 2] << 16) | ((u32)response[offset + 3] << 24);
}
static void load_card(void) {
    card_address(0x23);
    request[0] = 0x81;
    request[1] = 0x43;
    request[2] = 16;
    for (unsigned i = 3; i < 22; ++i) request[i] = 0;
    transact(2, 22);
    if (read_word(4) == 0x44415056 && read_word(16) ==
            (0x44415056 ^ read_word(8) ^ read_word(12))) {
        saved[0] = read_word(8);
        saved[1] = read_word(12);
    } else {
        saved[0] = saved[1] = 0;
    }
}
static void save_card(void) {
    card_address(0x22);
    request[0] = 0x81;
    request[1] = 0x42;
    request[2] = 16;
    u32 record[4] = {0x44415056, saved[0], saved[1],
        0x44415056 ^ saved[0] ^ saved[1]};
    unsigned checksum = 0;
    for (unsigned i = 0; i < 16; ++i) {
        request[3 + i] = (u8)(record[i >> 2] >> ((i & 3) * 8));
        checksum ^= request[3 + i];
    }
    request[19] = (u8)checksum;
    request[20] = request[21] = 0;
    transact(2, 22);
    request[0] = 0x81;
    request[1] = 0x81;
    request[2] = request[3] = 0;
    transact(2, 4);
}
__attribute__((noreturn)) void iop_main(void) {
    load_card();
    WORD(0x1d000010) = 0xffff;
    u32 last = 0;
    for (;;) {
        u32 command = WORD(0x1d000000);
        if (command == last) continue;
        last = command;
        if (command & 0x80000000) save_card();
        request[0] = 1;
        request[1] = 0x42;
        for (unsigned i = 2; i < 9; ++i) request[i] = 0;
        transact(0, 9);
        WORD(0x1d000010) = (command & 0xffff0000) |
            (u32)response[3] | ((u32)response[4] << 8);
    }
}
