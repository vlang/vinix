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
static uint32_t first[PIXELS], last[PIXELS], neutral[PIXELS];
static pid_t child;
static const char *log_path = "/tmp/ps2-emulator.log";
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
    printf("PS2 FAIL: %s (poll frame %u)\n", reason, frame_count);
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
static void inspect_frame(const uint32_t *frame) {
    unsigned lit = 0, distinct = 0;
    unsigned char colors[4096] = {0};
    for (unsigned index = 0; index < PIXELS; ++index) {
        uint32_t color = frame[index];
        lit += (color & 0xffffff) != 0;
        colors[((color >> 12) & 0xf00) | ((color >> 8) & 0xf0) | ((color >> 4) & 0xf)] = 1;
    }
    for (unsigned index = 0; index < sizeof(colors); ++index) distinct += colors[index];
    printf("PS2-PIXELS: lit=%u colors=%u\n", lit, distinct);
    if (lit < PIXELS / 32 || distinct < 4) fail("PlayStation did not draw a detailed game frame");
}
static void export_frame(const uint32_t *frame) {
    // A quarter-size artifact is enough to review the game without saturating
    // the serial console. Assertions inspect the original 640x480 surface.
    static const char digits[] = "0123456789abcdef";
    char row[WIDTH / 4 * 6 + 2];
    printf("PS2-FRAME: %u %u\n", WIDTH / 4, HEIGHT / 4);
    for (unsigned y = 0; y < HEIGHT; y += 4) {
        fputs("PS2-ROW: ", stdout);
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
        setenv("VINIX_PS2_DATA", "/opt/ps2/data", 1);
        if (game) execl("/usr/bin/vinix-ps2", "vinix-ps2", "--mute", game, (char *)NULL);
        else execl("/usr/bin/vinix-ps2", "vinix-ps2", "--mute", (char *)NULL);
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
    // PS2 code boots both processors, initializes GS and reads its memory card.
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
        printf("PS2-STATUS: %s\n", status_text);
        fail("Open game did not explain rejected content");
    }
}
static void test_rejected_content(void) {
    // A magic-only ELF must never be allowed to reach the emulated loader.
    static const unsigned char invalid[] = {0x7f, 'E', 'L', 'F', 1, 1, 1};
    int fd = open("/opt/ps2/truncated.elf", O_CREAT | O_TRUNC | O_WRONLY, 0600);
    if (fd < 0 || write(fd, invalid, sizeof(invalid)) != sizeof(invalid)) fail("malformed ELF fixture");
    close(fd);
    // A complete executable header with a LOAD segment crossing the PS2's
    // 32 MiB RAM boundary must be rejected before touching a running machine.
    unsigned char oversized[84] = {0x7f, 'E', 'L', 'F', 1, 1, 1, 0x56};
    uint16_t type = 2, machine = 8, header_size = 52, entry_size = 32, entries = 1;
    uint32_t version = 1, entry = 0x00100000, headers = 52;
    memcpy(oversized + 16, &type, 2); memcpy(oversized + 18, &machine, 2);
    memcpy(oversized + 20, &version, 4); memcpy(oversized + 24, &entry, 4);
    memcpy(oversized + 28, &headers, 4); memcpy(oversized + 40, &header_size, 2);
    memcpy(oversized + 42, &entry_size, 2); memcpy(oversized + 44, &entries, 2);
    uint32_t segment[8] = {1, sizeof(oversized), 0x01fff000, 0x01fff000, 0, 8192, 5, 16};
    memcpy(oversized + 52, segment, sizeof(segment));
    fd = open("/opt/ps2/outside-ram.elf", O_CREAT | O_TRUNC | O_WRONLY, 0600);
    if (fd < 0 || write(fd, oversized, sizeof(oversized)) != sizeof(oversized)) fail("out-of-range ELF fixture");
    close(fd);
    action("pause");
    snapshot(first);
    rejected_open("/opt/ps2/truncated.elf", "ELF");
    rejected_open("/opt/ps2/outside-ram.elf", "RAM");
    ticks(4);
    snapshot(last);
    if (changed(first, last)) fail("failed Open game lost the paused game");
    action("pause");
    ticks(8);
    snapshot(last);
    if (changed(first, last) < 16) fail("failed Open game could not resume the previous game");

    // Even with a supplied BIOS staged for the optional game, hide it for this
    // one check. No existing desktop data is touched: this VM is disposable.
    int had_bios = !rename("/opt/ps2/data/bios/ps2.bin", "/opt/ps2/data/bios/ps2.bin.saved");
    fd = open("/opt/ps2/firmware-required.iso", O_CREAT | O_TRUNC | O_WRONLY, 0600);
    if (fd < 0 || ftruncate(fd, 32768)) fail("disc fixture");
    close(fd);
    snapshot(first);
    rejected_open("/opt/ps2/firmware-required.iso", "BIOS");
    ticks(8);
    snapshot(last);
    if (changed(first, last) < 16) fail("missing BIOS request stopped the previous running game");
    if (had_bios && rename("/opt/ps2/data/bios/ps2.bin.saved", "/opt/ps2/data/bios/ps2.bin")) fail("BIOS fixture restore");
    puts("PS2 PASS: rejected content preserves the running game and pause state");
}

