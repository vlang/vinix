/* Linux listen(2) backlog boundaries and an already queued UNIX connection. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

static int listener = -1, client = -1, peer = -1;
static char socket_path[sizeof(((struct sockaddr_un *)0)->sun_path)];

static void cleanup(void) {
    if (peer >= 0) close(peer);
    if (client >= 0) close(client);
    if (listener >= 0) close(listener);
    peer = client = listener = -1;
    if (socket_path[0]) unlink(socket_path);
    socket_path[0] = '\0';
}

static void require(int condition, const char *operation) {
    if (!condition) {
        int saved_errno = errno;
        fprintf(stderr, "LISTEN-BACKLOG-FAIL %s errno=%d\n", operation, saved_errno);
        cleanup();
        exit(1);
    }
}

static long long monotonic_ms(void) {
    struct timespec now;
    require(clock_gettime(CLOCK_MONOTONIC, &now) == 0, "read monotonic clock");
    return (long long)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static void ready(int fd, short events, const char *operation) {
    struct pollfd watched = {.fd = fd, .events = events};
    long long deadline = monotonic_ms() + 5000;
    for (;;) {
        long long remaining = deadline - monotonic_ms();
        require(remaining > 0, operation);
        int result = poll(&watched, 1, (int)remaining);
        if (result < 0 && errno == EINTR) continue;
        require(result == 1 && (watched.revents & events), operation);
        return;
    }
}

static void listen_promptly(int backlog) {
    long long start = monotonic_ms();
    require(listen(listener, backlog) == 0, "listen succeeds");
    require(monotonic_ms() - start < 5000, "listen returns within five seconds");
}

static void raw_listen_promptly(int backlog) {
    /* The Linux ABI ignores register bits above the int argument's low word. */
    unsigned long long argument = (1ULL << 32) | (uint32_t)backlog;
    long long start = monotonic_ms();
    require(syscall(SYS_listen, listener, argument) == 0, "raw listen truncates upper word");
    require(monotonic_ms() - start < 5000, "raw listen returns within five seconds");
}

static void send_byte(int fd, unsigned char value) {
    ready(fd, POLLOUT, "socket becomes writable");
    require(send(fd, &value, 1, MSG_NOSIGNAL) == 1, "send one byte");
}

static void receive_byte(int fd, unsigned char expected) {
    unsigned char value = 0;
    ready(fd, POLLIN, "socket becomes readable");
    require(recv(fd, &value, 1, 0) == 1, "receive one byte");
    require(value == expected, "received byte matches peer");
}

static void exercise(int backlog, unsigned int index) {
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    int written = snprintf(socket_path, sizeof socket_path,
                           "/tmp/vinix-listen-%ld-%u.sock", (long)getpid(), index);
    require(written > 0 && (size_t)written < sizeof socket_path, "socket pathname fits");
    memcpy(address.sun_path, socket_path, (size_t)written + 1);
    socklen_t address_length = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + written + 1);
    require(unlink(socket_path) == 0 || errno == ENOENT, "remove stale endpoint");
    listener = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    require(listener >= 0, "create nonblocking listener");
    require(bind(listener, (struct sockaddr *)&address, address_length) == 0, "bind listener");
    printf("LISTEN-BACKLOG-BEGIN backlog=%d\n", backlog);
    raw_listen_promptly(backlog);
    listen_promptly(backlog);

    client = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    require(client >= 0, "create nonblocking client");
    int connected = connect(client, (struct sockaddr *)&address, address_length);
    require(connected == 0 || (connected < 0 && errno == EINPROGRESS), "connect client");
    if (connected < 0) {
        ready(client, POLLOUT, "connection completes");
        int error = -1;
        socklen_t length = sizeof error;
        require(getsockopt(client, SOL_SOCKET, SO_ERROR, &error, &length) == 0 && error == 0,
                "connection has no socket error");
    }

    /* These bytes and the pending endpoint must survive both listen calls. */
    unsigned char request = (unsigned char)(0x40 + index);
    send_byte(client, request);
    listen_promptly(-1);
    listen_promptly(0);
    ready(listener, POLLIN, "queued connection survives repeated listen");
    peer = accept4(listener, NULL, NULL, SOCK_NONBLOCK | SOCK_CLOEXEC);
    require(peer >= 0, "accept queued connection");
    receive_byte(peer, request);
    send_byte(peer, (unsigned char)(request + 1));
    receive_byte(client, (unsigned char)(request + 1));

    require(close(peer) == 0, "close accepted endpoint");
    peer = -1;
    require(close(client) == 0, "close client endpoint");
    client = -1;
    require(close(listener) == 0, "close listener endpoint");
    listener = -1;
    require(unlink(socket_path) == 0, "unlink listener endpoint");
    socket_path[0] = '\0';
    printf("LISTEN-BACKLOG-CASE-PASS backlog=%d queued_connection=preserved\n", backlog);
}

int main(void) {
    static const int backlogs[] = {-1, INT_MIN, INT_MAX, 0, 1, 128, 4096};
    setvbuf(stdout, NULL, _IONBF, 0);
    for (unsigned int i = 0; i < sizeof backlogs / sizeof backlogs[0]; i++)
        exercise(backlogs[i], i);
    puts("LISTEN-BACKLOG-PASS cases=7");
    return 0;
}
