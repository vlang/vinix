// SPDX-License-Identifier: GPL-2.0-or-later
extern int chmod(const char *, unsigned short), fchmod(int, unsigned short);
extern int open(const char *, int, ...), close(int), unlink(const char *), getpid(void);
extern int stat(const char *, void *), fstat(int, void *);
extern int snprintf(char *, unsigned long, const char *, ...), printf(const char *, ...), puts(const char *);
extern int *__error(void);
extern int pthread_create(unsigned long *, const void *, void *(*)(void *), void *);
extern int pthread_join(unsigned long, void **);

#define CHECK(condition,code) do { if (!(condition)) { printf("IOS-PERMISSIONS: failure %d errno %d\n", code, *__error()); return code; } } while (0)
static int check(int index) {
    char path[96];
    CHECK(snprintf(path, sizeof path, "/tmp/vinix-ios-permissions-%d-%d", getpid(), index) > 0, 10);
    CHECK(chmod(path, 0600) == -1 && *__error() == 2, 11);
    int fd = open(path, 0x200 | 0x800 | 2, 0600);
    CHECK(fd >= 0, 12);
    unsigned long long status[18];
    const unsigned short modes[] = {0600, 0644, 0711, 01777, 04755, 0600};
    for (unsigned i = 0; i < sizeof modes / sizeof *modes; i++) {
        *__error() = 177;
        CHECK(chmod(path, modes[i]) == 0 && *__error() == 177, 13);
        CHECK(stat(path, status) == 0 && (((unsigned short *)(void *)status)[2] & 07777) == modes[i], 14);
        unsigned short different = modes[i] ^ 0070;
        *__error() = 177;
        CHECK(fchmod(fd, different) == 0 && *__error() == 177, 15);
        CHECK(fstat(fd, status) == 0 && (((unsigned short *)(void *)status)[2] & 07777) == different, 16);
        CHECK((((unsigned short *)(void *)status)[2] & 0170000) == 0100000, 17);
    }
    CHECK(unlink(path) == 0, 18);
    CHECK(fchmod(fd, 0640) == 0 && fstat(fd, status) == 0 && (((unsigned short *)(void *)status)[2] & 07777) == 0640, 19);
    CHECK(close(fd) == 0, 20);
    CHECK(fchmod(fd, 0600) == -1 && *__error() == 9, 21);
    return 0;
}
struct job { int index, error; };
static void *worker(void *argument) {
    struct job *job = argument;
    job->error = check(job->index);
    return 0;
}
int main(int argc, char **argv) {
    if (argc > 1) CHECK(chmod(argv[1], 0600) == -1 && *__error() == 62, 1);
    int error = check(0);
    if (error) return error;
    unsigned long threads[8]; struct job jobs[8];
    *__error() = 12345;
    for (int i = 0; i < 8; i++) {
        jobs[i].index = i + 1; jobs[i].error = 0;
        CHECK(pthread_create(&threads[i], 0, worker, &jobs[i]) == 0, 2);
    }
    for (int i = 0; i < 8; i++) CHECK(pthread_join(threads[i], 0) == 0 && jobs[i].error == 0, 3);
    CHECK(*__error() == 12345, 4);
    puts("IOS-PERMISSIONS: real file modes, unlinked descriptors, Darwin errors and eight threads");
    return 0;
}
