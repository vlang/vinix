#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <netinet/in.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { printf("SOCKET IO FAIL line=%d errno=%d\n", __LINE__, errno); for (;;) pause(); } } while (0)
static int baseline;
struct heap { long size[32], objects[32], large; int n; };
static void heap_snapshot(struct heap *h)
{
    memset(h, 0, sizeof(*h)); FILE *f = fopen("/proc/slabinfo", "r"); CHECK(f != NULL);
    char line[256]; long index, size, objects, pages;
    while (fgets(line, sizeof line, f)) {
        if (sscanf(line, "size-%ld %ld %ld %ld", &index, &size, &objects, &pages) == 4 && h->n < 32) {
            h->size[h->n] = size; h->objects[h->n++] = objects;
        } else if (sscanf(line, "large - - %ld", &pages) == 1) h->large = pages;
    }
    CHECK(fclose(f) == 0 && h->n > 0);
}
static void sites(const char *path, const char *label)
{
    FILE *f = fopen(path, "r"); CHECK(f != NULL); char line[512];
    while (fgets(line, sizeof line, f)) if (label) printf("PERF-SITE variant=focus scenario=ops round=1 op=%s dir=/tmp %s", label, line);
    CHECK(!ferror(f) && fclose(f) == 0);
}
static void measure(const char *label, void (*operation)(void), int count)
{
    for (int i = 0; i < 20; i++) operation();
    struct heap before, after; heap_snapshot(&before); sites("/proc/allocstart", NULL);
    for (int i = 0; i < count; i++) operation();
    heap_snapshot(&after); sites("/proc/allocsites", label); CHECK(before.n == after.n);
    long kept = (after.large - before.large) * sysconf(_SC_PAGESIZE);
    for (int i = 0; i < before.n; i++) {
        long delta = after.objects[i] - before.objects[i];
        printf("SOCKET IO HEAP op=%s size=%ld delta=%ld\n", label, before.size[i], delta);
        kept += delta * before.size[i]; if (!baseline) CHECK(delta < 32);
    }
    printf("SOCKET IO MEASURE op=%s count=%d retained=%ld large=%ld\n", label, count, kept, after.large - before.large);
    if (!baseline) CHECK(kept < 16384 && after.large - before.large < 2);
}
struct blocking_call { int fd, use_msg; atomic_int entered, done; ssize_t result; char byte; };
static void *blocking_receive(void *data)
{
    struct blocking_call *b = data;
    struct iovec v = { &b->byte, 1 }; struct msghdr m = { .msg_iov = &v, .msg_iovlen = 1 };
    atomic_store(&b->entered, 1);
    b->result = b->use_msg ? recvmsg(b->fd, &m, 0) : recv(b->fd, &b->byte, 1, 0);
    atomic_store(&b->done, 1); return NULL;
}
static void flag_tests(void)
{
    int lost = 0;
    for (int use_msg = 0; use_msg <= 1; use_msg++) {
        printf("SOCKET IO STEP receive mode=%d\n", use_msg);
        int pair[2]; CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
        int alias = dup(pair[1]); CHECK(alias >= 0);
        struct blocking_call b = { .fd = pair[1], .use_msg = use_msg };
        pthread_t thread; CHECK(pthread_create(&thread, NULL, blocking_receive, &b) == 0);
        while (!atomic_load(&b.entered)) usleep(1000);
        usleep(40000); CHECK(!atomic_load(&b.done));
        /* A per-call nonblocking read must not disturb an already blocking alias. */
        char byte = 0;
        for (int i = 0; i < 100; i++) {
            CHECK(recv(alias, &byte, 1, MSG_DONTWAIT) == -1 && errno == EAGAIN);
            CHECK((fcntl(alias, F_GETFL) & O_NONBLOCK) == 0);
        }
        CHECK(!atomic_load(&b.done));
        /* Changing the shared status flags while this call waits must survive its return. */
        CHECK(fcntl(alias, F_SETFL, O_NONBLOCK) == 0);
        CHECK((fcntl(pair[1], F_GETFL) & O_NONBLOCK) != 0);
        puts("SOCKET IO STEP receiver wake"); CHECK(send(pair[0], "x", 1, 0) == 1);
        CHECK(pthread_join(thread, NULL) == 0 && b.result == 1 && b.byte == 'x');
        if (!(fcntl(alias, F_GETFL) & O_NONBLOCK)) lost++;
        CHECK(close(alias) == 0 && close(pair[0]) == 0 && close(pair[1]) == 0);
    }
    printf("SOCKET IO FLAGS lost_updates=%d\n", lost); if (!baseline) CHECK(lost == 0);
    puts("SOCKET IO PASS: flags");
}
static int pair[2], passed_file;
struct sending_call { int fd, use_control; atomic_int entered, done; ssize_t result; };
static void *blocking_send(void *data)
{
    struct sending_call *b = data; char byte = 's';
    union { struct cmsghdr align; char buffer[CMSG_SPACE(sizeof(int))]; } control = {0};
    struct iovec v = {&byte, 1};
    struct msghdr m = {.msg_iov = &v, .msg_iovlen = 1, .msg_control = control.buffer, .msg_controllen = sizeof control};
    struct cmsghdr *c = CMSG_FIRSTHDR(&m); c->cmsg_level = SOL_SOCKET; c->cmsg_type = SCM_RIGHTS; c->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(c), &passed_file, sizeof passed_file);
    atomic_store(&b->entered, 1);
    b->result = b->use_control ? sendmsg(b->fd, &m, 0) : send(b->fd, &byte, 1, 0);
    atomic_store(&b->done, 1); return NULL;
}
static void sender_flag_tests(void)
{
    int lost = 0; char fill[65536]; memset(fill, 'f', sizeof fill);
    for (int controlled = 0; controlled <= 1; controlled++) {
        int sockets[2]; CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
        int alias = dup(sockets[0]); CHECK(alias >= 0); ssize_t n; int chunks = 0;
        while ((n = send(sockets[0], fill, sizeof fill, MSG_DONTWAIT)) > 0) { CHECK(n == sizeof fill); CHECK(++chunks <= 16); }
        CHECK(n == -1 && errno == EAGAIN && chunks == 16);
        struct sending_call b = {.fd = sockets[0], .use_control = controlled}; pthread_t thread;
        CHECK(pthread_create(&thread, NULL, blocking_send, &b) == 0);
        while (!atomic_load(&b.entered)) usleep(1000);
        usleep(40000); CHECK(!atomic_load(&b.done));
        CHECK(fcntl(alias, F_SETFL, O_NONBLOCK) == 0);
        char byte; CHECK(recv(sockets[1], &byte, 1, 0) == 1 && byte == 'f');
        CHECK(pthread_join(thread, NULL) == 0 && b.result == 1);
        if (!(fcntl(alias, F_GETFL) & O_NONBLOCK)) lost++;
        /* The control descriptor still queued after the payload is dropped on close. */
        CHECK(close(alias) == 0 && close(sockets[0]) == 0 && close(sockets[1]) == 0);
    }
    printf("SOCKET IO SENDER FLAGS lost_updates=%d\n", lost); if (!baseline) CHECK(lost == 0);
}
static void datagram(void)
{
    char out[] = "socket-datagram", in[64] = {0}; struct sockaddr_storage addr;
    socklen_t length = sizeof addr;
    CHECK(sendto(pair[0], out, sizeof out, MSG_DONTWAIT, NULL, 0) == sizeof out);
    CHECK(recvfrom(pair[1], in, sizeof in, MSG_DONTWAIT, (void *)&addr, &length) == sizeof out);
    CHECK(!memcmp(out, in, sizeof out));
}
static void message(void)
{
    char a[] = "first", b[] = "second", in[64] = {0}; struct sockaddr_storage addr;
    struct iovec outv[2] = {{a, sizeof a}, {b, sizeof b}}, inv[2] = {{in, sizeof a}, {in + sizeof a, sizeof b}};
    struct msghdr out = {.msg_iov = outv, .msg_iovlen = 2};
    struct msghdr input = {.msg_name = &addr, .msg_namelen = sizeof addr, .msg_iov = inv, .msg_iovlen = 2};
    CHECK(sendmsg(pair[0], &out, MSG_DONTWAIT) == sizeof a + sizeof b);
    CHECK(recvmsg(pair[1], &input, MSG_DONTWAIT) == sizeof a + sizeof b);
    CHECK(!memcmp(in, a, sizeof a) && !memcmp(in + sizeof a, b, sizeof b));
}
static void rights(void)
{
    char byte = 'r', got = 0;
    union { struct cmsghdr align; char buffer[CMSG_SPACE(sizeof(int))]; } control = {0}, received = {0};
    struct iovec outv = {&byte, 1}, inv = {&got, 1};
    struct msghdr out = {.msg_iov = &outv, .msg_iovlen = 1, .msg_control = control.buffer, .msg_controllen = sizeof control};
    struct cmsghdr *c = CMSG_FIRSTHDR(&out); CHECK(c != NULL);
    c->cmsg_level = SOL_SOCKET; c->cmsg_type = SCM_RIGHTS; c->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(c), &passed_file, sizeof passed_file);
    CHECK(sendmsg(pair[0], &out, MSG_DONTWAIT) == 1);
    struct msghdr input = {.msg_iov = &inv, .msg_iovlen = 1, .msg_control = received.buffer, .msg_controllen = sizeof received};
    CHECK(recvmsg(pair[1], &input, MSG_DONTWAIT | MSG_CMSG_CLOEXEC) == 1 && got == 'r');
    c = CMSG_FIRSTHDR(&input); CHECK(c && c->cmsg_level == SOL_SOCKET && c->cmsg_type == SCM_RIGHTS);
    int fd; memcpy(&fd, CMSG_DATA(c), sizeof fd); CHECK(fd >= 0 && (fcntl(fd, F_GETFD) & FD_CLOEXEC));
    CHECK(lseek(fd, 0, SEEK_SET) == 0); char text[5]; CHECK(read(fd, text, sizeof text) == sizeof text && !memcmp(text, "owned", 5));
    CHECK(close(fd) == 0);
}
static void rejected_rights(void)
{
    char byte = 'r'; union { struct cmsghdr align; char buffer[CMSG_SPACE(sizeof(int))]; } control = {0};
    struct iovec v = {&byte, 1}; struct msghdr m = {.msg_iov = &v, .msg_iovlen = 1, .msg_control = control.buffer, .msg_controllen = sizeof control};
    struct cmsghdr *c = CMSG_FIRSTHDR(&m); c->cmsg_level = SOL_SOCKET; c->cmsg_type = SCM_RIGHTS; c->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(c), &passed_file, sizeof passed_file);
    CHECK(sendmsg(pair[0], &m, MSG_DONTWAIT) == -1 && errno == EAGAIN);
}
static void queue_retirement(void)
{
    char byte = 'q', got; int original = passed_file;
    for (int type = SOCK_STREAM; type <= SOCK_SEQPACKET; type++) {
        if (type != SOCK_STREAM && type != SOCK_DGRAM && type != SOCK_SEQPACKET) continue;
        int sockets[2]; CHECK(socketpair(AF_UNIX, type, 0, sockets) == 0);
        passed_file = dup(original); CHECK(passed_file >= 0);
        union { struct cmsghdr align; char buffer[CMSG_SPACE(sizeof(int))]; } control = {0}, input_control = {0};
        struct iovec v = {&byte, 1}; struct msghdr m = {.msg_iov = &v, .msg_iovlen = 1, .msg_control = control.buffer, .msg_controllen = sizeof control};
        struct cmsghdr *c = CMSG_FIRSTHDR(&m); c->cmsg_level = SOL_SOCKET; c->cmsg_type = SCM_RIGHTS; c->cmsg_len = CMSG_LEN(sizeof(int));
        memcpy(CMSG_DATA(c), &passed_file, sizeof passed_file);
        CHECK(sendmsg(sockets[0], &m, MSG_DONTWAIT) == 1 && close(passed_file) == 0);
        struct iovec inv = {&got, 1}; struct msghdr input = {.msg_iov = &inv, .msg_iovlen = 1, .msg_control = input_control.buffer, .msg_controllen = sizeof input_control};
        CHECK(recvmsg(sockets[1], &input, MSG_DONTWAIT | MSG_CMSG_CLOEXEC) == 1 && got == 'q');
        c = CMSG_FIRSTHDR(&input); CHECK(c && c->cmsg_type == SCM_RIGHTS); int received; memcpy(&received, CMSG_DATA(c), sizeof received);
        CHECK(lseek(received, 0, SEEK_SET) == 0); char text[5]; CHECK(read(received, text, 5) == 5 && !memcmp(text, "owned", 5)); CHECK(close(received) == 0);
        /* Plain receive and truncated ancillary delivery both drop queued refs. */
        memcpy(CMSG_DATA(CMSG_FIRSTHDR(&m)), &original, sizeof original);
        CHECK(sendmsg(sockets[0], &m, MSG_DONTWAIT) == 1 && recv(sockets[1], &got, 1, 0) == 1);
        CHECK(sendmsg(sockets[0], &m, MSG_DONTWAIT) == 1);
        input.msg_control = NULL; input.msg_controllen = 0;
        CHECK(recvmsg(sockets[1], &input, MSG_DONTWAIT) == 1 && (input.msg_flags & MSG_CTRUNC));
        CHECK(sendmsg(sockets[0], &m, MSG_DONTWAIT) == 1);
        CHECK(close(sockets[0]) == 0 && close(sockets[1]) == 0);
    }
    passed_file = original;
}
static void fault_tests(void)
{
    char data[4] = "abc", got[4] = {0}; struct iovec v = {(void *)1, sizeof data};
    struct msghdr bad = {.msg_iov = &v, .msg_iovlen = 1};
    CHECK(sendmsg(pair[0], &bad, MSG_DONTWAIT) == -1 && errno == EFAULT);
    CHECK(recv(pair[1], got, sizeof got, MSG_DONTWAIT) == -1 && errno == EAGAIN);
    CHECK(send(pair[0], data, sizeof data, 0) == sizeof data);
    CHECK(recvmsg(pair[1], &bad, MSG_DONTWAIT) == -1 && errno == EFAULT);
    CHECK(recv(pair[1], got, sizeof got, MSG_DONTWAIT) == sizeof got && !memcmp(data, got, sizeof data));
}
static int udp[2]; static struct sockaddr_in udp_address;
static void udp_datagram(void)
{
    char out[] = "udp", in[16] = {0}; struct sockaddr_in source; socklen_t length = sizeof source;
    CHECK(sendto(udp[0], out, sizeof out, MSG_DONTWAIT, (void *)&udp_address, sizeof udp_address) == sizeof out);
    CHECK(recvfrom(udp[1], in, sizeof in, MSG_DONTWAIT, (void *)&source, &length) == sizeof out);
    CHECK(length == sizeof source && source.sin_family == AF_INET && !memcmp(in, out, sizeof out));
}
int main(void)
{
#if defined(__x86_64__)
    /* AMD64's default /dev/console is graphical; report to the runner's UART. */
    int console = open("/dev/com1", O_WRONLY);
    CHECK(console >= 0 && dup2(console, 1) == 1 && dup2(console, 2) == 2 && close(console) == 0);
#endif
    setvbuf(stdout, NULL, _IONBF, 0); baseline = access("/socket-io-baseline", F_OK) == 0;
    puts("SOCKET IO STEP begin"); flag_tests(); CHECK(socketpair(AF_UNIX, SOCK_DGRAM, 0, pair) == 0);
    passed_file = open("/rights-data", O_CREAT | O_RDWR, 0600); CHECK(passed_file >= 0 && write(passed_file, "owned", 5) == 5);
    puts("SOCKET IO STEP rights"); rights(); puts("SOCKET IO STEP faults"); fault_tests(); puts("SOCKET IO STEP queue"); queue_retirement(); puts("SOCKET IO STEP sender"); sender_flag_tests(); puts("SOCKET IO PASS: rights");
    measure("socket_datagram", datagram, 1000); measure("socket_message", message, 1000); measure("socket_rights", rights, 200);
    char *full = malloc(1024 * 1024); CHECK(full != NULL); memset(full, 'b', 1024 * 1024);
    CHECK(send(pair[0], full, 1024 * 1024, MSG_DONTWAIT) == 1024 * 1024);
    measure("socket_rights_rejected", rejected_rights, 200);
    CHECK(recv(pair[1], full, 1024 * 1024, MSG_DONTWAIT) == 1024 * 1024); free(full);
    CHECK(close(pair[0]) == 0 && close(pair[1]) == 0 && close(passed_file) == 0);
    udp[0] = socket(AF_INET, SOCK_DGRAM, 0); udp[1] = socket(AF_INET, SOCK_DGRAM, 0); CHECK(udp[0] >= 0 && udp[1] >= 0);
    udp_address = (struct sockaddr_in){.sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    CHECK(bind(udp[1], (void *)&udp_address, sizeof udp_address) == 0);
    socklen_t length = sizeof udp_address; CHECK(getsockname(udp[1], (void *)&udp_address, &length) == 0);
    measure("socket_udp", udp_datagram, 1000); CHECK(close(udp[0]) == 0 && close(udp[1]) == 0);
    puts("SOCKET IO PASS: growth"); puts("SOCKET IO GUEST: PASS"); for (;;) pause();
}
