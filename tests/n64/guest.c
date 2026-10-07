// SPDX-License-Identifier: GPL-2.0-or-later
// Drive the ordinary desktop client through VAPP; inspect only game pixels.
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

enum { WINDOW_WIDTH = 800, WINDOW_HEIGHT = 680, WIDTH = 640, HEIGHT = 480,
       PIXELS = WIDTH * HEIGHT, SURFACE_BYTES = 48 + PIXELS * 8 };
static int request_fd = -1, response_fd = -1;
static unsigned char state[116], bytes[65536];
static size_t byte_count;
static char surface_path[512];
static char status_text[1024];
static uint32_t *surface;
static uint32_t first[PIXELS], last[PIXELS], neutral[PIXELS], controlled[PIXELS];
static pid_t child;
static const char *log_path = "/tmp/n64-emulator.log";
static unsigned frame_count;

static void print_log(void) {
    FILE *log = fopen(log_path, "r");
    if (!log) return;
    char line[512];
    while (fgets(line, sizeof(line), log)) fputs(line, stdout);
    fclose(log);
}
static void fail(const char *reason) {
    print_log();
    printf("N64 FAIL: %s (poll frame %u)\n", reason, frame_count);
    fflush(stdout);
    for (;;) pause();
}
static uint32_t number(const void *pointer) {
    uint32_t value;
    memcpy(&value, pointer, sizeof(value));
    return value;
}
static void transfer(int fd, void *pointer, size_t length, int writing) {
    size_t offset = 0;
    while (offset < length) {
        if (!writing) {
            struct pollfd waiting = {.fd = fd, .events = POLLIN};
            int ready;
            do { ready = poll(&waiting, 1, 30000); } while (ready < 0 && errno == EINTR);
            if (ready <= 0) fail("application reply timeout");
        }
        ssize_t count = writing ? write(fd, (char *)pointer + offset, length - offset) :
            read(fd, (char *)pointer + offset, length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) fail("application pipe closed");
        offset += (size_t)count;
    }
}
static void reply(void) {
    unsigned char header[128];
    transfer(response_fd, header, sizeof(header), 0);
    if (number(header) != 0x56415050 || header[4] != 10 || header[5]) fail("VAPP reply header");
    memcpy(state, header + 8, sizeof(state));
    byte_count = number(header + 124);
    if (byte_count > sizeof(bytes)) fail("VAPP reply size");
    transfer(response_fd, bytes, byte_count, 0);
}
static void command_data(unsigned kind, const void *payload, uint32_t length) {
    unsigned char header[136] = {0};
    uint32_t magic = 0x56415050, width = WINDOW_WIDTH, height = WINDOW_HEIGHT;
    memcpy(header, &magic, 4);
    header[4] = 10;
    header[5] = (unsigned char)kind;
    memcpy(header + 8, &width, 4);
    memcpy(header + 12, &height, 4);
    memcpy(header + 16, state, sizeof(state));
    memcpy(header + 132, &length, 4);
    transfer(request_fd, header, sizeof(header), 1);
    transfer(request_fd, (void *)payload, length, 1);
    reply();
    if (kind == 4) ++frame_count;
}
static void command(unsigned kind, const char *payload) {
    command_data(kind, payload, (uint32_t)strlen(payload));
}
static void ticks(unsigned count) {
    for (unsigned index = 0; index < count; ++index) command(4, "");
}
static void action(const char *name) { command(2, name); }
static void press(const char *name) { action(name); ticks(12); }
static void pointer(unsigned phase, int x, int y) {
    int32_t payload[7] = {(int32_t)phase, 1, 0, x, y, WINDOW_WIDTH, WINDOW_HEIGHT};
    command_data(5, payload, sizeof(payload));
}
static void toolbar(const char *name, int x, int y) {
    // The desktop sends both raw pointer events and the button's action.
    pointer(1, x, y);
    action(name);
    pointer(2, x, y);
}

