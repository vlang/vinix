// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the actual compatibility library on a native ARM64 musl host.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

static size_t (*checked_fread)(void *, size_t, size_t, FILE *, size_t);
static ssize_t (*checked_readlink)(const char *, char *, size_t, size_t);
static ssize_t (*checked_sendto)(int, const void *, size_t, size_t, int,
                                 const struct sockaddr *, socklen_t);
static size_t (*checked_strlcpy)(char *, const char *, size_t, size_t);
static void (*android_assert)(const char *, int, const char *);
static FILE *input;
static char link_path[128];
static int sockets[2];

static void require(int condition, const char *reason)
{
    if (!condition) {
        fprintf(stderr, "ANDROID-FORTIFY-FAIL %s\n", reason);
        exit(1);
    }
}

static void fread_overrun(void)
{
    char buffer[2];
    checked_fread(buffer, 2, 2, input, sizeof(buffer));
}

static void readlink_overrun(void)
{
    char buffer[2];
    checked_readlink(link_path, buffer, 3, sizeof(buffer));
}

static void readlink_count_overflow(void)
{
    char buffer[2];
    checked_readlink(link_path, buffer, (size_t)SSIZE_MAX + 1, SIZE_MAX);
}

static void sendto_overrun(void)
{
    char buffer[2] = { 0 };
    checked_sendto(sockets[0], buffer, 3, sizeof(buffer), 0, NULL, 0);
}

static void strlcpy_overrun(void)
{
    char buffer[2];
    // The destination check must abort before it tries to read the source.
    checked_strlcpy(buffer, NULL, 3, sizeof(buffer));
}

static void strlcpy_count_overflow(void)
{
    char buffer[2];
    checked_strlcpy(buffer, NULL, SIZE_MAX, sizeof(buffer));
}

static void assertion_failure(void)
{
    android_assert("fortify-test.c", 1, "Android assertion must abort");
}

static void require_abort(void (*operation)(void), const char *reason)
{
    pid_t child = fork();
    require(child >= 0, "fork");
    if (child == 0) {
        alarm(5);
        // Expected diagnostics are noisy in the serial test log.
        if (freopen("/dev/null", "w", stderr) == NULL) _exit(90);
        operation();
        _exit(91);
    }
    int status;
    require(waitpid(child, &status, 0) == child && WIFSIGNALED(status)
            && WTERMSIG(status) == SIGABRT, reason);
}

static int check_standard_stream(int required)
{
    // When the real Bionic provider is loaded, check its stdin facade too.
    FILE *facade = dlsym(RTLD_DEFAULT, "bionic___sF");
    if (facade == NULL) {
        require(!required, "explicit Bionic provider must export __sF");
        return 0;
    }
    int data[2];
    require(pipe(data) == 0, "standard stream pipe");
    int saved_stdin = dup(STDIN_FILENO);
    require(saved_stdin >= 0, "save stdin");
    require(write(data[1], "stdin", 5) == 5, "standard stream input");
    close(data[1]);
    require(dup2(data[0], STDIN_FILENO) == STDIN_FILENO, "replace stdin");
    close(data[0]);
    clearerr(stdin);
    char buffer[5];
    require(checked_fread(buffer, 1, sizeof(buffer), facade, sizeof(buffer)) == 5
            && memcmp(buffer, "stdin", 5) == 0, "Bionic stdin facade");
    errno = 0;
    require(checked_fread(buffer, SIZE_MAX, 2, facade, sizeof(buffer)) == 0
            && errno == EOVERFLOW && ferror(stdin), "Bionic stdin overflow flags");
    clearerr(stdin);
    require(dup2(saved_stdin, STDIN_FILENO) == STDIN_FILENO, "restore stdin");
    close(saved_stdin);
    return 1;
}

