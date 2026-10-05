/* Exercise the production raw lwIP glue on the host, including timer output,
 * socket queue limits and listener inheritance. No mocked transport API. */
#include <assert.h>
#include <stdarg.h>
#include <stdlib.h>
#define printf_panic printf
#include "core_fixture.h"

uint32_t vinix_net_random(void) { return 0x12345678; }
uint16_t vinix_ip_randomid(void) { return 1234; }
uint16_t vinix_pick_port(uint16_t first, uint16_t last,
                       vinix_port_taken_fn taken, void *context) {
    for (uint32_t p = first; p <= last; ++p) if (!taken((uint16_t)p, context)) return (uint16_t)p;
    return 0;
}
uint32_t vinix_tcp_isn(uint32_t a, uint16_t b, uint32_t c, uint16_t d) {
    (void)a; (void)b; (void)c; (void)d; return 0x12345678;
}
uint32_t vinix_tcp_isn_bytes(const void *a, uint16_t b, const void *c, uint16_t d, unsigned n) {
    (void)a; (void)b; (void)c; (void)d; (void)n; return 0x12345678;
}
uint32_t vinix_tcp_isn6(const uint32_t a[4], uint16_t b, const uint32_t c[4], uint16_t d) {
    (void)a; (void)b; (void)c; (void)d; return 0x12345678;
}
int vinix_virtio_net_send(const void *p, uint64_t n) { (void)p; (void)n; return 0; }
int vinix_apple_wifi_send(const void *p, uint64_t n) { (void)p; (void)n; return 0; }
int vinix_e1000_send(const void *p, uint64_t n) { (void)p; (void)n; return 0; }

static int keepalive_probes;
static int syn_sack, syn_timestamp, timestamp_echo, sack_reply, fail_output;
static err_t wire_output(struct netif *netif, struct pbuf *p, const ip4_addr_t *ip) {
    unsigned char header[80];
    (void)netif; (void)ip;
    pbuf_copy_partial(p, header, sizeof(header), 0);
    unsigned ihl = (header[0] & 15) * 4;
    unsigned thl = (header[ihl + 12] >> 4) * 4;
    if (header[9] == 6) {
        for (unsigned at = ihl + 20; at < ihl + thl;) {
            unsigned kind = header[at++];
            if (kind == 0) break;
            if (kind == 1) continue;
            assert(at < ihl + thl);
            unsigned length = header[at++];
            assert(length >= 2 && at + length - 2 <= ihl + thl);
            if (kind == 4 && length == 2) syn_sack = 1;
            if (kind == 8 && length == 10) {
                syn_timestamp = 1;
                if (header[ihl + 13] == 0x10 && header[at + 4] == 0 && header[at + 5] == 0 &&
                    header[at + 6] == 0 && header[at + 7] == 100) timestamp_echo = 1;
            }
            if (kind == 5 && length >= 10) sack_reply = 1;
            at += length - 2;
        }
    }
    if (header[9] == 6 && header[ihl + 13] == 0x10 &&
        p->tot_len == ihl + thl) keepalive_probes++;
    return fail_output ? ERR_IF : ERR_OK;
}

static uint16_t checksum(const uint8_t *bytes, unsigned n, uint32_t sum) {
    for (unsigned i = 0; i + 1 < n; i += 2) sum += ((unsigned)bytes[i] << 8) | bytes[i + 1];
    if (n & 1) sum += (unsigned)bytes[n - 1] << 8;
    while (sum >> 16) sum = (sum & 65535) + (sum >> 16);
    return (uint16_t)~sum;
}
static void be16(uint8_t *p, uint16_t n) { p[0] = n >> 8; p[1] = n; }
static void be32(uint8_t *p, uint32_t n) { p[0] = n >> 24; p[1] = n >> 16; p[2] = n >> 8; p[3] = n; }