static size_t parse(size_t offset, unsigned depth) {
    if (depth > 32 || offset + 274 > byte_count) fail("view element size");
    unsigned kind = bytes[offset];
    offset += 274;
    for (unsigned index = 0; index < 12; ++index) {
        if (offset + 4 > byte_count) fail("view string boundary");
        size_t length = number(bytes + offset);
        offset += 4;
        if (length > byte_count - offset) fail("view string size");
        if (kind == 2 && index == 3) {
            if (length >= sizeof(status_text)) fail("status label size");
            memcpy(status_text, bytes + offset, length);
            status_text[length] = 0;
        }
        static const char prefix[] = "vinix-surface:";
        if (index == 4 && length > sizeof(prefix) - 1 &&
                !memcmp(bytes + offset, prefix, sizeof(prefix) - 1)) {
            size_t path_length = length - (sizeof(prefix) - 1);
            if (path_length >= sizeof(surface_path)) fail("surface path size");
            memcpy(surface_path, bytes + offset + sizeof(prefix) - 1, path_length);
            surface_path[path_length] = 0;
        }
        offset += length;
    }
    if (offset + 8 > byte_count || number(bytes + offset)) fail("view menu boundary");
    unsigned children = number(bytes + offset + 4);
    offset += 8;
    if (children > 64) fail("view child count");
    for (unsigned index = 0; index < children; ++index) offset = parse(offset, depth + 1);
    return offset;
}
static void snapshot(uint32_t *destination) {
    unsigned active = __atomic_load_n(surface + 7, __ATOMIC_ACQUIRE);
    if (active > 1) fail("surface active buffer");
    __atomic_store_n(surface + 8, active, __ATOMIC_RELEASE);
    memcpy(destination, surface + 12 + active * PIXELS, PIXELS * 4);
    __atomic_store_n(surface + 8, UINT32_MAX, __ATOMIC_RELEASE);
}
static unsigned changed(const uint32_t *left, const uint32_t *right) {
    unsigned result = 0;
    for (unsigned index = 0; index < PIXELS; ++index) result += left[index] != right[index];
    return result;
}
static unsigned changed_court(const uint32_t *left, const uint32_t *right) {
    unsigned result = 0;
    // BEST persists across reset; deterministic gameplay excludes that HUD.
    for (unsigned index = WIDTH * 64; index < PIXELS; ++index) result += left[index] != right[index];
    return result;
}
static void inspect_frame(const uint32_t *frame, int homebrew) {
    unsigned lit = 0, distinct = 0, rdp_background = 0;
    unsigned char colors[4096] = {0};
    for (unsigned index = 0; index < PIXELS; ++index) {
        uint32_t color = frame[index];
        lit += (color & 0xffffff) != 0;
        unsigned red = (color >> 16) & 255, green = (color >> 8) & 255, blue = color & 255;
        rdp_background += red >= 4 && red <= 16 && green >= 8 && green <= 24 && blue >= 24 && blue <= 40;
        colors[((color >> 12) & 0xf00) | ((color >> 8) & 0xf0) | ((color >> 4) & 0xf)] = 1;
    }
    for (unsigned index = 0; index < sizeof(colors); ++index) distinct += colors[index];
    printf("N64-PIXELS: lit=%u colors=%u rdp-background=%u\n", lit, distinct, rdp_background);
    if (lit < PIXELS / 32 || distinct < 4) fail("Nintendo 64 did not draw a detailed game frame");
    if (homebrew && rdp_background < PIXELS / 3) fail("the real RDP did not clear the homebrew framebuffer");
}
static void export_frame(const uint32_t *frame) {
    // A quarter-size artifact is enough to review the game without saturating
    // the serial console. Assertions inspect the original 640x480 surface.
    static const char digits[] = "0123456789abcdef";
    char row[WIDTH / 4 * 6 + 2];
    printf("N64-FRAME: %u %u\n", WIDTH / 4, HEIGHT / 4);
    for (unsigned y = 0; y < HEIGHT; y += 4) {
        fputs("N64-ROW: ", stdout);
        for (unsigned x = 0; x < WIDTH; x += 4) {
            uint32_t color = frame[y * WIDTH + x];
            for (unsigned index = 0; index < 6; ++index)
                row[x / 4 * 6 + index] = digits[(color >> (20 - index * 4)) & 15];
        }
        row[sizeof(row) - 2] = '\n';
        row[sizeof(row) - 1] = 0;
        fputs(row, stdout);
    }
}
static void start(const char *game) {
    int requests[2], responses[2];
    if (pipe(requests) || pipe(responses)) fail("pipes");
    child = fork();
    if (child < 0) fail("fork");
    if (!child) {
        close(requests[1]);
        close(responses[0]);
        int log = open(log_path, O_CREAT | O_TRUNC | O_RDWR, 0600);
        if (log < 0 || dup2(log, 1) < 0 || dup2(log, 2) < 0) _exit(126);
        close(log);
        char input[32], output[32];
        snprintf(input, sizeof(input), "%d", requests[0]);
        snprintf(output, sizeof(output), "%d", responses[1]);
        setenv("VINIX_REQUEST_FD", input, 1);
        setenv("VINIX_RESPONSE_FD", output, 1);
        setenv("VINIX_N64_DATA", "/opt/n64/data", 1);
        if (game) execl("/usr/bin/vinix-n64", "vinix-n64", "--mute", game, (char *)NULL);
        else execl("/usr/bin/vinix-n64", "vinix-n64", "--mute", (char *)NULL);
        _exit(127);
    }
    close(requests[0]);
    close(responses[1]);
    request_fd = requests[1];
    response_fd = responses[0];
    frame_count = 0;
    memset(state, 0, sizeof(state));
    reply();
    command(1, "");
    surface_path[0] = 0;
    if (parse(0, 0) != byte_count || !surface_path[0]) fail("shared surface view missing");
    int fd = open(surface_path, O_RDWR);
    struct stat info;
    if (fd < 0 || fstat(fd, &info) || info.st_size != SURFACE_BYTES) fail("surface file size");
    surface = mmap(NULL, SURFACE_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    if (surface == MAP_FAILED || surface[0] != 0x31534656 || surface[1] != 1 || surface[2] != 48 ||
            surface[3] != WIDTH || surface[4] != HEIGHT || surface[5] != WIDTH * 4 || surface[6] != 1)
        fail("VSF1 header");
}
static void stop(void) {
    command(6, "");
    close(request_fd);
    close(response_fd);
    int status = 0;
    int reaped = 0;
    for (unsigned attempt = 0; attempt < 500; ++attempt) {
        pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child) { reaped = 1; break; }
        if (result < 0 && errno != EINTR) fail("application waitpid");
        usleep(10000);
    }
    if (!reaped || !WIFEXITED(status) || WEXITSTATUS(status)) fail("application clean shutdown");
    if (munmap(surface, SURFACE_BYTES)) fail("surface munmap");
    if (!access(surface_path, F_OK)) fail("surface file leaked");
    print_log();
}

