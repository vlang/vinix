/* End-to-end AF_INET smoke test.  It is freestanding so it can be installed as
 * /sbin/init in a tiny diagnostic initramfs without trusting a libc first. */
typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long u64;
typedef long i64;

struct sockaddr_in {
    u16 family;
    u16 port;
    u32 address;
    u8 zero[8];
};

struct timespec { i64 seconds, nanoseconds; };

static i64 call1(u64 number, u64 a) {
    register u64 x8 __asm__("x8") = number;
    register u64 x0 __asm__("x0") = a;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8) : "memory");
    return (i64)x0;
}

static i64 call2(u64 number, u64 a, u64 b) {
    register u64 x8 __asm__("x8") = number;
    register u64 x0 __asm__("x0") = a;
    register u64 x1 __asm__("x1") = b;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1) : "memory");
    return (i64)x0;
}

static i64 call3(u64 number, u64 a, u64 b, u64 c) {
    register u64 x8 __asm__("x8") = number;
    register u64 x0 __asm__("x0") = a;
    register u64 x1 __asm__("x1") = b;
    register u64 x2 __asm__("x2") = c;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory");
    return (i64)x0;
}

static i64 call4(u64 number, u64 a, u64 b, u64 c, u64 d) {
    register u64 x8 __asm__("x8") = number;
    register u64 x0 __asm__("x0") = a;
    register u64 x1 __asm__("x1") = b;
    register u64 x2 __asm__("x2") = c;
    register u64 x3 __asm__("x3") = d;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3) : "memory");
    return (i64)x0;
}

static i64 call5(u64 number, u64 a, u64 b, u64 c, u64 d, u64 e) {
    register u64 x8 __asm__("x8") = number;
    register u64 x0 __asm__("x0") = a;
    register u64 x1 __asm__("x1") = b;
    register u64 x2 __asm__("x2") = c;
    register u64 x3 __asm__("x3") = d;
    register u64 x4 __asm__("x4") = e;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2),
                     "r"(x3), "r"(x4) : "memory");
    return (i64)x0;
}

static i64 call6(u64 number, u64 a, u64 b, u64 c, u64 d, u64 e, u64 f) {
    register u64 x8 __asm__("x8") = number;
    register u64 x0 __asm__("x0") = a;
    register u64 x1 __asm__("x1") = b;
    register u64 x2 __asm__("x2") = c;
    register u64 x3 __asm__("x3") = d;
    register u64 x4 __asm__("x4") = e;
    register u64 x5 __asm__("x5") = f;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2),
                     "r"(x3), "r"(x4), "r"(x5) : "memory");
    return (i64)x0;
}

static u64 length(const char *text) {
    u64 n = 0;
    while (text[n]) n++;
    return n;
}

static void print(const char *text) { call3(64, 1, (u64)text, length(text)); }
static void close_fd(int fd) { call1(57, (u64)fd); }
static void pause(void) {
    struct timespec duration = {0, 100000000};
    call2(101, (u64)&duration, 0);
}

static u16 network_short(u16 value) { return (u16)((value << 8) | (value >> 8)); }
static u32 ipv4(u8 a, u8 b, u8 c, u8 d) {
    return (u32)a | (u32)b << 8 | (u32)c << 16 | (u32)d << 24;
}

static int same(const void *left, const void *right, u64 n) {
    const u8 *a = left, *b = right;
    while (n--) if (*a++ != *b++) return 0;
    return 1;
}

static int loopback_tcp(void) {
    struct sockaddr_in address = {2, network_short(32123), 0x0100007f, {0}};
    char input[8] = {0};
    int server = (int)call3(198, 2, 1, 0);
    int client = -1, accepted = -1;
    if (server < 0 || call3(200, server, (u64)&address, sizeof(address)) < 0 ||
        call2(201, server, 8) < 0) goto fail;
    client = (int)call3(198, 2, 1, 0);
    if (client < 0 || call3(203, client, (u64)&address, sizeof(address)) < 0) goto fail;
    accepted = (int)call3(202, server, 0, 0);
    if (accepted < 0 || call3(64, client, (u64)"hello", 5) != 5 ||
        call3(63, accepted, (u64)input, 5) != 5 || !same(input, "hello", 5)) goto fail;
    close_fd(accepted); close_fd(client); close_fd(server);
    return 1;
fail:
    if (accepted >= 0) close_fd(accepted);
    if (client >= 0) close_fd(client);
    if (server >= 0) close_fd(server);
    return 0;
}

