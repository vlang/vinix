/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static void die(const char *why) { printf("iOS FAIL: UIKit %s\n", why); fflush(stdout); for (;;) pause(); }
static void transfer(int fd, void *data, size_t length, int writing) {
    size_t done = 0;
    while (done < length) {
        ssize_t count = writing ? write(fd, (char *)data+done, length-done) : read(fd, (char *)data+done, length-done);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) die("pipe closed");
        done += (size_t)count;
    }
}
static uint32_t number(const unsigned char *p) { uint32_t n; memcpy(&n, p, 4); return n; }
static unsigned char state[116], bytes[65536];
static int input, output;
static size_t reply(void) {
    unsigned char header[128]; transfer(output, header, sizeof(header), 0);
    if (number(header) != 0x56415050 || header[4] != 10 || header[5]) die("response header");
    memcpy(state, header+8, sizeof(state));
    size_t length = number(header+124);
    if (length > sizeof(bytes)) die("response size");
    transfer(output, bytes, length, 0);
    return length;
}
static size_t command_data(int kind, const void *payload, uint32_t length, int width, int height) {
    unsigned char header[136] = {0}; uint32_t magic = 0x56415050;
    memcpy(header, &magic, 4); header[4] = 10; header[5] = (unsigned char)kind;
    memcpy(header+8, &width, 4); memcpy(header+12, &height, 4); memcpy(header+16, state, sizeof(state));
    memcpy(header+132, &length, 4); transfer(input, header, sizeof(header), 1);
    transfer(input, (void *)payload, length, 1); return reply();
}
static size_t command(int kind, const char *payload, int width, int height) {
    return command_data(kind, payload, (uint32_t)strlen(payload), width, height);
}
struct view { int kind; double frame[4]; char id[32], text[128]; };
static struct view views[128]; static unsigned count;
static size_t parse(size_t at, size_t length, int depth) {
    if (depth > 8 || at+274 > length) die("element boundary");
    struct view v = {0}; v.kind = bytes[at]; memcpy(v.frame, bytes+at+10, 32); at += 274;
    for (int i = 0; i < 12; i++) {
        if (at+4 > length) die("string boundary");
        size_t n = number(bytes+at); at += 4;
        if (n > length-at) die("string size");
        if (i == 0 && n < sizeof(v.id)) memcpy(v.id, bytes+at, n);
        if (i == 3 && n < sizeof(v.text)) memcpy(v.text, bytes+at, n);
        at += n;
    }
    if (depth > 0) { if (count == 128) die("view count"); views[count++] = v; }
    if (at+8 > length || number(bytes+at)) die("menu boundary");
    unsigned children = number(bytes+at+4); at += 8;
    if (children > 64) die("child count");
    for (unsigned i = 0; i < children; i++) at = parse(at, length, depth+1);
    return at;
}
static void build(int width, int height) {
    size_t length = command(1, "", width, height); count = 0;
    if (parse(0, length, 0) != length || count != 20 || views[0].kind != 2) die("calculator view tree");
    for (unsigned i = 0; i < count; i++) {
        double *r = views[i].frame;
        if (!(r[0] >= 0 && r[1] >= 0 && r[2] > 0 && r[3] > 0 && r[0]+r[2] <= width+0.001 && r[1]+r[3] <= height+0.001)) die("layout");
    }
}
static void key(char k) {
    char title[2] = {k, 0}; const char *target = title;
    switch (k) { case 'C': target = "AC"; break; case 's': target = "±"; break;
        case '*': target = "×"; break; case '-': target = "−"; break; case '/': target = "÷"; break; }
    for (unsigned i = 1; i < count; i++) if (!strcmp(views[i].text, target)) {
        if (views[i].kind != 4) die("button kind"); command(2, views[i].id, 390, 680); return;
    }
    die("button missing");
}
void test_uikit(void) {
    int requests[2], responses[2], errors[2];
    if (pipe(requests) || pipe(responses) || pipe(errors)) die("pipe");
    pid_t child = fork(); if (child < 0) die("fork");
    if (!child) {
        close(requests[1]); close(responses[0]); close(errors[0]);
        dup2(errors[1], 2); close(errors[1]);
        char request[32], response[32]; snprintf(request, sizeof(request), "%d", requests[0]);
        snprintf(response, sizeof(response), "%d", responses[1]);
        setenv("VINIX_REQUEST_FD", request, 1); setenv("VINIX_RESPONSE_FD", response, 1);
        execl("/opt/ios/run-ios", "run-ios", "/opt/ios/UIKitCalculator", (char *)NULL); _exit(127);
    }
    close(requests[0]); close(responses[1]); close(errors[1]); input = requests[1]; output = responses[0];
    reply(); if (number(state+48) != 1) die("initial desktop scale"); build(390, 680);
    if (strcmp(views[0].text, "0")) die("initial display");
    static const struct { const char *keys, *expected; } cases[] = {
        {"7+5=","12"},{"3-9=","-6"},{"12*8=","96"},{"81/9=","9"},{"0.1+0.2=","0.3"},
        {"0002.50+0.25=","2.75"},{"2+3*4=","20"},{"5+*2=","10"},{"5+=","10"},{"2+3===","11"},
        {"2+3=7","7"},{"2+3=C","0"},{"200+10%=","220"},{"200-10%=","180"},{"200*10%=","20"},
        {"50%=","0.5"},{"2s+5=","3"},{"s2+5=","3"},{"2ss","2"},{"5+s2=","3"},{"1/0=","Error"},
        {"1/0=+","Error"},{"1/0=7+2=","9"},{"1/0=C","0"},{"0..25","0.25"},
        {"1234567890123456","123456789012345"},{"9*=*=*=*=*=*=*=*=*=*=*=*=","Error"}
    };
    for (unsigned i = 0; i < sizeof(cases)/sizeof(cases[0]); i++) {
        key('C'); for (const char *p = cases[i].keys; *p; p++) key(*p);
        build(390, 680);
        if (strcmp(views[0].text, cases[i].expected)) {
            printf("UIKit case %s expected %s got %s\n", cases[i].keys, cases[i].expected, views[0].text); die("arithmetic");
        }
    }
    puts("iOS PASS: UIKit Mach-O 27 button/action cases");
    build(480, 800); build(800, 480); build(390, 680);
    command(3, "C7+5=", 390, 680); build(390, 680); if (strcmp(views[0].text, "12")) die("keyboard");
    for (int i = 0; i < 1000; i++) {
        command(3, "C2+3=", 390, 680); build(390, 680); if (strcmp(views[0].text, "5")) die("update cycle");
    }
    command(6, "", 390, 680); close(input); close(output);
    int status; if (waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status)) die("exit status");
    char diagnostics[512]; ssize_t n = read(errors[0], diagnostics, sizeof(diagnostics)-1); close(errors[0]);
    if (n != 0) { if (n > 0) { diagnostics[n] = 0; puts(diagnostics); } die("runtime diagnostics/object ownership"); }
    puts("iOS PASS: UIKit resize, keyboard, 1000 updates and ARC teardown");
}