static void begin_paddle(void) {
    // N64 code copies its program through PI, initializes VI and reads SRAM.
    ticks(2);
    press("start");
}

static void rejected_open(const char *path, const char *message) {
    action("open");
    command(3, path);
    command(3, "\n");
    command(1, "");
    status_text[0] = 0;
    if (parse(0, 0) != byte_count || !strstr(status_text, message)) {
        printf("N64-STATUS: %s\n", status_text);
        fail("Open game did not explain rejected content");
    }
}
static void test_rejected_content(void) {
    // Neither a magic-only image nor an unsupported byte order may replace
    // the current machine. These are independent ROM-validation failures.
    static const unsigned char invalid[] = {0x80, 0x37, 0x12, 0x40, 0, 0, 0};
    int fd = open("/opt/n64/truncated.z64", O_CREAT | O_TRUNC | O_WRONLY, 0600);
    if (fd < 0 || write(fd, invalid, sizeof(invalid)) != sizeof(invalid)) fail("truncated ROM fixture");
    close(fd);
    fd = open("/opt/n64/bad-header.z64", O_CREAT | O_TRUNC | O_WRONLY, 0600);
    if (fd < 0 || ftruncate(fd, 0x100000)) fail("invalid ROM header fixture");
    close(fd);
    action("pause");
    snapshot(first);
    rejected_open("/opt/n64/truncated.z64", "ROM");
    rejected_open("/opt/n64/bad-header.z64", "header");
    ticks(4);
    snapshot(last);
    if (changed(first, last)) fail("failed Open ROM lost the paused game");
    action("pause");
    ticks(8);
    snapshot(last);
    if (changed(first, last) < 16) fail("failed Open ROM could not resume the previous game");
    snapshot(first);
    rejected_open("/opt/n64/missing.z64", "path");
    ticks(8);
    snapshot(last);
    if (changed(first, last) < 16) fail("missing ROM request stopped the previous running game");
    puts("N64 PASS: rejected content preserves the running game and pause state");
}

