/* Production lwIP IPv6/dual-stack adapter, including packet and PCB ownership. */
#include <assert.h>
#include <stdlib.h>
#define printf_panic printf
#include "../../kernel/c/vinix_net.c"
#include <lwip/stats.h>
uint32_t vinix_net_random(void) { return 0x12345678; }
uint16_t vinix_ip_randomid(void) { return 1234; }
uint16_t vinix_pick_port(uint16_t first, uint16_t last, vinix_port_taken_fn taken, void *context) {
    for (uint32_t p = first; p <= last; ++p) if (!taken((uint16_t)p, context)) return (uint16_t)p;
    return 0;
}
uint32_t vinix_tcp_isn_bytes(const void *a, uint16_t b, const void *c, uint16_t d, unsigned n) {
    (void)a; (void)b; (void)c; (void)d; assert(n == 4 || n == 16); return 0x12345678;
}
int vinix_virtio_net_send(const void *p, uint64_t n) { (void)p; (void)n; return 0; }
int vinix_apple_wifi_send(const void *p, uint64_t n) { (void)p; (void)n; return 0; }
int vinix_e1000_send(const void *p, uint64_t n) { (void)p; (void)n; return 0; }
/* Keep the original byte-address assertions; adapt only the fixture to the
 * production stack-endpoint interface used by both multicast and unicast. */
