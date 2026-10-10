// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VINIX_IOS_READLINK_FIXTURE_H
#define VINIX_IOS_READLINK_FIXTURE_H
extern long readlink(const char *, char *, unsigned long);
extern int symlink(const char *, const char *);
extern int open(const char *, int, ...), close(int), unlink(const char *), getpid(void);
extern unsigned long strlen(const char *);
extern void *memset(void *, int, unsigned long);
extern int memcmp(const void *, const void *, unsigned long);
extern int snprintf(char *, unsigned long, const char *, ...), printf(const char *, ...), puts(const char *);
extern int *__error(void);
extern int pthread_create(unsigned long *, const void *, void *(*)(void *), void *);
extern int pthread_join(unsigned long, void **);

#define RL_CHECK(condition,code) do { if (!(condition)) { printf("IOS-READLINK: failure %d errno %d\n", code, *__error()); return code; } } while (0)
static int ios_readlink_worker_check(int index) {
    char path[128], file[128], loop[128], parent[160], missing[128], notdir[160], alias[160], through_alias[256];
    RL_CHECK(snprintf(path, sizeof path, "/tmp/vinix-ios-readlink-%d-%d", getpid(), index) > 0, 10);
    RL_CHECK(snprintf(file, sizeof file, "%s-file", path) > 0, 11);
    RL_CHECK(snprintf(loop, sizeof loop, "%s-loop", path) > 0, 12);
    RL_CHECK(snprintf(parent, sizeof parent, "%s/child", loop) > 0, 13);
    RL_CHECK(snprintf(missing, sizeof missing, "%s-missing", path) > 0, 14);
    RL_CHECK(snprintf(notdir, sizeof notdir, "%s/child", file) > 0, 15);
    RL_CHECK(snprintf(alias, sizeof alias, "%s-directory", path) > 0, 45);
    RL_CHECK(snprintf(through_alias, sizeof through_alias, "%s/vinix-ios-readlink-%d-%d", alias, getpid(), index) > 0, 46);
    const char target[] = "./missing/../target";
    unsigned long length = strlen(target);
    *__error() = 177;
    RL_CHECK(symlink(target, path) == 0 && *__error() == 177, 16);
    RL_CHECK(symlink(target, path) == -1 && *__error() == 17, 17);
    int fd = open(file, 0x200 | 0x800 | 2, 0600);
    RL_CHECK(fd >= 0, 18);
    RL_CHECK(symlink(loop, loop) == 0, 19);
    RL_CHECK(symlink("/tmp", alias) == 0, 47);
    struct { unsigned char before[8], data[64], after[8]; } output;
    const unsigned long sizes[] = {1, 4, length, length + 1, sizeof output.data, 0x7fffffffUL};
    for (unsigned i = 0; i < sizeof sizes / sizeof *sizes; i++) {
        memset(&output, 0x5a, sizeof output);
        *__error() = 177;
        unsigned long count = sizes[i] < length ? sizes[i] : length;
        RL_CHECK(readlink(path, (char *)output.data, sizes[i]) == (long)count && *__error() == 177, 20);
        RL_CHECK(memcmp(output.data, target, count) == 0, 21);
        for (unsigned j = 0; j < sizeof output.before; j++) RL_CHECK(output.before[j] == 0x5a && output.after[j] == 0x5a, 22);
        // A complete read also leaves the next byte untouched: no terminator.
        for (unsigned long j = count; j < sizeof output.data; j++) RL_CHECK(output.data[j] == 0x5a, 23);
    }
    memset(&output, 0x5a, sizeof output);
    *__error() = 177;
    RL_CHECK(readlink(path, (char *)output.data, 0) == 0 && *__error() == 177, 24);
    RL_CHECK(readlink(path, 0, 0) == 0 && *__error() == 177, 25);
    RL_CHECK(readlink(path, 0, 1) == -1 && *__error() == 14, 26);
    RL_CHECK(readlink(0, (char *)output.data, 1) == -1 && *__error() == 14, 27);
    RL_CHECK(readlink(0, (char *)output.data, 0) == -1 && *__error() == 14, 48);
    RL_CHECK(readlink(missing, 0, 1) == -1 && *__error() == 2, 28);
    RL_CHECK(readlink(missing, (char *)output.data, 0) == -1 && *__error() == 2, 29);
    RL_CHECK(readlink("", (char *)output.data, 1) == -1 && *__error() == 2, 30);
    RL_CHECK(readlink(file, (char *)output.data, sizeof output.data) == -1 && *__error() == 22, 31);
    RL_CHECK(readlink(file, 0, 1) == -1 && *__error() == 22, 32);
    RL_CHECK(readlink(file, (char *)output.data, 0) == -1 && *__error() == 22, 33);
    RL_CHECK(readlink(notdir, (char *)output.data, sizeof output.data) == -1 && *__error() == 20, 34);
    RL_CHECK(readlink(parent, (char *)output.data, sizeof output.data) == -1 && *__error() == 62, 35);
    RL_CHECK(readlink(path, (char *)output.data, 0x80000000UL) == -1 && *__error() == 22, 36);
    RL_CHECK(readlink(path, (char *)output.data, ~0UL) == -1 && *__error() == 22, 37);
    RL_CHECK(readlink(0, 0, 0x80000000UL) == -1 && *__error() == 22, 38);
    RL_CHECK(readlink(missing, (char *)output.data, 0x80000000UL) == -1 && *__error() == 22, 39);
    for (unsigned i = 0; i < sizeof output; i++) RL_CHECK(((unsigned char *)&output)[i] == 0x5a, 40);
    // The final component is read, rather than followed, even when self-referential.
    *__error() = 177;
    RL_CHECK(readlink(loop, (char *)output.data, sizeof output.data) == (long)strlen(loop) && *__error() == 177, 41);
    RL_CHECK(memcmp(output.data, loop, strlen(loop)) == 0, 42);
    *__error() = 177;
    RL_CHECK(readlink(through_alias, (char *)output.data, sizeof output.data) == (long)length && *__error() == 177, 49);
    RL_CHECK(memcmp(output.data, target, length) == 0, 50);
    RL_CHECK(close(fd) == 0 && unlink(file) == 0 && unlink(loop) == 0 && unlink(alias) == 0 && unlink(path) == 0, 43);
    RL_CHECK(readlink(path, (char *)output.data, sizeof output.data) == -1 && *__error() == 2, 44);
    return 0;
}
struct ios_readlink_job { int index, error; };
static void *ios_readlink_worker(void *argument) {
    struct ios_readlink_job *job = argument;
    job->error = ios_readlink_worker_check(job->index);
    return 0;
}
static int ios_readlink_check(void) {
    int result = ios_readlink_worker_check(0);
    if (result) return result;
    unsigned long threads[8]; struct ios_readlink_job jobs[8];
    *__error() = 12345;
    for (int i = 0; i < 8; i++) {
        jobs[i].index = i + 1; jobs[i].error = 0;
        RL_CHECK(pthread_create(&threads[i], 0, ios_readlink_worker, &jobs[i]) == 0, 1);
    }
    int failed = 0;
    for (int i = 0; i < 8; i++) {
        if (pthread_join(threads[i], 0) != 0 || jobs[i].error) failed = 1;
    }
    RL_CHECK(!failed && *__error() == 12345, 2);
    puts("IOS-READLINK: native links, guarded truncation, zero counts, Darwin errors and eight threads");
    return 0;
}
#undef RL_CHECK
#endif
