// SPDX-License-Identifier: GPL-2.0-or-later
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static int request_fd, response_fd;
static unsigned char state[116], bytes[65536];
static size_t byte_count;
static const char *log_path;
static char image[256], action[64];
static int expected_audio_failure;
static int startup_failed;
static pid_t ui_child;

static int audio_failure(void) {
    int status;
    if (waitpid(ui_child, &status, 0) != ui_child || !WIFEXITED(status) || WEXITSTATUS(status) != 1) return 0;
    FILE *log = fopen(log_path, "r");
    char diagnostics[16384] = {0};
    if (!log || fread(diagnostics, 1, sizeof(diagnostics) - 1, log) == sizeof(diagnostics) - 1) return 0;
    fclose(log);
    if (!strstr(diagnostics, "SceneDelegate: Launching PPSSPP") ||
        !strstr(diagnostics, "unimplemented Objective-C method AVAudioSession setCategory:error:")) return 0;
    puts("iOS BLOCKED: PPSSPP graphics startup passed; AVAudioSession audio activation is unsupported");
    startup_failed = 1;
    return 1;
}

static void fail(const char *reason) {
    FILE *log = fopen(log_path, "r");
    if (log) { char chunk[512]; while (fgets(chunk, sizeof(chunk), log)) fputs(chunk, stdout); fclose(log); }
    printf("iOS FAIL: graphics UI %s\n", reason);
    fflush(stdout);
    for (;;) pause();
}
static uint32_t number(const void *pointer) { uint32_t value; memcpy(&value, pointer, 4); return value; }
static void transfer(int fd, void *pointer, size_t length, int writing) {
    size_t offset = 0;
    while (offset < length) {
        ssize_t count = writing ? write(fd, (char *)pointer + offset, length - offset) :
            read(fd, (char *)pointer + offset, length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) {
            if (!writing && expected_audio_failure && audio_failure()) return;
            fail("application pipe closed");
        }
        offset += (size_t)count;
    }
}
static void reply(void) {
    unsigned char header[128] = {0};
    transfer(response_fd, header, sizeof(header), 0);
    if (startup_failed) return;
    if (number(header) != 0x56415050 || header[4] != 10 || header[5]) fail("reply header");
    memcpy(state, header + 8, sizeof(state));
    byte_count = number(header + 124);
    if (byte_count > sizeof(bytes)) fail("reply size");
    transfer(response_fd, bytes, byte_count, 0);
}
static void command_data(unsigned kind, const void *payload, uint32_t length) {
    unsigned char header[136] = {0};
    uint32_t magic = 0x56415050, width = 390, height = 680;
    memcpy(header, &magic, 4); header[4] = 10; header[5] = (unsigned char)kind;
    memcpy(header + 8, &width, 4); memcpy(header + 12, &height, 4);
    memcpy(header + 16, state, sizeof(state)); memcpy(header + 132, &length, 4);
    transfer(request_fd, header, sizeof(header), 1);
    transfer(request_fd, (void *)payload, length, 1);
    reply();
}
static void command(unsigned kind, const char *payload) { command_data(kind, payload, (uint32_t)strlen(payload)); }
static void pointer(unsigned phase, int x, int y) {
    int32_t payload[7] = {(int32_t)phase, 1, 0, x, y, 390, 680};
    command_data(5, payload, sizeof(payload));
}
static pid_t start(const char *path, const char *logfile) {
    log_path = logfile;
    startup_failed = 0;
    int requests[2], responses[2];
    if (pipe(requests) || pipe(responses)) fail("pipes");
    pid_t child = fork();
    if (child < 0) fail("fork");
    if (!child) {
        close(requests[1]); close(responses[0]);
        int log = open(logfile, O_CREAT | O_TRUNC | O_RDWR, 0600);
        if (log < 0 || dup2(log, 1) < 0 || dup2(log, 2) < 0) _exit(126);
        close(log);
        char input[32], output[32];
        snprintf(input, sizeof(input), "%d", requests[0]);
        snprintf(output, sizeof(output), "%d", responses[1]);
        setenv("VINIX_REQUEST_FD", input, 1); setenv("VINIX_RESPONSE_FD", output, 1);
        if (!strcmp(path, "/opt/ios/PPSSPP")) {
            setenv("VINIX_IOS_DOCUMENTS", "/opt/ios/ppsspp-documents", 1);
            setenv("VINIX_IOS_EXIT_ON_CLOSE", "1", 1);
            if (!access("/opt/ios/ppsspp-muted", F_OK)) {
                if (!access("/opt/ios/ppsspp-cube", F_OK))
                    execl("/usr/bin/vinix-ios-ppsspp", "vinix-ios-ppsspp", "/opt/ios/cube.pbp", (char *)NULL);
                else execl("/usr/bin/vinix-ios-ppsspp", "vinix-ios-ppsspp", (char *)NULL);
                _exit(127);
            }
        }
        execl("/opt/ios/run-ios", "run-ios", path, (char *)NULL);
        _exit(127);
    }
    close(requests[0]); close(responses[1]);
    request_fd = requests[1]; response_fd = responses[0];
    ui_child = child;
    reply();
    return child;
}
static size_t parse(size_t offset, unsigned depth) {
    if (depth > 32 || offset + 274 > byte_count) fail("element size");
    unsigned kind = bytes[offset]; offset += 274;
    for (unsigned index = 0; index < 12; ++index) {
        if (offset + 4 > byte_count) fail("string bounds");
        size_t length = number(bytes + offset); offset += 4;
        if (length > byte_count - offset) fail("string size");
        if (kind == 3 && index == 4 && length > 14 && length < sizeof(image) &&
            !memcmp(bytes + offset, "vinix-surface:", 14)) {
            memcpy(image, bytes + offset + 14, length - 14); image[length - 14] = 0;
        }
        if (kind == 4 && index == 0 && length && length < sizeof(action)) {
            memcpy(action, bytes + offset, length); action[length] = 0;
        }
        offset += length;
    }
    if (offset + 8 > byte_count || number(bytes + offset)) fail("element menu");
    unsigned children = number(bytes + offset + 4); offset += 8;
    if (children > 64) fail("element children");
    for (unsigned index = 0; index < children; ++index) offset = parse(offset, depth + 1);
    return offset;
}
static void build(void) {
    command(1, ""); image[0] = 0; action[0] = 0;
    if (parse(0, 0) != byte_count || !image[0]) fail("shared surface view missing");
}
void test_gles_ui(void) {
    pid_t child = start("/opt/ios/gles-app", "/tmp/ios-gles-app.log");
    build();
    if (!action[0]) fail("pause action missing");
    pointer(1, 9, 11); pointer(2, 9, 11);
    int fd = open(image, O_RDWR);
    struct stat info;
    if (fd < 0 || fstat(fd, &info) || info.st_size != 48 + 32 * 24 * 8) fail("surface file");
    uint32_t *surface = mmap(NULL, (size_t)info.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    if (surface == MAP_FAILED || surface[0] != 0x31534656 || surface[1] != 1 || surface[2] != 48 ||
        surface[3] != 32 || surface[4] != 24 || surface[5] != 128 || surface[6] != 1) fail("VSF1 header");
    uint32_t active = __atomic_load_n(surface + 7, __ATOMIC_ACQUIRE);
    if (active > 1) fail("surface active buffer");
    uint32_t pixel = surface[12 + active * 32 * 24];
    if ((pixel & 0xffff00ff) != 0xffff0000) fail("native GL clear color in XRGB surface");
    __atomic_store_n(surface + 8, active, __ATOMIC_RELEASE);
    usleep(40000); command(4, "");
    if (__atomic_load_n(surface + 7, __ATOMIC_ACQUIRE) != (active ^ 1)) fail("surface publication");
    usleep(40000); command(4, "");
    if (__atomic_load_n(surface + 7, __ATOMIC_ACQUIRE) != (active ^ 1) ||
        surface[12 + active * 32 * 24] != pixel) fail("producer overwrote claimed reader");
    __atomic_store_n(surface + 8, UINT32_MAX, __ATOMIC_RELEASE);
    usleep(40000); command(4, "");
    if (__atomic_load_n(surface + 7, __ATOMIC_ACQUIRE) != active) fail("surface publication after reader released");
    command(2, action); // Pause: action may allow one pending tick before setting paused.
    uint32_t before[32 * 24 * 2 + 12];
    memcpy(before, surface, sizeof(before));
    for (unsigned index = 0; index < 3; ++index) { usleep(40000); command(4, ""); }
    if (memcmp(before, surface, sizeof(before))) fail("display link drew while paused");
    command(2, action);
    usleep(40000); command(4, "");
    if (memcmp(before, surface, sizeof(before)) == 0) fail("display link did not resume");
    command(6, ""); close(request_fd); close(response_fd);
    int status;
    if (waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status)) fail("application teardown");
    munmap(surface, (size_t)info.st_size);
    if (access(image, F_OK) == 0) fail("surface file leaked");
    FILE *log = fopen(log_path, "r");
    char diagnostics[2048] = {0};
    if (!log || fread(diagnostics, 1, sizeof(diagnostics) - 1, log) == sizeof(diagnostics) - 1) fail("application diagnostics");
    fclose(log);
    if (!strstr(diagnostics, "IOS-GLES-APP: main queue, display link timing/pause and native drawing callbacks") ||
        strstr(diagnostics, "still owned") || strstr(diagnostics, "V panic")) fail("native callbacks/ownership");
    puts("iOS PASS: display links, main queue and desktop shared-surface presentation");
}

