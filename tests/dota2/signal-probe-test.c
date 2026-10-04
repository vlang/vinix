/* Host test: clang -Wall -Wextra -Werror signal-probe-test.c -o /tmp/probe-test */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#define SIGNAL_PROBE_HOST_TEST
#define write probe_write
#define read probe_read
#define open probe_open
#define close probe_close
#define getenv probe_getenv
#define unsetenv probe_unsetenv
#define raise probe_raise
#define sigaction probe_sigaction
#define __errno_location probe_errno
#include "signal-probe.c"

static char output[32768], tail[1024];
static unsigned long output_length, position, junk_bytes, chunk = 997;
static int error, writes, reads, closes, interrupted_reads, interrupted_writes;
static int raised, actions, unsets, short_writes;
static char *gate;
static const char junk[] = "1000-2000 rw-p 00000000 00:00 0\n";

int *probe_errno(void) { return &error; }
char *probe_getenv(const char *name) { assert(!strcmp(name, "VINIX_DOTA2_SIGNAL_PROBE")); return gate; }
int probe_unsetenv(const char *name) { assert(!strcmp(name, "VINIX_DOTA2_SIGNAL_PROBE")); ++unsets; return 0; }
int probe_open(const char *name, int flags, ...) { assert(!strcmp(name, "/proc/self/maps") && !flags); return 7; }
int probe_close(int descriptor) { assert(descriptor == 7); ++closes; return 0; }
int probe_raise(int number) { raised = number; return 0; }
int probe_sigaction(int number, const struct action *action, struct action *previous)
{
    const int signals[] = {11, 7, 4};
    assert(actions < 3 && number == signals[actions++]);
    assert(!previous && action->handler == failure && (unsigned)action->flags == 0x80000004U);
    for (int index = 0; index < 16; ++index) assert(!action->mask[index]);
    return 0;
}

long probe_write(int descriptor, const void *data, unsigned long count)
{
    assert(descriptor == 2); ++writes;
    if (interrupted_writes) { --interrupted_writes; error = 4; return -1; }
    if (short_writes && count > 13) count = 13;
    assert(output_length + count < sizeof output);
    memcpy(output + output_length, data, count); output_length += count;
    output[output_length] = 0;
    return (long)count;
}

long probe_read(int descriptor, void *data, unsigned long count)
{
    assert(descriptor == 7); ++reads;
    if (interrupted_reads) { --interrupted_reads; error = 4; return -1; }
    unsigned long total = junk_bytes + strlen(tail);
    if (position == total) return 0;
    if (count > chunk) count = chunk;
    if (count > total - position) count = total - position;
    for (unsigned long index = 0; index < count; ++index, ++position)
        ((char *)data)[index] = position < junk_bytes ? junk[position % (sizeof junk - 1)] : tail[position - junk_bytes];
    return (long)count;
}

static void reset(void)
{
    output_length = position = junk_bytes = 0; output[0] = tail[0] = 0;
    error = writes = reads = closes = interrupted_reads = interrupted_writes = 0;
    raised = actions = unsets = short_writes = 0; chunk = 997; gate = 0;
}

static int occurrences(const char *needle)
{
    int count = 0;
    for (const char *at = output; (at = strstr(at, needle)); at += strlen(needle)) ++count;
    return count;
}

int main(void)
{
    struct map_range mapping;
    assert(parse_map("8000-9000 r-xp 00004000 00:00 12 /game.so", &mapping));
    assert(mapping.start == 0x8000 && mapping.end == 0x9000 && mapping.offset == 0x4000);
    assert(mapping.readable && !strcmp(mapping.path, "/game.so"));
    assert(parse_map("9000-a000 ---p 0 00:00 0", &mapping) && !mapping.readable);
    assert(!parse_map("9000-8000 r-xp 0 00:00 0", &mapping));
    assert(!parse_map("10000000000000000-2000 r-xp 0 00:00 0", &mapping));
    assert(!parse_map("8000-9000 r", &mapping));
    assert(!parse_map("8000-9000 r-xp", &mapping));
    struct context context = {0}; struct signal_info info = {11, 0, 1, 0, 0x40};
    for (int index = 0; index < 23; ++index) context.registers[index] = 0x100000UL + (unsigned long)index;
    reset(); emit_context(11, &info, &context, 23);
    assert(writes == 1 && occurrences("SIGNAL-REGISTER:") == 15);
    assert(strstr(output, "address=0x0000000000000040") && strstr(output, "SIGNAL-ERRNO: 0x0000000000000017"));
    char expected[2048]; strcpy(expected, output);
    reset(); interrupted_writes = 1; short_writes = 1; emit_context(11, &info, &context, 23);
    assert(!strcmp(output, expected));

    unsigned long stack[256];
    for (unsigned long index = 0; index < 256; ++index) stack[index] = 0xa000UL + index;
    context.registers[15] = (unsigned long)stack; context.registers[16] = 0x89ff; context.registers[10] = 0;
    reset(); error = 23; interrupted_reads = 2;
    junk_bytes = (2UL * 1024 * 1024 / (sizeof junk - 1)) * (sizeof junk - 1);
    snprintf(tail, sizeof tail, "8000-8400 r--p 0 00:00 1 /game.so\n8400-9000 r-xp 400 00:00 1 /game.so\n%lx-%lx rw-p 0 00:00 0 [stack]\n", (unsigned long)stack, (unsigned long)(stack + 256));
    failure(11, &info, &context);
    assert(closes == 1 && raised == 11 && position > 1024 * 1024);
    assert(occurrences("SIGNAL-MAP:") == 3 && occurrences("SIGNAL-STACK:") == 256);
    assert(strstr(output, "/game.so") && !strstr(output, "MAPS-TRUNCATED"));
    assert(strstr(output, "returning to the original fault with SIG_DFL"));

    reset(); context.registers[15] = (unsigned long)stack + 1;
    snprintf(tail, sizeof tail, "%lx-%lx rw-p 0 00:00 0 [stack]\n", (unsigned long)stack, (unsigned long)(stack + 256));
    failure(11, &info, &context);
    assert(!occurrences("SIGNAL-STACK:") && !occurrences("SIGNAL-FRAME:") && raised == 11 && closes == 1);
    reset(); context.registers[15] = (unsigned long)stack;
    snprintf(tail, sizeof tail, "%lx-%lx ---p 0 00:00 0 [stack]\n", (unsigned long)stack, (unsigned long)(stack + 256));
    failure(11, &info, &context);
    assert(!occurrences("SIGNAL-STACK:") && !occurrences("SIGNAL-FRAME:") && raised == 11 && closes == 1);

    reset(); junk_bytes = 32UL * 1024 * 1024;
    struct map_scan scan = {0}; scan.context = &context; scan.fault = 0x40;
    maps(&scan);
    assert(position == 16UL * 1024 * 1024 && reads <= 32768 && closes == 1);
    assert(strstr(output, "MAPS-TRUNCATED"));
    reset(); junk_bytes = 32UL * 1024 * 1024; chunk = 1; maps(&scan);
    assert(reads == 32768 && closes == 1 && strstr(output, "MAPS-TRUNCATED"));

    reset(); error = 42; arm(); assert(!actions && !unsets && error == 42);
    gate = "10"; arm(); assert(!actions && !unsets && error == 42);
    gate = "1"; arm(); assert(actions == 3 && unsets == 1 && error == 42);
    puts("signal-probe host parser/context/bounds/registration checks PASS");
    return 0;
}