static void game_tree(void) {
    size_t length = command(1, "", 390, 680); count = 0;
    if (parse(0, length, 0) != length) die("2048 view tree");
}
static int game_score(unsigned *tiles) {
    int score = -1; *tiles = 0;
    for (unsigned i = 0; i < count; i++) {
        if (!strncmp(views[i].text, "SCORE: ", 7)) score = atoi(views[i].text+7);
        if (views[i].kind == 2 && views[i].text[0] >= '0' && views[i].text[0] <= '9') {
            unsigned value = (unsigned)atoi(views[i].text);
            if (value < 2 || (value & (value-1))) die("2048 tile value");
            (*tiles)++;
        }
    }
    if (score < 0 || *tiles > 16) die("2048 score/board");
    return score;
}
void test_2048(void) {
    int requests[2], responses[2], errors[2];
    if (pipe(requests) || pipe(responses) || pipe(errors)) die("2048 pipe");
    pid_t child = fork(); if (child < 0) die("2048 fork");
    if (!child) {
        close(requests[1]); close(responses[0]); close(errors[0]);
        dup2(errors[1], 2); close(errors[1]);
        char request[32], response[32]; snprintf(request, sizeof(request), "%d", requests[0]);
        snprintf(response, sizeof(response), "%d", responses[1]);
        setenv("VINIX_REQUEST_FD", request, 1); setenv("VINIX_RESPONSE_FD", response, 1);
        execl("/opt/ios/run-ios", "run-ios", "/opt/ios/NumberTileGame.app/NumberTileGame", (char *)NULL); _exit(127);
    }
    close(requests[0]); close(responses[1]); close(errors[1]); input = requests[1]; output = responses[0];
    reply(); game_tree();
    int found = 0;
    for (unsigned i = 0; i < count; i++) if (!strcmp(views[i].text, "Play Game")) {
        command(2, views[i].id, 390, 680); found = 1; break;
    }
    if (!found) die("2048 upstream launch button");
    game_tree(); unsigned tiles;
    if (game_score(&tiles) != 0 || tiles != 2) die("2048 initial board");
    int score = 0;
    const int32_t swipes[4][4] = {{310,340,90,340},{195,450,195,220},{90,340,310,340},{195,220,195,450}};
    for (int i = 0; i < 32; i++) {
        const int32_t *s = swipes[i%4];
        int32_t down[7] = {1,1,0,s[0],s[1],390,680}, up[7] = {2,1,0,s[2],s[3],390,680};
        command_data(5, down, sizeof(down), 390, 680); command_data(5, up, sizeof(up), 390, 680);
        usleep(320000); command(4, "", 390, 680); game_tree();
        int next = game_score(&tiles); if (next < score) die("2048 score monotonicity"); score = next;
    }
    if (score < 4) die("2048 merge/score");
    command(3, "\033[D", 390, 680); usleep(320000); command(4, "", 390, 680); game_tree();
    printf("iOS RESULT: upstream 2048 score=%d tiles=%u\n", score, tiles);
    command(6, "", 390, 680); close(input); close(output);
    int status; if (waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status)) die("2048 exit status");
    char diagnostics[512]; ssize_t n = read(errors[0], diagnostics, sizeof(diagnostics)-1); close(errors[0]);
    if (n != 0) { if (n > 0) { diagnostics[n] = 0; puts(diagnostics); } die("2048 runtime diagnostics/ARC teardown"); }
    puts("iOS PASS: upstream 2048 launch, swipes, merges, timers and ARC teardown");
}