static void answer_syn(struct vinix_socket *s) {
    uint8_t bytes[56] = {0};
    bytes[0] = 0x45; be16(bytes + 2, sizeof(bytes)); bytes[8] = 64; bytes[9] = 6;
    memcpy(bytes + 12, &ip_2_ip4(&s->tcp->remote_ip)->addr, 4);
    memcpy(bytes + 16, &ip_2_ip4(&s->tcp->local_ip)->addr, 4);
    be16(bytes + 20, s->tcp->remote_port); be16(bytes + 22, s->tcp->local_port);
    be32(bytes + 24, 1000); be32(bytes + 28, s->tcp->snd_nxt);
    bytes[32] = 0x90; bytes[33] = 0x12;
    bytes[40] = 1; bytes[41] = 1; bytes[42] = 4; bytes[43] = 2;
    bytes[44] = 1; bytes[45] = 1; bytes[46] = 8; bytes[47] = 10; be32(bytes + 48, 100); be16(bytes + 34, 32768);
    uint32_t pseudo = 6 + 36;
    for (int i = 12; i < 20; i += 2) pseudo += ((unsigned)bytes[i] << 8) | bytes[i + 1];
    be16(bytes + 36, checksum(bytes + 20, 36, pseudo));
    be16(bytes + 10, checksum(bytes, 20, 0));
    struct pbuf *p = pbuf_alloc(PBUF_RAW, sizeof(bytes), PBUF_RAM);
    assert(p && pbuf_take(p, bytes, sizeof(bytes)) == ERR_OK);
    assert(ip4_input(p, &physical_netif) == ERR_OK);
    assert(s->connected && s->tcp->state == ESTABLISHED &&
           (s->tcp->flags & TF_SACK) && (s->tcp->flags & TF_TIMESTAMP) && timestamp_echo);
}

static void incoming_data(struct vinix_socket *s, uint32_t seq, const char *data) {
    uint8_t bytes[62] = {0};
    bytes[0] = 0x45; be16(bytes + 2, sizeof(bytes)); bytes[8] = 64; bytes[9] = 6;
    memcpy(bytes + 12, &ip_2_ip4(&s->tcp->remote_ip)->addr, 4);
    memcpy(bytes + 16, &ip_2_ip4(&s->tcp->local_ip)->addr, 4);
    be16(bytes + 20, s->tcp->remote_port); be16(bytes + 22, s->tcp->local_port);
    be32(bytes + 24, seq); be32(bytes + 28, s->tcp->snd_nxt);
    bytes[32] = 0x80; bytes[33] = 0x18; be16(bytes + 34, 32768);
    bytes[40] = 1; bytes[41] = 1; bytes[42] = 8; bytes[43] = 10; be32(bytes + 44, 101);
    memcpy(bytes + 52, data, 10);
    uint32_t pseudo = 6 + 42;
    for (int i = 12; i < 20; i += 2) pseudo += ((unsigned)bytes[i] << 8) | bytes[i + 1];
    be16(bytes + 36, checksum(bytes + 20, 42, pseudo));
    be16(bytes + 10, checksum(bytes, 20, 0));
    struct pbuf *p = pbuf_alloc(PBUF_RAW, sizeof(bytes), PBUF_RAM);
    assert(p && pbuf_take(p, bytes, sizeof(bytes)) == ERR_OK);
    assert(ip4_input(p, &physical_netif) == ERR_OK);
}

