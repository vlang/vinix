// SPDX-License-Identifier: GPL-2.0-or-later
extern int fcntl(int, int, ...), fsync(int), open(const char *, int, ...), close(int), unlink(const char *), getpid(void);
extern long write(int, const void *, unsigned long), read(int, void *, unsigned long);
extern long long lseek(int, long long, int);
extern int socketpair(int, int, int, int *);
extern long send(int, const void *, unsigned long, int), recv(int, void *, unsigned long, int);
extern int snprintf(char *, unsigned long, const char *, ...), printf(const char *, ...), puts(const char *);
extern int *__error(void);
extern int pthread_create(unsigned long *, const void *, void *(*)(void *), void *), pthread_join(unsigned long, void **);
#define CHECK(value,code) do { if (!(value)) { printf("IOS-FCNTL: failure %d errno %d\n",code,*__error()); return code; } } while (0)

static int check(int index) {
    char name[96];
    CHECK(snprintf(name, sizeof name, "/tmp/vinix-ios-fcntl-%d-%d", getpid(), index) > 0, 1);
    int fd = open(name, 2 | 0x200 | 0x800 | 0x1000000, 0600);
    CHECK(fd >= 0 && unlink(name) == 0, 2);
    CHECK(fcntl(fd, 1) == 1 && fcntl(fd, 3) == 2, 3);
    *__error() = 177;
    int alias = fcntl(fd, 0, 100);
    CHECK(alias >= 100 && *__error() == 177 && fcntl(alias, 1) == 0, 4);
    int protected = fcntl(fd, 67, 100);
    CHECK(protected >= 100 && protected != alias && fcntl(protected, 1) == 1, 5);
    const int bits[] = {0,1,2,3,-1};
    for (unsigned i = 0; i < sizeof bits/sizeof *bits; ++i) {
        *__error() = 177;
        CHECK(fcntl(alias, 2, bits[i]) == 0 && *__error() == 177, 6);
        CHECK(fcntl(alias, 1) == (bits[i] & 1), 7);
        CHECK(fcntl(fd, 1) == 1 && fcntl(protected, 1) == 1, 8);
    }
    const int modes[] = {0,4,8,12,0x200 | 0x800 | 4,0x1000000 | 8,0x80,0x400000,0};
    for (unsigned i = 0; i < sizeof modes/sizeof *modes; ++i) {
        *__error() = 177;
        CHECK(fcntl(alias, 4, modes[i]) == 0 && *__error() == 177, 9);
        int expected = 2 | (modes[i] & (12 | 0x80 | 0x400000));
        CHECK(fcntl(fd, 3) == expected && fcntl(alias, 3) == expected && fcntl(protected, 3) == expected, 10);
    }
    CHECK(write(fd, "a", 1) == 1 && lseek(alias, 0, 0) == 0, 11);
    CHECK(fcntl(protected, 4, 8) == 0 && write(alias, "b", 1) == 1, 12);
    CHECK(lseek(fd, 0, 0) == 0, 13);
    char bytes[2];
    CHECK(read(fd, bytes, 2) == 2 && bytes[0] == 'a' && bytes[1] == 'b', 14);
    CHECK(lseek(alias, 0, 1) == 2, 15);
    *__error() = 177;
    CHECK(fsync(fd) == 0 && *__error() == 177, 16);
    CHECK(fcntl(fd, 0, -1) == -1 && *__error() == 22, 17);
    CHECK(fcntl(fd, 67, -1) == -1 && *__error() == 22, 18);
    CHECK(fcntl(fd, 0, 100000000) == -1 && *__error() == 22, 35);
    CHECK(fcntl(fd, 67, 100000000) == -1 && *__error() == 22, 36);
    CHECK(fcntl(fd, -1) == -1 && *__error() == 22, 19);
    CHECK(fcntl(fd, 999) == -1 && *__error() == 25, 20);
#ifndef IOS_FCNTL_REFERENCE
    // The runner explicitly rejects unsupported Apple control services. EOSSDK
    // falls back from F_FULLFSYNC to ordinary fsync in its actual call sites.
    CHECK(fcntl(fd, 51) == -1 && *__error() == 45 && fsync(fd) == 0, 21);
    CHECK(fcntl(fd, 48, 1) == -1 && *__error() == 45, 22);
#endif
    CHECK(close(alias) == 0 && close(protected) == 0 && close(fd) == 0, 23);
    // Concurrent clients may already have reused a just-closed descriptor.
    int invalid = index == 0 ? fd : -1;
    CHECK(fcntl(invalid, 3) == -1 && *__error() == 9, 24);
    CHECK(fsync(invalid) == -1 && *__error() == 9, 25);

    int pair[2];
    CHECK(socketpair(1, 1, 0, pair) == 0, 26);
    CHECK(fcntl(pair[0], 3) == 2 && fcntl(pair[0], 4, 4) == 0 && fcntl(pair[0], 3) == 6, 27);
    CHECK(recv(pair[0], bytes, 1, 0) == -1 && *__error() == 35, 28);
    CHECK(send(pair[1], "x", 1, 0) == 1 && recv(pair[0], bytes, 1, 0) == 1 && bytes[0] == 'x', 29);
    CHECK(fcntl(pair[0], 4, 0) == 0 && fcntl(pair[0], 3) == 2, 30);
    CHECK(close(pair[0]) == 0 && close(pair[1]) == 0, 31);
    return 0;
}
struct job { int index, error; };
static void *worker(void *argument) {
    struct job *job = argument;
    job->error = check(job->index);
    return 0;
}
int main(void) {
    CHECK(fcntl(-1, 999) == -1 && *__error() == 9, 32);
    int error = check(0);
    if (error) return error;
    unsigned long clients[8]; struct job jobs[8];
    for (int i = 0; i < 8; ++i) {
        jobs[i].index = i + 1; jobs[i].error = 0;
        CHECK(pthread_create(&clients[i], 0, worker, &jobs[i]) == 0, 33);
    }
    for (int i = 0; i < 8; ++i) CHECK(pthread_join(clients[i], 0) == 0 && jobs[i].error == 0, 34);
    puts("IOS-FCNTL: shared status and offsets, descriptor flags, duplicates, native flush and nonblocking sockets");
    return 0;
}