int main(int argc, char **argv)
{
    alarm(20);
    struct rlimit core_limit = { 0, 0 };
    require(setrlimit(RLIMIT_CORE, &core_limit) == 0, "disable core files");
    require(argc <= 3, "usage: fortify-test [compat.so [libc_bio.so]]");
    for (int index = 1; index < argc; ++index) {
        require(dlopen(argv[index], RTLD_NOW | RTLD_GLOBAL) != NULL, "load runtime library");
    }
    checked_fread = dlsym(RTLD_DEFAULT, "bionic___fread_chk");
    checked_readlink = dlsym(RTLD_DEFAULT, "bionic___readlink_chk");
    checked_sendto = dlsym(RTLD_DEFAULT, "bionic___sendto_chk");
    checked_strlcpy = dlsym(RTLD_DEFAULT, "bionic___strlcpy_chk");
    android_assert = dlsym(RTLD_DEFAULT, "bionic___assert");
    require(checked_fread != NULL && checked_readlink != NULL && checked_sendto != NULL
            && checked_strlcpy != NULL && android_assert != NULL, "native Android ABI exports");

    input = tmpfile();
    require(input != NULL && fwrite("abcdefgh", 1, 8, input) == 8, "fread fixture");
    rewind(input);
    char buffer[32];
    memset(buffer, '#', sizeof(buffer));
    require(checked_fread(buffer, 2, 3, input, 6) == 3
            && memcmp(buffer, "abcdef", 6) == 0 && buffer[6] == '#', "fread bounded items");
    require(checked_fread(buffer, 0, 4, input, 0) == 0
            && checked_fread(buffer, 4, 0, input, 0) == 0, "fread zero requests");
    require(checked_fread(buffer, 1, 4, input, SIZE_MAX) == 2
            && memcmp(buffer, "gh", 2) == 0 && feof(input), "fread short read and unknown size");
    rewind(input);
    errno = 0;
    require(checked_fread(buffer, SIZE_MAX, 2, input, sizeof(buffer)) == 0
            && errno == EOVERFLOW && ferror(input) && ftell(input) == 0,
            "fread overflow flags without I/O");
    clearerr(input);
    require_abort(fread_overrun, "fread rejects undersized destination");
    fclose(input);
    int standard_stream_checked = check_standard_stream(argc == 3);

    char directory[] = "/tmp/android-fortify-XXXXXX";
    require(mkdtemp(directory) != NULL, "link fixture directory");
    require(snprintf(link_path, sizeof(link_path), "%s/link", directory) < (int)sizeof(link_path),
            "link fixture path");
    const char target[] = "android-native-link";
    require(symlink(target, link_path) == 0, "link fixture");
    memset(buffer, '#', sizeof(buffer));
    require(checked_readlink(link_path, buffer, 8, 8) == 8
            && memcmp(buffer, target, 8) == 0 && buffer[8] == '#', "readlink truncation and bound");
    require(checked_readlink(link_path, buffer, sizeof(buffer), SIZE_MAX) == (ssize_t)strlen(target)
            && memcmp(buffer, target, strlen(target)) == 0, "readlink unknown size");
    require_abort(readlink_overrun, "readlink rejects undersized destination");
    require_abort(readlink_count_overflow, "readlink rejects count above SSIZE_MAX");
    require(unlink(link_path) == 0 && rmdir(directory) == 0, "remove link fixture");
    errno = 0;
    require(checked_readlink(link_path, buffer, sizeof(buffer), sizeof(buffer)) == -1
            && errno == ENOENT, "readlink preserves I/O error");

    require(socketpair(AF_UNIX, SOCK_DGRAM, 0, sockets) == 0, "datagram sockets");
    require(checked_sendto(sockets[0], target, 8, 8, MSG_DONTWAIT, NULL, 0) == 8
            && recv(sockets[1], buffer, sizeof(buffer), 0) == 8
            && memcmp(buffer, target, 8) == 0, "sendto bounded transfer and flags");
    require(checked_sendto(sockets[0], target, 2, SIZE_MAX, 0, NULL, 0) == 2
            && recv(sockets[1], buffer, sizeof(buffer), 0) == 2, "sendto unknown size");
    require(checked_sendto(sockets[0], target, 0, 0, 0, NULL, 0) == 0
            && recv(sockets[1], buffer, sizeof(buffer), 0) == 0, "sendto empty datagram");
    require_abort(sendto_overrun, "sendto rejects undersized source");
    close(sockets[0]);
    close(sockets[1]);
    errno = 0;
    require(checked_sendto(-1, target, 2, sizeof(target), 0, NULL, 0) == -1
            && errno == EBADF, "sendto preserves I/O error");

    memset(buffer, '#', sizeof(buffer));
    errno = E2BIG;
    require(checked_strlcpy(buffer, "android", 8, 8) == 7
            && memcmp(buffer, "android\0", 8) == 0 && buffer[8] == '#'
            && errno == E2BIG, "strlcpy bounded copy and errno");
    memset(buffer, '#', sizeof(buffer));
    errno = E2BIG;
    require(checked_strlcpy(buffer, "android", 4, 4) == 7
            && memcmp(buffer, "and\0", 4) == 0 && buffer[4] == '#'
            && errno == E2BIG, "strlcpy truncation and source length");
    memset(buffer, '#', sizeof(buffer));
    errno = E2BIG;
    require(checked_strlcpy(buffer, "android", 0, 0) == 7
            && buffer[0] == '#' && errno == E2BIG, "strlcpy zero destination bound");
    require(checked_strlcpy(buffer, "android", 1, 1) == 7
            && buffer[0] == '\0' && buffer[1] == '#', "strlcpy one-byte destination");
    memset(buffer, '#', sizeof(buffer));
    errno = E2BIG;
    require(checked_strlcpy(buffer, "native", sizeof(buffer), SIZE_MAX) == 6
            && memcmp(buffer, "native\0", 7) == 0 && buffer[7] == '#'
            && errno == E2BIG, "strlcpy unknown destination size");
    require_abort(strlcpy_overrun, "strlcpy rejects undersized destination before copy");
    require_abort(strlcpy_count_overflow, "strlcpy rejects count above destination size");

    require_abort(assertion_failure, "Android assert aborts");
    printf("ANDROID-FORTIFY-PASS fread=verified readlink=verified sendto=verified strlcpy=verified assert=verified standard-stream=%s\n",
           standard_stream_checked ? "verified" : "skipped");
    return 0;
}