static void test_keepalive_wire(void) {
    struct vinix_socket *s = vinix_socket_new(VINIX_NET_STREAM, 0);
    assert(s);
    assert(vinix_socket_set_option(s, 1, 9, 1) == 0);
    assert(vinix_socket_set_option(s, 6, 4, 1) == 0);
    assert(vinix_socket_set_option(s, 6, 5, 1) == 0);
    assert(vinix_socket_set_option(s, 6, 6, 2) == 0);
    assert(vinix_socket_set_option(s, 6, 5, 0) == 22);
    assert(vinix_socket_set_option(s, 6, 6, 128) == 22);
    assert(vinix_socket_connect(s, PP_HTONL(0x0a000202), lwip_htons(7777)) == 115);
    assert(syn_sack && syn_timestamp);
    answer_syn(s);
    incoming_data(s, 1011, "klmnopqrst");
    assert(sack_reply && s->rx_head == NULL);
    incoming_data(s, 1001, "abcdefghij");
    char received[20] = {0};
    int count = vinix_socket_recv(s, received, sizeof(received), NULL, NULL);
    if (count < 20) count += vinix_socket_recv(s, received + count, sizeof(received) - count, NULL, NULL);
    assert(count == 20 && memcmp(received, "abcdefghijklmnopqrst", 20) == 0);
    keepalive_probes = 0;
    for (uint32_t now = 250; now <= 2500; now += 250) vinix_net_poll(now);
    assert(keepalive_probes >= 1);
    for (uint32_t now = 2750; now <= 6000; now += 250) vinix_net_poll(now);
    assert(s->tcp == NULL && s->error != 0);
    vinix_socket_free(s);
}

static void test_receive_and_send_limits(void) {
    struct vinix_socket *s = vinix_socket_new(VINIX_NET_DGRAM, 0);
    assert(s);
    assert(vinix_socket_set_option(s, 1, 8, 2048) == 0);
    int value = 0;
    assert(vinix_socket_get_option(s, 1, 8, &value) == 0 && value == 4096);
    struct pbuf *a = pbuf_alloc(PBUF_RAW, 3000, PBUF_RAM);
    struct pbuf *b = pbuf_alloc(PBUF_RAW, 3000, PBUF_RAM);
    udp_received(s, s->udp, a, &physical_netif.ip_addr, 99);
    udp_received(s, s->udp, b, &physical_netif.ip_addr, 99);
    assert(s->rx_head && s->rx_head == s->rx_tail);
    uint8_t bytes[5000] = {0};
    assert(vinix_socket_recv(s, bytes, 5, NULL, NULL) == 5);
    assert(s->receive_queued == 0 && s->rx_head == NULL);
    /* Empty datagrams consume metadata budget too, rather than growing forever. */
    for (int i = 0; i < 10000; ++i) {
        struct pbuf *p = pbuf_alloc(PBUF_RAW, 0, PBUF_RAM);
        assert(p); udp_received(s, s->udp, p, &physical_netif.ip_addr, 99);
    }
    assert(s->receive_queued <= 4096);
    assert(vinix_socket_set_option(s, 1, 7, 2048) == 0);
    assert(vinix_socket_send(s, bytes, sizeof(bytes), PP_HTONL(0x0a000202), lwip_htons(99), 1) == -90);
    assert(vinix_socket_set_option(s, 1, 7, -1) == 22);
    assert(vinix_socket_set_option(s, 1, 10, 1) == 92);
    assert(vinix_socket_get_option(s, 6, 4, &value) == 92);
    vinix_socket_free(s);
}

static void test_tcp_send_budget_and_abort(void) {
    struct vinix_socket *s = vinix_socket_new(VINIX_NET_STREAM, 0);
    assert(s && vinix_socket_set_option(s, 1, 7, 2048) == 0);
    assert(vinix_socket_connect(s, PP_HTONL(0x0a000202), lwip_htons(7778)) == 115);
    answer_syn(s);
    uint8_t bytes[5000] = {0};
    fail_output = 1;
    assert(vinix_socket_send(s, bytes, sizeof(bytes), 0, 0, 0) == 4096);
    fail_output = 0;
    unsigned queued = 0;
    for (struct tcp_seg *p = s->tcp->unsent; p; p = p->next) queued += p->len;
    for (struct tcp_seg *p = s->tcp->unacked; p; p = p->next) queued += p->len;
    assert(queued == 4096 && vinix_socket_pending(s) == 4096);
    assert(!(vinix_socket_ready(s) & VINIX_NET_WRITABLE));
    assert(vinix_socket_send(s, bytes, 1, 0, 0, 0) == -11);
    /* ACK callback restores the exact budget used by send. */
    tcp_sent_data(s, s->tcp, 4096);
    assert(vinix_socket_pending(s) == 0 && (vinix_socket_ready(s) & VINIX_NET_WRITABLE));
    vinix_socket_abort_close(s); vinix_socket_free(s);
}