static int loopback_udp(void) {
    struct sockaddr_in destination = {2, network_short(32124), 0x0100007f, {0}};
    struct sockaddr_in source = {0};
    u32 source_length = sizeof(source);
    char input[8] = {0};
    int server = (int)call3(198, 2, 2, 0);
    int client = -1;
    if (server < 0 || call3(200, server, (u64)&destination, sizeof(destination)) < 0) goto fail;
    client = (int)call3(198, 2, 2, 0);
    if (client < 0 || call6(206, client, (u64)"udp", 3, 0,
                            (u64)&destination, sizeof(destination)) != 3) goto fail;
    if (call6(207, server, (u64)input, sizeof(input), 0,
              (u64)&source, (u64)&source_length) != 3 ||
        !same(input, "udp", 3) || source.family != 2) goto fail;
    close_fd(client); close_fd(server);
    return 1;
fail:
    if (client >= 0) close_fd(client);
    if (server >= 0) close_fd(server);
    return 0;
}

static int socket_options(void) {
    int fd = (int)call3(198, 2, 2, 0);
    int value = 0x48;
    int result = 0;
    u32 result_length = sizeof(result);
    if (fd < 0) return 0;
    if (call5(208, fd, 0, 1, (u64)&value, sizeof(value)) < 0 ||
        call5(209, fd, 0, 1, (u64)&result, (u64)&result_length) < 0 ||
        result != value || result_length != sizeof(result)) {
        close_fd(fd);
        return 0;
    }
    value = 1;
    result = 0;
    result_length = sizeof(result);
    if (call5(208, fd, 1, 6, (u64)&value, sizeof(value)) < 0 ||
        call5(209, fd, 1, 6, (u64)&result, (u64)&result_length) < 0 ||
        result != value) {
        close_fd(fd);
        return 0;
    }
    close_fd(fd);
    return 1;
}

static int dns_query(void) {
    /* A query for example.com, transaction 0x564e. */
    u8 query[] = {0x56,0x4e, 0x01,0x00, 0x00,0x01, 0,0, 0,0, 0,0,
                  7,'e','x','a','m','p','l','e', 3,'c','o','m',0, 0,1, 0,1};
    u8 reply[512];
    struct sockaddr_in dns = {2, network_short(53), 0, {0}};
    int fd = (int)call3(198, 2, 2, 0);
    if (fd < 0) return 0;
    for (int attempt = 0; attempt < 80; attempt++) {
        /* QEMU user networking advertises 10.0.2.3 through DHCP. */
        dns.address = ipv4(10, 0, 2, 3);
        i64 sent = call6(206, fd, (u64)query, sizeof(query), 0,
                         (u64)&dns, sizeof(dns));
        if (sent == (i64)sizeof(query)) {
            i64 got = call6(207, fd, (u64)reply, sizeof(reply), 0, 0, 0);
            if (got >= 12 && reply[0] == 0x56 && reply[1] == 0x4e &&
                (reply[2] & 0x80) != 0) {
                close_fd(fd);
                return 1;
            }
        }
        pause();
    }
    close_fd(fd);
    return 0;
}

void _start(void) {
    int failures = 0;
    print("NET TEST START\n");
    if (loopback_tcp()) print("PASS tcp loopback\n");
    else { print("FAIL tcp loopback\n"); failures++; }
    if (loopback_udp()) print("PASS udp loopback\n");
    else { print("FAIL udp loopback\n"); failures++; }
    if (socket_options()) print("PASS IPv4 socket options\n");
    else { print("FAIL IPv4 socket options\n"); failures++; }
    if (dns_query()) print("PASS dhcp dns udp\n");
    else { print("FAIL dhcp dns udp\n"); failures++; }
    print(failures ? "NET TEST FAILED\n" : "NET TEST PASSED\n");
    call1(93, failures);
    for (;;) { }
}