static int read_sram(int fd, uint32_t values[4]) {
    unsigned char raw[16];
    if (pread(fd, raw, sizeof(raw), 133120) != sizeof(raw)) return 0;
    // parallel-n64's packed save uses little-endian words on ARM64: its SRAM
    // DMA copies RDRAM's internal word-swapped bytes without conversion.
    for (unsigned i = 0; i < 4; ++i)
        values[i] = raw[i * 4] | ((uint32_t)raw[i * 4 + 1] << 8) |
                    ((uint32_t)raw[i * 4 + 2] << 16) | ((uint32_t)raw[i * 4 + 3] << 24);
    return 1;
}
static int write_sram(int fd, const uint32_t values[4]) {
    unsigned char raw[16];
    for (unsigned i = 0; i < 4; ++i)
        for (unsigned j = 0; j < 4; ++j) raw[i * 4 + j] = (unsigned char)(values[i] >> (j * 8));
    return pwrite(fd, raw, sizeof(raw), 133120) == sizeof(raw) && !fsync(fd);
}
static void test_sram(void) {
    static const char game[] = "/usr/share/games/n64/paddle.z64";
    uint32_t hash = 2166136261u;
    for (unsigned index = 0; game[index]; ++index) hash = (hash ^ (unsigned char)game[index]) * 16777619u;
    char path[256];
    snprintf(path, sizeof(path), "/opt/n64/data/saves/paddle.z64-%08x.sav", hash);
    struct stat info;
    if (stat(path, &info) || info.st_size != 296960)
        fail("N64 save file geometry");
    // The real R4300 wrote this record through PI DMA. Change BEST, then
    // require a fresh machine to read it before writing an incremented game
    // count. This proves both cartridge SRAM reads and writes.
    uint32_t record[4];
    int fd = open(path, O_RDWR);
    if (fd < 0 || !read_sram(fd, record) ||
            record[0] != 0x4e504144 || !record[2] ||
            record[3] != (record[0] ^ record[1] ^ record[2])) fail("game did not write its cartridge SRAM through PI");
    uint32_t games = record[2];
    record[1] = 42;
    record[3] = record[0] ^ record[1] ^ record[2];
    if (!write_sram(fd, record)) fail("cartridge SRAM fixture write");
    close(fd);
    start(NULL);
    begin_paddle();
    snapshot(last);
    inspect_frame(last, 1);
    stop();
    fd = open(path, O_RDONLY);
    if (fd < 0 || !read_sram(fd, record) ||
            record[0] != 0x4e504144 || record[1] != 42 || record[2] != games + 1 ||
            record[3] != (record[0] ^ record[1] ^ record[2])) fail("fresh N64 process did not load and update its PI SRAM save");
    close(fd);
    puts("N64 PASS: cartridge SRAM survives a fresh emulator process");
}
static void test_rom_formats(void) {
    const char *paths[] = {"/opt/n64/paddle.v64", "/opt/n64/paddle.n64"};
    for (unsigned i = 0; i < sizeof(paths) / sizeof(paths[0]); ++i) {
        start(paths[i]);
        begin_paddle();
        snapshot(first);
        inspect_frame(first, 1);
        ticks(8);
        snapshot(last);
        if (changed(first, last) < 16) fail("converted ROM did not run and animate");
        stop();
    }
    puts("N64 PASS: byte-swapped and word-swapped ROM formats boot real code");
}
static void test_instruction_limit(void) {
    // A structurally valid cartridge can still execute an endless boot loop.
    // Its bounded failure must reply over VAPP and permit another cartridge.
    start("/opt/n64/budget.z64");
    ticks(1);
    command(1, "");
    status_text[0] = 0;
    if (parse(0, 0) != byte_count || !strstr(status_text, "instruction limit")) {
        printf("N64-STATUS: %s\n", status_text);
        fail("stalled boot code did not report its instruction limit");
    }
    ticks(2);
    action("open");
    command(3, "/usr/share/games/n64/paddle.z64");
    command(3, "\n");
    begin_paddle();
    snapshot(first);
    inspect_frame(first, 1);
    ticks(8);
    snapshot(last);
    if (changed(first, last) < 16) fail("emulator did not recover after its instruction limit");
    stop();
    puts("N64 PASS: stalled boot code hits its instruction limit and recovers");
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    signal(SIGPIPE, SIG_IGN);
    start(NULL);
    begin_paddle();
    snapshot(first);
    inspect_frame(first, 1);
    export_frame(first);
    ticks(8);
    snapshot(last);
    unsigned animated = changed(first, last);
    printf("N64-GAMEPLAY: animated=%u\n", animated);
    if (animated < 16) fail("running Nintendo 64 game did not animate");
    puts("N64 PASS: native emulator boots Nintendo 64 code and publishes real frames");

    // At equal emulated ages, the ordinary game must draw a different board
    // after controller input. Animation alone cannot satisfy this check.
    action("reset");
    begin_paddle();
    ticks(20);
    snapshot(neutral);
    action("reset");
    begin_paddle();
    pointer(1, 352, 613); // Right: the actual desktop controller button.
    action("n64.right");
    ticks(12);
    pointer(2, 352, 613);
    ticks(8);
    snapshot(last);
    unsigned moved = changed(neutral, last);
    printf("N64-CONTROLLER: equal-age input changed=%u\n", moved);
    if (moved < 16) fail("controller did not change the emulated game");
    puts("N64 PASS: controller input changes the emulated game");
    export_frame(last);
    memcpy(controlled, last, sizeof(controlled));

    action("reset");
    begin_paddle();
    action("stick_right");
    ticks(20);
    snapshot(last);
    unsigned analog = changed_court(neutral, last);
    printf("N64-ANALOG: equal-age input changed=%u\n", analog);
    if (analog < 16) fail("analog stick did not change the emulated game");
    puts("N64 PASS: analog stick reaches the emulated controller");

    action("reset");
    begin_paddle();
    // A single native text payload may contain multiple terminal sequences.
    // It must move exactly as the pointer-held D-pad at the same frame age;
    // interpreting an embedded Escape as pause cannot satisfy equality.
    command(3, "\x1b[C\x1b[C");
    ticks(20);
    snapshot(last);
    if (changed_court(controlled, last)) fail("batched arrow keys did not match the real D-pad");
    action("reset");
    begin_paddle();
    command(3, "dd");
    ticks(20);
    snapshot(last);
    if (changed_court(controlled, last)) fail("batched WASD keys did not match the analog stick");
    puts("N64 PASS: batched arrow and WASD input stays running and moves the game");

    toolbar("n64.pause", 184, 575);
    snapshot(first);
    action("open");
    command(3, "\x1b"); // Cancelling Open game must preserve the paused state.
    ticks(4);
    snapshot(last);
    if (changed(first, last)) fail("emulation drew while paused");
    toolbar("n64.pause", 184, 575);
    ticks(8);
    snapshot(last);
    if (changed(first, last) < 16) fail("emulation did not resume");
    puts("N64 PASS: pause freezes emulation and resume produces new frames");

    action("reset");
    begin_paddle();
    ticks(20);
    snapshot(last);
    if (changed_court(neutral, last)) fail("reset did not reproduce the game's initial state");
    test_rejected_content();
    stop();
    puts("N64 PASS: reset restarts the game and close releases the native surface");
    test_sram();
    test_rom_formats();
    test_instruction_limit();

    FILE *game = fopen("/opt/n64/game-path", "r");
    if (game) {
        char path[4096];
        if (!fgets(path, sizeof(path), game)) fail("supplied game path");
        fclose(game);
        path[strcspn(path, "\r\n")] = 0;
        start(path);
        ticks(180);
        press("start");
        press("a");
        ticks(60);
        snapshot(last);
        inspect_frame(last, 0);
        export_frame(last);
        stop();
        puts("N64 PASS: supplied game rendered and shut down cleanly");
    }
    puts("VINIX N64 GUEST: PASS");
    for (;;) pause();
}
