// SPDX-License-Identifier: GPL-2.0-or-later
// The same Darwin ABI fixture runs against the Mac library and V adapters.
struct descriptor { int fd; short events, revents; };
struct timestamp { long seconds, nanos; };
extern int pipe(int *), poll(struct descriptor *, unsigned, int);
extern int fcntl(int, int, ...), close(int), socketpair(int, int, int, int *);
extern long read(int, void *, unsigned long), write(int, const void *, unsigned long);
extern int clock_gettime(int, struct timestamp *), usleep(unsigned), strcmp(const char *, const char *);
extern int *__error(void), puts(const char *), printf(const char *, ...);
extern int pthread_create(unsigned long *, const void *, void *(*)(void *), void *), pthread_join(unsigned long, void **);

#define CHECK(condition, code) do { if (!(condition)) { error = code; goto done; } } while (0)
static int readiness(int fd, short events, short expected) {
    struct { unsigned long before; struct descriptor value; unsigned long after; } guard = {
        0xabcdef0123456789UL, {fd, events, 0x7777}, 0xabcdef0123456789UL};
    *__error() = 177;
    int result = poll(&guard.value, 1, 0);
    if (result != !!expected || guard.value.revents != expected || *__error() != 177 ||
        guard.value.fd != fd || guard.value.events != events ||
        guard.before != 0xabcdef0123456789UL || guard.after != 0xabcdef0123456789UL) {
        printf("IOS-POLL: fd %d events %x result %d revents %x expected %x errno %d\n",
            fd, (unsigned short)events, result, (unsigned short)guard.value.revents, (unsigned short)expected, *__error());
        return 1;
    }
    return 0;
}
static int pairs(void) {
    int error = 0, p[2] = {-1,-1}, sockets[2] = {-1,-1};
    struct { unsigned before; int pair[2]; unsigned after; } guard = {0xabcdef01U, {-1,-1}, 0xabcdef01U};
    *__error() = 177; CHECK(pipe(guard.pair) == 0, 1); p[0] = guard.pair[0]; p[1] = guard.pair[1];
    CHECK(*__error() == 177 && guard.before == 0xabcdef01U && guard.after == 0xabcdef01U, 2);
    CHECK(fcntl(p[0], 3) == 0 && fcntl(p[1], 3) == 1 && fcntl(p[0], 1) == 0 && fcntl(p[1], 1) == 0, 3);
    const short masks[] = {1,4,0x40,2,0x80,0x100,0};
    for (unsigned i = 0; i < sizeof masks/sizeof *masks; i++) {
        CHECK(!readiness(p[0], masks[i], 0), 4);
        CHECK(!readiness(p[1], masks[i], masks[i] & 0x104), 5);
    }
    struct { unsigned long before; struct descriptor array[65]; unsigned long after; } many;
    many.before = many.after = 0xabcdef0123456789UL;
    for (unsigned i = 0; i < 65; i++) many.array[i] = (struct descriptor){-13, (short)0xffff, 0x7777};
    many.array[2] = (struct descriptor){p[0], 0x41, 0x7777};
    many.array[64] = (struct descriptor){p[1], 0x104, 0x7777};
    *__error() = 177; CHECK(poll(many.array, 65, 0) == 1 && *__error() == 177, 6);
    CHECK(write(p[1], "abc", 3) == 3, 7);
    *__error() = 177; CHECK(poll(many.array, 65, 0) == 2 && *__error() == 177, 8);
    for (unsigned i = 0; i < 65; i++) {
        short expected = i == 2 ? 0x41 : i == 64 ? 0x104 : 0;
        CHECK(many.array[i].revents == expected, 9);
        CHECK(many.array[i].fd == (i == 2 ? p[0] : i == 64 ? p[1] : -13), 10);
        CHECK(many.array[i].events == (i == 2 ? 0x41 : i == 64 ? 0x104 : (short)0xffff), 11);
    }
    CHECK(many.before == 0xabcdef0123456789UL && many.after == 0xabcdef0123456789UL, 12);
    CHECK(close(p[1]) == 0, 13); p[1] = -1;
    CHECK(!readiness(p[0], 0x45, 0x51) && !readiness(p[0], 0, 0), 14);
    char bytes[3]; CHECK(read(p[0], bytes, 3) == 3 && bytes[0] == 'a' && bytes[1] == 'b' && bytes[2] == 'c', 15);
    CHECK(!readiness(p[0], 0x45, 0x51) && read(p[0], bytes, 1) == 0, 16);
    CHECK(close(p[0]) == 0, 17); p[0] = -1;
    CHECK(pipe(p) == 0 && close(p[0]) == 0, 18); p[0] = -1;
    CHECK(!readiness(p[1], 0x104, 0x10) && !readiness(p[1], 0x41, 0x51), 19);
    CHECK(!readiness(0x3fffffff, 1, 0x20) && !readiness(0x3fffffff, 0, 0) && !readiness(-1, (short)0xffff, 0), 20);
    CHECK(socketpair(1, 1, 0, sockets) == 0, 21);
    CHECK(!readiness(sockets[0], 0x145, 0x104) && write(sockets[1], "abc", 3) == 3, 22);
    CHECK(!readiness(sockets[0], 0x145, 0x145), 23);
    CHECK(close(sockets[1]) == 0, 24); sockets[1] = -1;
    CHECK(!readiness(sockets[0], 0x145, 0x51), 25);
    CHECK(read(sockets[0], bytes, 3) == 3 && bytes[0] == 'a' && read(sockets[0], bytes, 1) == 0, 26);
done:
    for (int i = 0; i < 2; i++) { if (p[i] >= 0) close(p[i]); if (sockets[i] >= 0) close(sockets[i]); }
    if (error) printf("IOS-POLL: pair failure %d errno %d\n", error, *__error());
    return error;
}
struct producer { int fd, error; };
static void *produce(void *argument) {
    struct producer *job = argument;
    if (usleep(20000) || write(job->fd, "x", 1) != 1) job->error = 1;
    if (close(job->fd)) job->error = 1;
    return 0;
}
static int waits(void) {
    struct timestamp before, after;
    if (clock_gettime(6, &before)) return 27;
    *__error() = 177;
    if (poll(0, 0, 30) != 0 || *__error() != 177 || clock_gettime(6, &after)) return 28;
    if ((after.seconds - before.seconds) * 1000000000L + after.nanos - before.nanos < 20000000) return 29;
    struct descriptor ignored = {-1, (short)0xffff, 0x7777};
    if (clock_gettime(6, &before) || poll(&ignored, 1, 30) || clock_gettime(6, &after)) return 30;
    if (ignored.revents || (after.seconds - before.seconds) * 1000000000L + after.nanos - before.nanos < 20000000) return 31;
    int p[2]; if (pipe(p)) return 32;
    struct producer job = {p[1],0}; unsigned long thread;
    if (pthread_create(&thread, 0, produce, &job)) { close(p[0]); close(p[1]); return 33; }
    struct descriptor input = {p[0], 0x41, 0x7777};
    *__error() = 177; int result = poll(&input, 1, -7), saved_error = *__error();
    int joined = pthread_join(thread, 0); char byte = 0;
    int count = result > 0 ? (int)read(p[0], &byte, 1) : -1;
    close(p[0]);
    if (joined || job.error || result != 1 || saved_error != 177 || !(input.revents & 0x41) || count != 1 || byte != 'x') return 34;
    return 0;
}
static void *worker(void *argument) {
    int *error = argument;
    for (int i = 0; i < 16 && !*error; i++) *error = pairs();
    return 0;
}
int main(int argc, char **argv) {
    int error = pairs(); if (error) return error;
    error = waits(); if (error) return error;
    if (poll(0, 1, 0) != -1 || *__error() != 14) return 35;
    if (poll(0, 0xffffffffU, 0) != -1 || *__error() != 22) return 36;
    if (!(argc > 1 && !strcmp(argv[1], "--native-darwin"))) {
        if (pipe(0) != -1 || *__error() != 14) return 37;
        struct descriptor unsupported = {0, 0x200, 0x7777};
        if (poll(&unsupported, 1, 0) != -1 || *__error() != 45 || unsupported.revents != 0x7777) return 38;
        struct descriptor many[65];
        for (unsigned i = 0; i < 65; i++) many[i] = (struct descriptor){-1,0,0x7777};
        many[64] = unsupported;
        if (poll(many, 65, 0) != -1 || *__error() != 45) return 40;
        for (unsigned i = 0; i < 65; i++) if (many[i].revents != 0x7777) return 41;
    }
    unsigned long threads[8]; int errors[8] = {0}, started = 0, failed = 0;
    *__error() = 12345;
    for (int i = 0; i < 8; i++) { if (pthread_create(&threads[i], 0, worker, &errors[i])) break; started++; }
    for (int i = 0; i < started; i++) if (pthread_join(threads[i], 0) || errors[i]) failed = 1;
    if (started != 8 || failed || *__error() != 12345) return 39;
    puts("IOS-POLL: real pipes/socket I/O, band flags, endpoint readiness, EOF, timeouts, guarded arrays and eight threads");
    return 0;
}
