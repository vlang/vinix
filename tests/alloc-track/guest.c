/* Native coverage of the C entry's frame capture and V live-site aggregation. */
#define _GNU_SOURCE
#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define CHECK(test) do { if (!(test)) { \
    printf("ALLOC TRACK FAIL: line %d\n", __LINE__); fflush(stdout); _exit(1); \
} } while (0)

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    int start = open("/proc/allocstart", O_RDONLY);
    CHECK(start >= 0);
    char byte;
    CHECK(read(start, &byte, 1) >= 0);
    CHECK(close(start) == 0);
    int pipes[128][2];
    for (unsigned i = 0; i < 128; i++) CHECK(pipe(pipes[i]) == 0);
    int sites = open("/proc/allocsites", O_RDONLY);
    CHECK(sites >= 0);
    static char output[1048576];
    size_t used = 0;
    for (;;) {
        ssize_t n = read(sites, output + used, sizeof(output) - 1 - used);
        CHECK(n >= 0);
        if (!n) break;
        used += (size_t)n;
        CHECK(used < sizeof(output) - 1);
    }
    output[used] = 0;
    CHECK(close(sites) == 0 && !strncmp(output, "live ", 5));
    unsigned long long live, dropped;
    CHECK(sscanf(output, "live %llu dropped %llu", &live, &dropped) == 2);
    CHECK(live >= 128 && dropped == 0);
    unsigned named = 0;
    char *line = strchr(output, '\n');
    CHECK(line != NULL);
    for (++line; *line;) {
        unsigned long long count, size, pc;
        CHECK(sscanf(line, "%llu %llu %llx", &count, &size, &pc) == 3);
        CHECK(count >= 50 && size > 0 && pc != 0);
        named++;
        line = strchr(line, '\n');
        CHECK(line != NULL);
        ++line;
    }
    CHECK(named > 0);
    for (unsigned i = 0; i < 128; i++) {
        CHECK(close(pipes[i][0]) == 0 && close(pipes[i][1]) == 0);
    }
    puts("ALLOC TRACK GUEST PASS");
    for (;;) pause();
}