struct fixture_address { uint32_t family, scope; uint8_t bytes[16]; };
static struct fixture_address fixture_ipv4(uint32_t address) {
    struct fixture_address a = {.family = 2}; memcpy(a.bytes, &address, 4); return a;
}
static struct vinix_net_endpoint fixture_endpoint(const struct fixture_address *a, uint16_t port) {
    struct vinix_net_endpoint e = {.family = (uint16_t)a->family, .scope = a->scope, .port = port};
    memcpy(e.words, a->bytes, sizeof a->bytes); return e;
}
static void fixture_copy_address(struct fixture_address *a, const struct vinix_net_endpoint *e) {
    a->family = e->family; a->scope = e->scope; memcpy(a->bytes, e->words, sizeof a->bytes);
}
static int fixture_bind(struct vinix_socket *s, const struct fixture_address *a, uint16_t port) {
    struct vinix_net_endpoint e = fixture_endpoint(a, port); return vinix_socket_bind_endpoint(s, &e);
}
static int fixture_connect(struct vinix_socket *s, const struct fixture_address *a, uint16_t port) {
    struct vinix_net_endpoint e = fixture_endpoint(a, port); return vinix_socket_connect_endpoint(s, &e);
}
static int fixture_send(struct vinix_socket *s, const void *data, size_t length,
                        const struct fixture_address *a, uint16_t port, int has_address) {
    struct vinix_net_endpoint e = fixture_endpoint(a, port);
    return vinix_socket_send_endpoint(s, data, length, &e, has_address);
}
static int fixture_recv(struct vinix_socket *s, void *data, size_t length,
                        struct fixture_address *a, uint16_t *port) {
    struct vinix_net_endpoint e; int result = vinix_socket_recv_endpoint(s, data, length, &e);
    if (result >= 0) { fixture_copy_address(a, &e); *port = e.port; } return result;
}
static int fixture_peer(struct vinix_socket *s, struct fixture_address *a, uint16_t *port) {
    struct vinix_net_endpoint e; int result = vinix_socket_name_endpoint(s, &e, 1);
    if (!result) { fixture_copy_address(a, &e); *port = e.port; } return result;
}
static int fixture_ipv6_address(unsigned index, unsigned slot, struct fixture_address *a,
                                unsigned *prefix, unsigned *flags) {
    struct vinix_net_endpoint e; uint32_t state, valid, preferred;
    int result = vinix_net_ipv6_address(index, slot, &e, &state, &valid, &preferred);
    if (result) { fixture_copy_address(a, &e); *prefix = index == 1 ? 128 : 64; *flags = state; }
    return result;
}
uint32_t vinix_tcp_isn(uint32_t a, uint16_t b, uint32_t c, uint16_t d) {
    (void)a; (void)b; (void)c; (void)d; return 0x12345678;
}
uint32_t vinix_tcp_isn6(const uint32_t a[4], uint16_t b, const uint32_t c[4], uint16_t d) {
    (void)a; (void)b; (void)c; (void)d; return 0x12345678;
}
static struct fixture_address loop6(void) {
    struct fixture_address a = {.family = 10}; a.bytes[15] = 1; return a;
}
static struct fixture_address mapped4(void) {
    struct fixture_address a = {.family = 10};
    a.bytes[10] = a.bytes[11] = 255; a.bytes[12] = 127; a.bytes[15] = 1; return a;
}
static void udp_exchange(int mapped) {
    struct vinix_socket *server = vinix_socket_new_family(2, 0, 10);
    struct vinix_socket *client = vinix_socket_new_family(2, 0, mapped ? 2 : 10);
    struct fixture_address local = mapped ? (struct fixture_address){.family = 10} : loop6();
    struct fixture_address remote = mapped ? fixture_ipv4(PP_HTONL(0x7f000001)) : loop6();
    assert(server && client);
    assert(fixture_bind(server, &local, lwip_htons(39411)) == 0);
    assert(fixture_send(client, "IPv6", 4, &remote, lwip_htons(39411), 1) == 4);
    char data[16] = {0}; struct fixture_address peer; uint16_t port;
    assert(fixture_recv(server, data, sizeof data, &peer, &port) == 4);
    assert(memcmp(data, "IPv6", 4) == 0 && peer.family == 10 && port != 0);
    if (mapped) assert(peer.bytes[10] == 255 && peer.bytes[11] == 255 && peer.bytes[12] == 127);
    else assert(peer.bytes[15] == 1);
    assert(fixture_send(server, "reply", 5, &peer, port, 1) == 5);
    assert(vinix_socket_recv(client, data, sizeof data, NULL, NULL) == 5);
    vinix_socket_free(client); vinix_socket_free(server);
}
static void tcp_exchange(int mapped) {
    struct vinix_socket *server = vinix_socket_new_family(1, 0, 10);
    struct vinix_socket *client = vinix_socket_new_family(1, 0, mapped ? 2 : 10);
    struct fixture_address local = mapped ? (struct fixture_address){.family = 10} : loop6();
    struct fixture_address remote = mapped ? fixture_ipv4(PP_HTONL(0x7f000001)) : loop6();
    assert(server && client);
    assert(fixture_bind(server, &local, lwip_htons(39412)) == 0);
    assert(vinix_socket_listen(server, 8) == 0);
    assert(fixture_connect(client, &remote, lwip_htons(39412)) == 0);
    struct vinix_socket *accepted = vinix_socket_accept(server); assert(accepted);
    struct fixture_address peer; uint16_t port;
    assert(fixture_peer(accepted, &peer, &port) == 0 && peer.family == 10);
    assert(peer.bytes[15] == 1);
    if (mapped) assert(peer.bytes[10] == 255 && peer.bytes[12] == 127);
    assert(vinix_socket_send(client, "stream", 6, 0, 0, 0) == 6);
    char data[8] = {0}; assert(vinix_socket_recv(accepted, data, 2, NULL, NULL) == 2);
    vinix_socket_abort_close(client); netif_poll_all();
    assert(vinix_socket_recv(accepted, data + 2, 1, NULL, NULL) == 1);
    assert(vinix_socket_recv(accepted, data + 3, 3, NULL, NULL) == 3);
    assert(memcmp(data, "stream", 6) == 0);
    vinix_socket_free(client);
    vinix_socket_abort_close(accepted); vinix_socket_free(accepted); vinix_socket_free(server);
}
static void router_advertisement(void) {
    uint8_t mac[6] = {0x52, 0x54, 0, 0x12, 0x34, 0x56};
    assert(vinix_net_attach(mac, DRIVER_VIRTIO) == 0);
    uint8_t frame[14 + 40 + 48] = {0};
    frame[0] = frame[1] = 0x33; frame[5] = 1;
    frame[6] = 0x52; frame[7] = 0x54; frame[11] = 1;
    frame[12] = 0x86; frame[13] = 0xdd;
    uint8_t *ip = frame + 14, *ra = ip + 40;
    ip[0] = 0x60; ip[5] = 48; ip[6] = 58; ip[7] = 255;
    ip[8] = 0xfe; ip[9] = 0x80; ip[23] = 1;
    ip[24] = 0xff; ip[25] = 2; ip[39] = 1;
    ra[0] = 134; ra[4] = 64; ra[6] = 7; ra[7] = 8;
    ra[16] = 3; ra[17] = 4; ra[18] = 64; ra[19] = 0xc0;
    ra[21] = 1; ra[22] = 0x51; ra[23] = 0x80;
    ra[25] = 1; ra[26] = 0x51; ra[27] = 0x80;
    ra[32] = 0x20; ra[33] = 1; ra[34] = 0x0d; ra[35] = 0xb8; ra[36] = 0xab; ra[37] = 0xcd;
    ip6_addr_t source, destination;
    memset(&source, 0, sizeof source); memset(&destination, 0, sizeof destination);
    memcpy(source.addr, ip + 8, 16); memcpy(destination.addr, ip + 24, 16);
    struct pbuf *p = pbuf_alloc(PBUF_RAW, 48, PBUF_RAM);
    assert(p && pbuf_take(p, ra, 48) == ERR_OK);
    uint16_t sum = ip6_chksum_pseudo(p, 58, 48, &source, &destination);
    memcpy(ra + 2, &sum, 2); pbuf_free(p);
    assert(vinix_net_input(frame, sizeof frame) == 0);
    int found = 0;
    for (unsigned slot = 1; slot < LWIP_IPV6_NUM_ADDRESSES; ++slot) {
        struct fixture_address a; unsigned prefix, flags;
        if (fixture_ipv6_address(2, slot, &a, &prefix, &flags)) {
            if (memcmp(a.bytes, ra + 32, 8) == 0) found = 1;
        }
    }
    assert(found);
    vinix_net_detach();
    puts("IPV6 HOST PASS: Ethernet router advertisement creates SLAAC address");
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    vinix_net_init();
    struct vinix_socket *s = vinix_socket_new_family(2, 0, 10); assert(s);
    int value = -1; assert(vinix_socket_get_option(s, 41, 26, &value) == 0 && value == 0);
    assert(vinix_socket_set_option(s, 41, 26, 1) == 0);
    struct fixture_address mapped = mapped4();
    assert(fixture_connect(s, &mapped, lwip_htons(9)) == 101);
    struct fixture_address bad = {.family = 10}; bad.bytes[0] = 0xfe; bad.bytes[1] = 0x80; bad.bytes[15] = 1;
    assert(fixture_connect(s, &bad, lwip_htons(9)) == 22);
    bad.scope = 99; assert(fixture_connect(s, &bad, lwip_htons(9)) == 19);
    struct fixture_address any = {.family = 10};
    assert(fixture_bind(s, &any, lwip_htons(39410)) == 0);
    assert(vinix_socket_set_option(s, 41, 26, 0) == 22);
    vinix_socket_free(s);
    udp_exchange(0); udp_exchange(1); tcp_exchange(0); tcp_exchange(1);
    puts("IPV6 HOST PASS: IPv6 TCP/UDP and mapped dual-stack exchange");
    for (int i = 0; i < 20; ++i) udp_exchange(i & 1);
    netif_poll_all();
    unsigned heap_before = lwip_stats.mem.used;
    for (int i = 0; i < 600; ++i) udp_exchange(i & 1);
    printf("IPV6 HOST HEAP: before=%u after=%u bytes delta=%d\n", heap_before, (unsigned)lwip_stats.mem.used, (int)lwip_stats.mem.used - (int)heap_before);
    assert(lwip_stats.mem.used == heap_before);
    assert(udp_pcbs == NULL);
    for (uint32_t t = 0; t <= 6000; t += 250) vinix_net_poll(t);
    puts("IPV6 HOST PASS: 600 repeated datagram exchanges release PCBs");
    router_advertisement();
    return 0;
}