static void test_receive_shrink_and_recovery(void) {
    struct vinix_socket *s = vinix_socket_new(VINIX_NET_STREAM, 0);
    assert(s && vinix_socket_connect(s, PP_HTONL(0x0a000202), lwip_htons(7779)) == 115);
    answer_syn(s);
    struct pbuf *a = pbuf_alloc(PBUF_RAW, 10000, PBUF_RAM);
    struct pbuf *b = pbuf_alloc(PBUF_RAW, 3000, PBUF_RAM);
    assert(a && b && tcp_received(s, s->tcp, a, ERR_OK) == ERR_OK);
    assert(vinix_socket_set_option(s, 1, 8, 2048) == 0);
    /* A refused TCP pbuf stays owned by lwIP; its retry succeeds after growth. */
    assert(tcp_received(s, s->tcp, b, ERR_OK) == ERR_MEM);
    assert(vinix_socket_set_option(s, 1, 8, 16384) == 0);
    assert(tcp_received(s, s->tcp, b, ERR_OK) == ERR_OK);
    uint8_t bytes[10000];
    assert(vinix_socket_recv(s, bytes, sizeof(bytes), NULL, NULL) == 10000);
    assert(vinix_socket_recv(s, bytes, sizeof(bytes), NULL, NULL) == 3000);
    assert(s->receive_queued == 0);
    assert(vinix_socket_set_option(s, 1, 8, 2048) == 0);
    a = pbuf_alloc(PBUF_RAW, 10000, PBUF_RAM);
    assert(a && tcp_received(s, s->tcp, a, ERR_OK) == ERR_OK);
    assert(vinix_socket_recv(s, bytes, sizeof(bytes), NULL, NULL) == 10000);
    assert(s->receive_queued == 0);
    vinix_socket_abort_close(s); vinix_socket_free(s);
}

static void test_listener_keepalive_inheritance(void) {
    struct vinix_socket *listener = vinix_socket_new(VINIX_NET_STREAM, 0);
    assert(listener && vinix_socket_listen(listener, 8) == 0);
    assert(vinix_socket_set_option(listener, 1, 9, 1) == 0);
    assert(vinix_socket_set_option(listener, 6, 4, 17) == 0);
    assert(vinix_socket_set_option(listener, 6, 5, 3) == 0);
    assert(vinix_socket_set_option(listener, 6, 6, 4) == 0);
    struct tcp_pcb *pcb = tcp_new_ip_type(IPADDR_TYPE_V4);
    assert(pcb && accept_callback(listener, pcb, ERR_OK) == ERR_OK);
    struct vinix_socket *child = vinix_socket_accept(listener);
    assert(child && ip_get_option(child->tcp, SOF_KEEPALIVE));
    assert(child->tcp->keep_idle == 17000 && child->tcp->keep_intvl == 3000 && child->tcp->keep_cnt == 4);
    vinix_socket_free(child); vinix_socket_free(listener);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    uint8_t mac[6] = {0x52,0x54,0,0x12,0x34,0x56};
    vinix_net_init(); assert(vinix_net_attach(mac, DRIVER_VIRTIO) == 0);
    dhcp_stop(&physical_netif);
    ip4_addr_t local = { PP_HTONL(0x0a00020f) }, mask = { PP_HTONL(0xffffff00) }, gateway = { PP_HTONL(0x0a000202) };
    netif_set_addr(&physical_netif, &local, &mask, &gateway);
    physical_netif.output = wire_output;
    test_keepalive_wire(); test_receive_and_send_limits(); test_tcp_send_budget_and_abort(); test_receive_shrink_and_recovery(); test_listener_keepalive_inheritance();
    puts("NETWORK OPTIONS HOST: PASS");
    return 0;
}