static void test_card(void) {
    static const char game[] = "/usr/share/games/ps2/paddle.elf";
    uint32_t hash = 2166136261u;
    for (unsigned index = 0; game[index]; ++index) hash = (hash ^ (unsigned char)game[index]) * 16777619u;
    char path[256];
    snprintf(path, sizeof(path), "/opt/ps2/data/saves/paddle.elf-%08x.ps2", hash);
    struct stat info;
    if (stat(path, &info) || info.st_size != 16384 * 528)
        fail("PS2 memory card geometry");
    // The real IOP wrote this record through SIO2, rather than through a host
    // save hook. Change BEST, then require the next IOP to preserve it when it
    // saves an incremented game count. This proves both PS2 reads and writes.
    uint32_t record[4];
    int fd = open(path, O_RDWR);
    if (fd < 0 || pread(fd, record, sizeof(record), 16 * 528) != sizeof(record) ||
            record[0] != 0x44415056 || !record[2] ||
            record[3] != (record[0] ^ record[1] ^ record[2])) fail("game did not write its memory card through SIO2");
    uint32_t games = record[2];
    record[1] = 42;
    record[3] = record[0] ^ record[1] ^ record[2];
    if (pwrite(fd, record, sizeof(record), 16 * 528) != sizeof(record) || fsync(fd)) fail("memory card fixture write");
    close(fd);
    start(NULL);
    begin_paddle();
    snapshot(last);
    inspect_frame(last);
    stop();
    fd = open(path, O_RDONLY);
    if (fd < 0 || pread(fd, record, sizeof(record), 16 * 528) != sizeof(record) ||
            record[0] != 0x44415056 || record[1] != 42 || record[2] != games + 1 ||
            record[3] != (record[0] ^ record[1] ^ record[2])) fail("fresh PS2 process did not load and update its SIO2 save");
    close(fd);
    puts("PS2 PASS: memory card survives a fresh emulator process");
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    signal(SIGPIPE, SIG_IGN);
    start(NULL);
    begin_paddle();
    snapshot(first);
    inspect_frame(first);
    export_frame(first);
    ticks(8);
    snapshot(last);
    unsigned animated = changed(first, last);
    printf("PS2-GAMEPLAY: animated=%u\n", animated);
    if (animated < 16) fail("running PlayStation game did not animate");
    puts("PS2 PASS: native emulator boots PlayStation code and publishes real frames");

    // At equal emulated ages, the ordinary game must draw a different board
    // after controller input. Animation alone cannot satisfy this check.
    action("reset");
    begin_paddle();
    ticks(20);
    snapshot(neutral);
    action("reset");
    begin_paddle();
    pointer(1, 348, 613); // Right: the actual desktop controller button.
    action("ps2.right");
    ticks(12);
    pointer(2, 348, 613);
    ticks(8);
    snapshot(last);
    unsigned moved = changed(neutral, last);
    printf("PS2-CONTROLLER: equal-age input changed=%u\n", moved);
    if (moved < 16) fail("controller did not change the emulated game");
    puts("PS2 PASS: controller input changes the emulated game");
    export_frame(last);

    toolbar("ps2.pause", 184, 575);
    snapshot(first);
    action("open");
    command(3, "\x1b"); // Cancelling Open game must preserve the paused state.
    ticks(4);
    snapshot(last);
    if (changed(first, last)) fail("emulation drew while paused");
    toolbar("ps2.pause", 184, 575);
    ticks(8);
    snapshot(last);
    if (changed(first, last) < 16) fail("emulation did not resume");
    puts("PS2 PASS: pause freezes emulation and resume produces new frames");

    action("reset");
    begin_paddle();
    ticks(20);
    snapshot(last);
    if (changed(neutral, last)) fail("reset did not reproduce the game's initial state");
    test_rejected_content();
    stop();
    puts("PS2 PASS: reset restarts the game and close releases the native surface");
    test_card();

    FILE *game = fopen("/opt/ps2/game-path", "r");
    if (game) {
        char path[4096];
        if (!fgets(path, sizeof(path), game)) fail("supplied game path");
        fclose(game);
        path[strcspn(path, "\r\n")] = 0;
        start(path);
        ticks(180);
        press("start");
        press("cross");
        ticks(60);
        snapshot(last);
        inspect_frame(last);
        export_frame(last);
        stop();
        puts("PS2 PASS: supplied game rendered and shut down cleanly");
    }
    puts("VINIX PS2 GUEST: PASS");
    for (;;) pause();
}