void test_ppsspp_ui(void) {
    int cube = access("/opt/ios/ppsspp-cube", F_OK) == 0;
    expected_audio_failure = access("/opt/ios/ppsspp-muted", F_OK) != 0;
    (void)start("/opt/ios/PPSSPP", "/tmp/ios-ppsspp-ui.log");
    if (expected_audio_failure) {
        if (!startup_failed) fail("default PPSSPP did not report its expected audio API failure");
        close(request_fd); close(response_fd); return;
    }
    build();
    if (access("/opt/ios/ppsspp-documents/PSP/SYSTEM/ppsspp.ini", R_OK)) fail("PPSSPP launcher preferences");
    int fd = open(image, O_RDWR);
    struct stat info;
    if (fd < 0 || fstat(fd, &info) || info.st_size != 48 + 390 * 680 * 8) fail("PPSSPP framebuffer size");
    uint32_t *surface = mmap(NULL, (size_t)info.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    if (surface == MAP_FAILED || surface[0] != 0x31534656 || surface[3] != 390 || surface[4] != 680) fail("PPSSPP surface header");
    unsigned pixels = 390 * 680;
    uint32_t *first = malloc(pixels * 4), *last = malloc(pixels * 4);
    if (!first || !last) fail("PPSSPP framebuffer allocation");
    unsigned active = __atomic_load_n(surface + 7, __ATOMIC_ACQUIRE);
    if (active > 1) fail("PPSSPP surface active buffer");
    __atomic_store_n(surface + 8, active, __ATOMIC_RELEASE);
    memcpy(first, surface + 12 + active * pixels, pixels * 4);
    __atomic_store_n(surface + 8, UINT32_MAX, __ATOMIC_RELEASE);
    for (unsigned tick = 0; tick < 180; ++tick) { usleep(20000); command(4, ""); }
    if (cube) {
        // Compare two frames after boot, so the splash-to-game transition
        // alone cannot count as successful PSP execution or animation.
        active = __atomic_load_n(surface + 7, __ATOMIC_ACQUIRE);
        if (active > 1) fail("PSP cube baseline buffer");
        __atomic_store_n(surface + 8, active, __ATOMIC_RELEASE);
        memcpy(first, surface + 12 + active * pixels, pixels * 4);
        __atomic_store_n(surface + 8, UINT32_MAX, __ATOMIC_RELEASE);
    }
    // The original menu's Settings gear: route a real UIKit touch pair to its
    // native controller, then render the resulting settings screen.
    if (!cube) { pointer(1, 230, 34); pointer(2, 230, 34); }
    for (unsigned tick = 0; tick < 60; ++tick) { usleep(20000); command(4, ""); }
    active = __atomic_load_n(surface + 7, __ATOMIC_ACQUIRE);
    if (active > 1) fail("PPSSPP final active buffer");
    __atomic_store_n(surface + 8, active, __ATOMIC_RELEASE);
    memcpy(last, surface + 12 + active * pixels, pixels * 4);
    __atomic_store_n(surface + 8, UINT32_MAX, __ATOMIC_RELEASE);
    unsigned changed = 0, lit = 0;
    unsigned char colors[4096] = {0};
    for (unsigned index = 0; index < pixels; ++index) {
        uint32_t color = last[index];
        if (color != first[index]) ++changed;
        if ((color & 0xffffff) != 0) ++lit;
        colors[((color >> 12) & 0xf00) | ((color >> 8) & 0xf0) | ((color >> 4) & 0xf)] = 1;
    }
    unsigned distinct = 0;
    for (unsigned index = 0; index < sizeof(colors); ++index) distinct += colors[index];
    if ((!cube && changed < 1000) || lit < pixels / 4 || distinct < 16) fail("PPSSPP native scene did not render changing detailed pixels");
    if (cube) {
        unsigned background[2] = {0}, colored[2] = {0}, animated = 0;
        for (unsigned y = 80; y < 240; ++y) for (unsigned x = 80; x < 310; ++x) {
            unsigned index = y * 390 + x;
            uint32_t frames[2] = {first[index], last[index]};
            if (frames[0] != frames[1]) ++animated;
            for (unsigned frame = 0; frame < 2; ++frame) {
                uint32_t color = frames[frame] & 0xffffff;
                if (color == 0x334455) ++background[frame]; // Demo's sceGuClearColor(0xff554433), ABGR.
                unsigned r = color >> 16, g = (color >> 8) & 255, b = color & 255;
                unsigned high = r > g ? r : g, low = r < g ? r : g;
                if (b > high) high = b;
                if (b < low) low = b;
                if (high > 150 && high - low > 50) ++colored[frame];
            }
        }
        printf("IOS-PSP-CUBE: background=%u/%u colored=%u/%u animated=%u\n",
            background[0], background[1], colored[0], colored[1], animated);
        if (background[0] < 2000 || background[1] < 2000 || colored[0] < 2000 ||
            colored[1] < 2000 || animated < 1000) fail("PSP cube background, textured geometry or animation");
    }
    // Export an actual framebuffer for visual review, sampled at two pixels.
    puts("IOS-PPSSPP-FRAME: 195 340");
    for (unsigned y = 0; y < 680; y += 2) {
        fputs("IOS-PPSSPP-ROW: ", stdout);
        for (unsigned x = 0; x < 390; x += 2) printf("%06x", last[y * 390 + x] & 0xffffff);
        putchar('\n');
    }
    printf("IOS-PPSSPP-PIXELS: changed=%u lit=%u colors=%u\n", changed, lit, distinct);
    free(first); free(last);
    command(6, ""); close(request_fd); close(response_fd);
    int status;
    if (waitpid(ui_child, &status, 0) != ui_child || !WIFEXITED(status) || WEXITSTATUS(status)) fail("PPSSPP process lifecycle");
    munmap(surface, (size_t)info.st_size);
    if (access(image, F_OK) == 0) fail("PPSSPP shared surface leaked");
    FILE *log = fopen(log_path, "r");
    char diagnostics[32768] = {0};
    if (!log || fread(diagnostics, 1, sizeof(diagnostics) - 1, log) == sizeof(diagnostics) - 1) fail("PPSSPP diagnostics");
    fclose(log);
    if (!strstr(diagnostics, "SceneDelegate: Launching PPSSPP") || !strstr(diagnostics, "RobotoCondensed-Regular") ||
        strstr(diagnostics, "V panic") || strstr(diagnostics, "terminate called")) fail("PPSSPP native startup/lifecycle");
    if (cube) {
        if (!strstr(diagnostics, "startup path passed to argv: /opt/ios/cube.pbp") ||
            !strstr(diagnostics, "Booted /opt/ios/cube.pbp...")) fail("PSP homebrew native boot");
        puts("iOS PASS: unchanged PPSSPP iOS binary executes PSP cube homebrew");
    }
    puts("iOS PASS: upstream PPSSPP native framebuffer and process lifecycle (muted)");
}
