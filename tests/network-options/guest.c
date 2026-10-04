/* Linux ABI coverage for the implemented socket controls and rtnetlink errors. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <signal.h>
#include <sys/time.h>
#include <time.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { printf("NETWORK OPTIONS FAIL line %d: %s errno=%d\n", __LINE__, #x, errno); return 1; } } while (0)
struct nl_header { unsigned length; unsigned short type, flags; unsigned sequence, pid; };
struct nl_address { unsigned short family, pad; unsigned pid, groups; };
struct nl_link { unsigned char family, pad; unsigned short type; int index; unsigned flags, change; };

static int setting(int fd, int level, int option, int requested, int expected) {
    int result = 0; socklen_t n = sizeof(result);
    return setsockopt(fd, level, option, &requested, sizeof(requested)) == 0 &&
        getsockopt(fd, level, option, &result, &n) == 0 && result == expected && n == sizeof(result);
}

static int test_options(void) {
    int s = socket(AF_INET, SOCK_STREAM, 0);
    CHECK(s >= 0);
    CHECK(setting(s, SOL_SOCKET, SO_KEEPALIVE, 17, 1));
    CHECK(setting(s, IPPROTO_TCP, TCP_KEEPIDLE, 2, 2));
    CHECK(setting(s, IPPROTO_TCP, TCP_KEEPINTVL, 3, 3));
    CHECK(setting(s, IPPROTO_TCP, TCP_KEEPCNT, 4, 4));
    CHECK(setting(s, SOL_SOCKET, SO_SNDBUF, 2048, 4096));
    CHECK(setting(s, SOL_SOCKET, SO_RCVBUF, 4096, 8192));
    int invalid = 0;
    CHECK(setsockopt(s, IPPROTO_TCP, TCP_KEEPIDLE, &invalid, sizeof(invalid)) == -1 && errno == EINVAL);
    struct linger linger = {1, -1};
    CHECK(setsockopt(s, SOL_SOCKET, SO_LINGER, &linger, sizeof(linger)) == -1 && errno == EINVAL);
    invalid = 1;
    CHECK(setsockopt(s, SOL_SOCKET, SO_OOBINLINE, &invalid, sizeof(invalid)) == -1 && errno == ENOPROTOOPT);
    CHECK(close(s) == 0);
    s = socket(AF_INET, SOCK_DGRAM, 0); CHECK(s >= 0);
    CHECK(setting(s, SOL_SOCKET, SO_SNDBUF, 2048, 4096));
    char data[5000] = {0};
    struct sockaddr_in remote = { .sin_family = AF_INET, .sin_port = htons(1234), .sin_addr = { htonl(INADDR_LOOPBACK) } };
    CHECK(sendto(s, data, sizeof(data), 0, (struct sockaddr *)&remote, sizeof(remote)) == -1 && errno == EMSGSIZE);
    CHECK(close(s) == 0);
    puts("NETWORK OPTIONS PASS: transport settings and bounds");
    return 0;
}

static int test_netlink(void) {
    int s = socket(16, SOCK_RAW, 0); CHECK(s >= 0);
    struct nl_address kernel = { .family = 16 };
    struct { struct nl_header header; struct nl_link link; } request = {
        .header = { sizeof(request), 16, 1 | 4, 123, 0 },
        .link = { .index = 1, .flags = 1, .change = 1 }
    };
    unsigned char answer[256] = {0};
    CHECK(sendto(s, &request, sizeof(request), 0, (struct sockaddr *)&kernel, sizeof(kernel)) == sizeof(request));
    int n = recv(s, answer, sizeof(answer), 0); CHECK(n >= 36);
    struct nl_header *header = (struct nl_header *)answer;
    int error; memcpy(&error, answer + sizeof(*header), sizeof(error));
    CHECK(header->type == 2 && header->sequence == 123 && error == -EOPNOTSUPP);
    request.header.flags = 1; request.header.sequence++;
    CHECK(sendto(s, &request, sizeof(request), 0, (struct sockaddr *)&kernel, sizeof(kernel)) == sizeof(request));
    n = recv(s, answer, sizeof(answer), 0); CHECK(n >= 36);
    memcpy(&error, answer + sizeof(*header), sizeof(error));
    CHECK(header->type == 2 && header->sequence == 124 && error == -EOPNOTSUPP);
    CHECK(setting(s, SOL_SOCKET, SO_RCVBUF, 2048, 4096));
    CHECK(setting(s, SOL_SOCKET, SO_SNDBUF, 2048, 4096));
    int queued = 0;
    for (; queued < 200; ++queued) {
        ssize_t sent = sendto(s, &request, sizeof(request), 0, (struct sockaddr *)&kernel, sizeof(kernel));
        if (sent == -1) { CHECK(errno == ENOBUFS); break; }
        CHECK(sent == sizeof(request));
    }
    CHECK(queued >= 2 && queued <= 4);
    for (int i = 0; i < queued; ++i) CHECK(recv(s, answer, sizeof(answer), 0) == 36);
    CHECK(sendto(s, &request, sizeof(request), 0, (struct sockaddr *)&kernel, sizeof(kernel)) == sizeof(request));
    CHECK(recv(s, answer, sizeof(answer), 0) == 36);
    unsigned char oversized[5000] = {0};
    CHECK(sendto(s, oversized, sizeof(oversized), 0, (struct sockaddr *)&kernel, sizeof(kernel)) == -1 && errno == EMSGSIZE);
    CHECK(close(s) == 0);
    puts("NETWORK OPTIONS PASS: unsupported network changes fail");
    return 0;
}

static int test_linger(void) {
    int listener = socket(AF_INET, SOCK_STREAM, 0); CHECK(listener >= 0);
    struct sockaddr_in address = { .sin_family = AF_INET, .sin_port = htons(31991), .sin_addr = { htonl(INADDR_LOOPBACK) } };
    CHECK(bind(listener, (struct sockaddr *)&address, sizeof(address)) == 0 && listen(listener, 8) == 0);
    int client = socket(AF_INET, SOCK_STREAM, 0); CHECK(client >= 0);
    CHECK(connect(client, (struct sockaddr *)&address, sizeof(address)) == 0);
    int receiver = accept(listener, NULL, NULL); CHECK(receiver >= 0);
    CHECK(fcntl(client, F_SETFL, O_NONBLOCK) == 0);
    char data[4096] = {0}; int total = 0;
    for (int attempt = 0; attempt < 100; ++attempt) {
        int n = write(client, data, sizeof(data));
        if (n < 0) { CHECK(errno == EAGAIN); break; }
        total += n;
    }
    CHECK(total > 20000);
    struct linger linger = {1, 1}; CHECK(setsockopt(client, SOL_SOCKET, SO_LINGER, &linger, sizeof(linger)) == 0);
    struct timespec begin, end; CHECK(clock_gettime(1, &begin) == 0);
    CHECK(close(client) == 0); CHECK(clock_gettime(1, &end) == 0);
    long long ns = (end.tv_sec - begin.tv_sec) * 1000000000LL + end.tv_nsec - begin.tv_nsec;
    CHECK(ns >= 800000000 && ns < 4000000000LL);
    CHECK(close(receiver) == 0 && close(listener) == 0);
    puts("NETWORK OPTIONS PASS: linger waits and times out");
    return 0;
}

static int test_exit_linger(void) {
    int listener = socket(AF_INET, SOCK_STREAM, 0); CHECK(listener >= 0);
    struct sockaddr_in address = { .sin_family = AF_INET, .sin_port = htons(31992), .sin_addr = { htonl(INADDR_LOOPBACK) } };
    CHECK(bind(listener, (struct sockaddr *)&address, sizeof(address)) == 0 && listen(listener, 8) == 0);
    pid_t child = fork(); CHECK(child >= 0);
    if (child == 0) {
        int client = socket(AF_INET, SOCK_STREAM, 0);
        if (client < 0 || connect(client, (struct sockaddr *)&address, sizeof(address)) != 0 ||
            fcntl(client, F_SETFL, O_NONBLOCK) != 0) _exit(2);
        char data[4096] = {0};
        for (int attempt = 0; attempt < 100; ++attempt) {
            if (write(client, data, sizeof(data)) < 0) break;
        }
        struct linger linger = {1, 60};
        if (setsockopt(client, SOL_SOCKET, SO_LINGER, &linger, sizeof(linger)) != 0) _exit(3);
        _exit(0);
    }
    int receiver = accept(listener, NULL, NULL); CHECK(receiver >= 0);
    int status = 0, finished = 0;
    struct timespec delay = {0, 10000000};
    for (int attempt = 0; attempt < 300; ++attempt) {
        if (waitpid(child, &status, WNOHANG) == child) { finished = 1; break; }
        nanosleep(&delay, NULL);
    }
    CHECK(finished && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    CHECK(close(receiver) == 0 && close(listener) == 0);
    puts("NETWORK OPTIONS PASS: exit keeps linger in background");
    return 0;
}

int main(void) {
    setbuf(stdout, NULL);
    /* amd64's primary console is the framebuffer; mirror the ABI test to
     * its serial device, as the existing kernel guest regressions do. */
    int console = open("/dev/com1", O_WRONLY);
    if (console >= 0) {
        dup2(console, STDOUT_FILENO); dup2(console, STDERR_FILENO); close(console);
    }
    if (test_options() || test_netlink() || test_linger() || test_exit_linger()) return 1;
    puts("NETWORK OPTIONS GUEST: PASS");
    return 0;
}
