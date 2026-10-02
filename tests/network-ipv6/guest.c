#define _GNU_SOURCE
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#define CHECK(x) do { if (!(x)) { printf("IPV6 FAIL: line %d: %s errno=%d\n", __LINE__, #x, errno); return 1; } } while (0)

static struct sockaddr_in6 loop6(unsigned port) {
    struct sockaddr_in6 a = {.sin6_family = AF_INET6, .sin6_port = htons(port)};
    a.sin6_addr.s6_addr[15] = 1; return a;
}
static int exchange(int type, int mapped) {
    int listener = socket(AF_INET6, type, 0); CHECK(listener >= 0);
    int client = socket(mapped ? AF_INET : AF_INET6, type, 0); CHECK(client >= 0);
    struct sockaddr_in6 local = loop6(39431 + type);
    if (mapped) memset(&local.sin6_addr, 0, sizeof local.sin6_addr);
    CHECK(bind(listener, (struct sockaddr *)&local, sizeof local) == 0);
    int server = listener;
    struct sockaddr_in v4 = {.sin_family = AF_INET, .sin_port = local.sin6_port,
                            .sin_addr = {htonl(INADDR_LOOPBACK)}};
    struct sockaddr_in6 remote = loop6(39431 + type);
    struct sockaddr *destination = mapped ? (struct sockaddr *)&v4 : (struct sockaddr *)&remote;
    socklen_t destination_size = mapped ? sizeof(v4) : sizeof(remote);
    if (type == SOCK_STREAM) {
        CHECK(listen(listener, 8) == 0);
        CHECK(connect(client, destination, destination_size) == 0);
        server = accept(listener, NULL, NULL); CHECK(server >= 0);
    }
    CHECK(sendto(client, "IPv6", 4, 0, type == SOCK_DGRAM ? destination : NULL,
                 type == SOCK_DGRAM ? destination_size : 0) == 4);
    char bytes[16] = {0}; struct sockaddr_in6 peer = {0}; socklen_t size = sizeof peer;
    CHECK(recvfrom(server, bytes, sizeof bytes, 0, (struct sockaddr *)&peer, &size) == 4);
    CHECK(memcmp(bytes, "IPv6", 4) == 0 && size == sizeof peer && peer.sin6_family == AF_INET6);
    CHECK(peer.sin6_addr.s6_addr[15] == 1 && peer.sin6_port != 0);
    if (mapped) CHECK(peer.sin6_addr.s6_addr[10] == 255 && peer.sin6_addr.s6_addr[12] == 127);
    size = sizeof peer;
    CHECK(getsockname(server, (struct sockaddr *)&peer, &size) == 0 && size == sizeof peer);
    int v6only = -1; size = sizeof v6only;
    CHECK(getsockopt(server, IPPROTO_IPV6, IPV6_V6ONLY, &v6only, &size) == 0 && v6only == 0);
    int hops = -1; size = sizeof hops;
    CHECK(getsockopt(server, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &hops, &size) == 0 && hops >= 0);
    int domain = 0; size = sizeof domain;
    CHECK(getsockopt(server, SOL_SOCKET, SO_DOMAIN, &domain, &size) == 0 && domain == AF_INET6);
    CHECK(close(client) == 0); CHECK(close(server) == 0);
    if (server != listener) CHECK(close(listener) == 0);
    return 0;
}
static long slab_kib(void) {
    int fd = syscall(SYS_openat, AT_FDCWD, "/proc/meminfo", 0, 0); if (fd < 0) return -1;
    char text[8192]; int n = read(fd, text, sizeof text - 1); close(fd);
    if (n <= 0) return -1;
    text[n] = 0;
    char *p = strstr(text, "Slab:"); return p ? strtol(p + 5, NULL, 10) : -1;
}
struct heap_class { unsigned size; unsigned long long live; };
static int heap_snapshot(struct heap_class classes[32]) {
    int fd = syscall(SYS_openat, AT_FDCWD, "/proc/slabinfo", 0, 0); if (fd < 0) return -1;
    char text[8192]; int n = read(fd, text, sizeof text - 1); close(fd);
    if (n <= 0) return -1;
    text[n] = 0; int count = 0;
    for (char *line = text; line && *line;) {
        char *next = strchr(line, '\n'); if (next) *next++ = 0;
        unsigned size; unsigned long long live;
        if (sscanf(line, "size-%u %*u %llu", &size, &live) == 2) {
            if (count == 32) return -1;
            classes[count++] = (struct heap_class){size, live};
        }
        line = next;
    }
    return count;
}
static int netlink_addresses(void) {
    struct header { unsigned len; unsigned short type, flags; unsigned seq, pid; };
    struct address { unsigned char family, prefix, flags, scope; unsigned index; };
    struct { struct header h; struct address a; } request = {
        .h = {sizeof(request), 22, 0x301, 701, 0}, .a = {.family = AF_INET6}
    };
    int fd = socket(16, SOCK_RAW, 0); CHECK(fd >= 0);
    CHECK(send(fd, &request, sizeof request, 0) == (ssize_t)sizeof request);
    unsigned char answer[2048]; int n = recv(fd, answer, sizeof answer, 0); CHECK(n > 16);
    int found = 0;
    for (int off = 0; off + 16 <= n;) {
        struct header h; memcpy(&h, answer + off, sizeof h);
        CHECK(h.len >= 16 && h.len <= (unsigned)(n - off));
        if (h.type == 20) {
            struct address a; CHECK(h.len >= 24); memcpy(&a, answer + off + 16, sizeof a);
            CHECK(a.family == AF_INET6);
            if (a.index == 1 && a.prefix == 128) {
                for (unsigned at = 24; at + 4 <= h.len;) {
                    unsigned short len, type; memcpy(&len, answer + off + at, 2); memcpy(&type, answer + off + at + 2, 2);
                    CHECK(len >= 4 && at + len <= h.len);
                    if (type == 1 && len == 20 && answer[off + at + 19] == 1) found = 1;
                    at += (len + 3) & ~3u;
                }
            }
        }
        off += (h.len + 3) & ~3u;
    }
    CHECK(found); CHECK(close(fd) == 0);
    return 0;
}
int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    int s = socket(AF_INET6, SOCK_DGRAM, 0); CHECK(s >= 0);
    int value = -1; socklen_t size = sizeof value;
    CHECK(getsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY, &value, &size) == 0 && value == 0);
    value = 1; CHECK(setsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY, &value, sizeof value) == 0);
    struct sockaddr_in6 remote = loop6(9); remote.sin6_addr.s6_addr[10] = remote.sin6_addr.s6_addr[11] = 255;
    remote.sin6_addr.s6_addr[12] = 127;
    CHECK(connect(s, (struct sockaddr *)&remote, sizeof remote) == -1 && errno == ENETUNREACH);
    remote = loop6(0); CHECK(bind(s, (struct sockaddr *)&remote, sizeof remote) == 0);
    value = 0; CHECK(setsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY, &value, sizeof value) == -1 && errno == EINVAL);
    CHECK(close(s) == 0);
    CHECK(exchange(SOCK_DGRAM, 0) == 0); CHECK(exchange(SOCK_DGRAM, 1) == 0);
    CHECK(exchange(SOCK_STREAM, 0) == 0); CHECK(exchange(SOCK_STREAM, 1) == 0);
    puts("IPV6 PASS: TCP UDP dual-stack socket ABI");
    CHECK(netlink_addresses() == 0);
    puts("IPV6 PASS: rtnetlink IPv6 loopback reporting");
    for (int i = 0; i < 20; ++i) { CHECK(exchange(SOCK_DGRAM, i & 1) == 0); CHECK(netlink_addresses() == 0); }
    struct heap_class baseline[32], measured[32];
    CHECK(heap_snapshot(baseline) > 0); CHECK(slab_kib() >= 0);
    usleep(2500000);
    int classes = heap_snapshot(baseline); CHECK(classes > 0);
    long before = slab_kib();
    for (int i = 0; i < 500; ++i) { CHECK(exchange(SOCK_DGRAM, i & 1) == 0); CHECK(netlink_addresses() == 0); }
    long after = slab_kib();
    CHECK(heap_snapshot(measured) == classes);
    int grew = 0;
    for (int i = 0; i < classes; ++i) {
        CHECK(measured[i].size == baseline[i].size);
        long delta = (long)measured[i].live - (long)baseline[i].live;
        printf("IPV6 CLASS: size=%u before=%llu after=%llu delta=%ld objects\n",
               measured[i].size, baseline[i].live, measured[i].live, delta);
        if (delta > 0) grew = 1;
    }
    CHECK(!grew);
    printf("IPV6 SLAB: before=%ld KiB after=%ld KiB delta=%ld KiB operations=500\n", before, after, after-before);
    CHECK(before >= 0 && after <= before + 16);
    puts("IPV6 PASS: repeated socket path allocation measurement");
    for (;;) pause();
}
