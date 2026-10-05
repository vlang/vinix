/* Use the existing raw-lwIP wire fixture; no transport or close API is mocked. */
#define main network_options_main
#include "../network-options/test.c"
#undef main
#include <lwip/stats.h>

static struct vinix_socket *connected_socket(void) {
    struct vinix_socket *socket = vinix_socket_new(VINIX_NET_STREAM, 0);
    assert(socket && vinix_socket_connect(socket, PP_HTONL(0x0a000202),
                                          lwip_htons(7780)) == 115);
    answer_syn(socket);
    return socket;
}

static struct pbuf *control_packet(struct tcp_pcb *pcb, int fin, int ack_fin,
                                   const void *data, unsigned int length) {
    uint8_t bytes[10040] = {0};
    assert(length <= sizeof bytes - 40);
    bytes[0] = 0x45; be16(bytes + 2, 40 + length); bytes[8] = 64; bytes[9] = 6;
    memcpy(bytes + 12, &ip_2_ip4(&pcb->remote_ip)->addr, 4);
    memcpy(bytes + 16, &ip_2_ip4(&pcb->local_ip)->addr, 4);
    be16(bytes + 20, pcb->remote_port); be16(bytes + 22, pcb->local_port);
    be32(bytes + 24, pcb->rcv_nxt);
    be32(bytes + 28, pcb->snd_nxt - !ack_fin);
    bytes[32] = 0x50; bytes[33] = fin ? 0x11 : 0x10; be16(bytes + 34, 32768);
    if (length) memcpy(bytes + 40, data, length);
    uint32_t pseudo = 6 + 20 + length;
    for (int i = 12; i < 20; i += 2) pseudo += ((unsigned)bytes[i] << 8) | bytes[i + 1];
    be16(bytes + 36, checksum(bytes + 20, 20 + length, pseudo));
    be16(bytes + 10, checksum(bytes, 20, 0));
    struct pbuf *p = pbuf_alloc(PBUF_RAW, 40 + length, PBUF_POOL);
    assert(p && pbuf_take(p, bytes, 40 + length) == ERR_OK);
    return p;
}

static void incoming_control(struct tcp_pcb *pcb, int fin, int ack_fin) {
    struct pbuf *p = control_packet(pcb, fin, ack_fin, NULL, 0);
    assert(ip4_input(p, &physical_netif) == ERR_OK);
}

static void expire_timewait(void) {
    for (unsigned int tick = 0; tick < 250; ++tick) tcp_slowtmr();
    assert(tcp_tw_pcbs == NULL);
}

static void check_endpoints(struct vinix_socket *socket,
                            const struct vinix_net_endpoint *local,
                            const struct vinix_net_endpoint *remote) {
    struct vinix_net_endpoint actual;
    assert(vinix_socket_name_endpoint(socket, &actual, 0) == 0);
    assert(memcmp(&actual, local, sizeof actual) == 0);
    assert(vinix_socket_name_endpoint(socket, &actual, 1) == 0);
    assert(memcmp(&actual, remote, sizeof actual) == 0);
}

static void test_shutdown_pool_ownership(void) {
    struct vinix_socket *a = vinix_socket_new(VINIX_NET_STREAM, 0);
    assert(a && vinix_socket_shutdown(a, 2) == 0);
    assert(a->tcp == NULL);
    vinix_socket_free(a);

    /* A double free above lets a later allocation zero this real TIME-WAIT
     * record, reproducing tcp_input's state invariant failure in Dota startup.
     */
    struct vinix_socket *b = connected_socket();
    struct tcp_pcb *pcb = b->tcp;
    assert(vinix_socket_shutdown(b, 2) == 0 && b->tcp == NULL);
    incoming_control(pcb, 1, 1);
    assert(tcp_tw_pcbs == pcb && pcb->state == TIME_WAIT);
    struct vinix_socket *c = vinix_socket_new(VINIX_NET_STREAM, 0);
    assert(c && c->tcp != pcb && pcb->state == TIME_WAIT);
    vinix_socket_free(c);
    vinix_socket_free(b);
    expire_timewait();
}

static void test_shutdown_order(int first) {
    struct vinix_socket *socket = connected_socket();
    struct tcp_pcb *pcb = socket->tcp;
    struct vinix_net_endpoint local, remote;
    assert(vinix_socket_name_endpoint(socket, &local, 0) == 0);
    assert(vinix_socket_name_endpoint(socket, &remote, 1) == 0);
    assert(vinix_socket_shutdown(socket, first) == 0 && socket->tcp == pcb);
    assert(vinix_socket_shutdown(socket, !first) == 0 && socket->tcp == NULL);
    assert(pcb->callback_arg == NULL && pcb->recv == NULL &&
           pcb->sent == NULL && pcb->errf == NULL);
    check_endpoints(socket, &local, &remote);
    assert(vinix_socket_shutdown(socket, 2) == 0);
    char byte;
    assert(vinix_socket_recv(socket, &byte, 1, NULL, NULL) == 0);
    assert(vinix_socket_send(socket, &byte, 1, 0, 0, 0) == -32);
    vinix_socket_free(socket);
    incoming_control(pcb, 1, 1);
    expire_timewait();
}

static void test_write_shutdown_eof(int ack_fin) {
    struct vinix_socket *socket = connected_socket();
    struct tcp_pcb *pcb = socket->tcp;
    struct vinix_net_endpoint local, remote;
    assert(vinix_socket_name_endpoint(socket, &local, 0) == 0);
    assert(vinix_socket_name_endpoint(socket, &remote, 1) == 0);
    incoming_data(socket, pcb->rcv_nxt, "abcdefghij");
    assert(vinix_socket_shutdown(socket, 1) == 0 && socket->tcp == pcb);
    incoming_control(pcb, 1, ack_fin);
    assert(socket->peer_closed && socket->tcp == NULL);
    assert(pcb->state == (ack_fin ? TIME_WAIT : CLOSING));
    if (!ack_fin) incoming_control(pcb, 0, 1);
    assert(pcb->state == TIME_WAIT);
    expire_timewait();
    /* The descriptor remains usable after lwIP frees its former PCB. */
    struct vinix_socket *replacement = vinix_socket_new(VINIX_NET_STREAM, 0);
    assert(replacement);
    char bytes[10];
    assert(vinix_socket_recv(socket, bytes, sizeof bytes, NULL, NULL) == 10);
    assert(memcmp(bytes, "abcdefghij", sizeof bytes) == 0);
    assert(vinix_socket_recv(socket, bytes, sizeof bytes, NULL, NULL) == 0);
    check_endpoints(socket, &local, &remote);
    assert(vinix_socket_shutdown(socket, 0) == 0);
    vinix_socket_free(socket);
    assert(replacement->tcp->state == CLOSED);
    vinix_socket_free(replacement);
}

static void test_deferred_fin(void) {
    struct vinix_socket *socket = connected_socket();
    struct tcp_pcb *pcb = socket->tcp;
    void *segments[MEMP_NUM_TCP_SEG];
    unsigned int count = 0;
    while (count < MEMP_NUM_TCP_SEG &&
           (segments[count] = memp_malloc(MEMP_TCP_SEG)) != NULL) ++count;
    assert(count > 0);
    assert(vinix_socket_shutdown(socket, 2) == 0 && socket->tcp == NULL);
    assert(pcb->flags & TF_CLOSEPEND);
    assert(pcb->callback_arg == NULL && pcb->errf == NULL);
    vinix_socket_free(socket);
    for (unsigned int index = 0; index < count; ++index)
        memp_free(MEMP_TCP_SEG, segments[index]);
    tcp_fasttmr();
    assert(pcb->state == FIN_WAIT_1 && !(pcb->flags & TF_CLOSEPEND));
    incoming_control(pcb, 1, 1);
    expire_timewait();
}

static void test_final_data_budget(int ack_fin) {
    struct vinix_socket *socket = connected_socket();
    struct tcp_pcb *pcb = socket->tcp;
    char earlier[5000];
    memset(earlier, 'a', sizeof earlier);
    struct pbuf *p = control_packet(pcb, 0, 1, earlier, sizeof earlier);
    assert(ip4_input(p, &physical_netif) == ERR_OK);
    assert(vinix_socket_set_option(socket, 1, 8, 2048) == 0);
    assert(socket->receive_queued > socket->receive_limit);
    assert(vinix_socket_shutdown(socket, 1) == 0);
    p = control_packet(pcb, 1, ack_fin, "finalbytes", 10);
    assert(ip4_input(p, &physical_netif) == ERR_OK);
    assert(socket->tcp == NULL && socket->peer_closed && !socket->error);
    assert(pcb->refused_data == NULL);
    if (!ack_fin) incoming_control(pcb, 0, 1);
    expire_timewait();
    char bytes[5000];
    assert(vinix_socket_recv(socket, bytes, sizeof bytes, NULL, NULL) == sizeof bytes);
    assert(memcmp(bytes, earlier, sizeof bytes) == 0);
    assert(vinix_socket_recv(socket, bytes, sizeof bytes, NULL, NULL) == 10);
    assert(memcmp(bytes, "finalbytes", 10) == 0);
    assert(vinix_socket_recv(socket, bytes, sizeof bytes, NULL, NULL) == 0);
    vinix_socket_free(socket);
}

static unsigned int available_pool_packets(void) {
    struct pbuf *packets[PBUF_POOL_SIZE];
    unsigned int count = 0;
    while (count < PBUF_POOL_SIZE &&
           (packets[count] = pbuf_alloc(PBUF_RAW, 1, PBUF_POOL)) != NULL) ++count;
    for (unsigned int index = 0; index < count; ++index) pbuf_free(packets[index]);
    return count;
}

static void test_final_data_metadata_failure(void) {
    unsigned int available = available_pool_packets();
    mem_size_t used = lwip_stats.mem.used;
    struct vinix_socket *socket = connected_socket();
    struct tcp_pcb *pcb = socket->tcp;
    incoming_data(socket, pcb->rcv_nxt, "abcdefghij");
    assert(vinix_socket_shutdown(socket, 1) == 0);
    /* Leave the local FIN unacknowledged: acknowledging it would free its
     * heap pbuf before receive delivery, leaving enough room for metadata.
     */
    struct pbuf *p = control_packet(pcb, 1, 0, "finalbytes", 10);
    /* Exhaust the actual heap used for queue metadata, while the already
     * prepared final packet and TCP PCB live in separate lwIP pools.
     */
    static void *blocks[MEM_SIZE / sizeof(struct packet) + 1];
    unsigned int count = 0;
    while (count < sizeof blocks / sizeof blocks[0] &&
           (blocks[count] = mem_malloc(sizeof(struct packet))) != NULL) ++count;
    assert(count > 0);
    assert(ip4_input(p, &physical_netif) == ERR_OK);
    assert(socket->tcp == NULL && socket->peer_closed && socket->error == 12);
    assert(tcp_tw_pcbs == NULL);
    for (unsigned int index = 0; index < count; ++index) mem_free(blocks[index]);
    char bytes[10];
    assert(vinix_socket_recv(socket, bytes, sizeof bytes, NULL, NULL) == sizeof bytes);
    assert(memcmp(bytes, "abcdefghij", sizeof bytes) == 0);
    assert(vinix_socket_recv(socket, bytes, sizeof bytes, NULL, NULL) == -12);
    vinix_socket_free(socket);
    assert(available_pool_packets() == available);
    assert(lwip_stats.mem.used == used);
}

static void test_write_shutdown_after_peer_eof(void) {
    struct vinix_socket *socket = connected_socket();
    struct tcp_pcb *pcb = socket->tcp;
    struct vinix_net_endpoint local, remote;
    assert(vinix_socket_name_endpoint(socket, &local, 0) == 0);
    assert(vinix_socket_name_endpoint(socket, &remote, 1) == 0);
    struct pbuf *p = control_packet(pcb, 1, 1, "finalbytes", 10);
    assert(ip4_input(p, &physical_netif) == ERR_OK);
    assert(socket->peer_closed && socket->tcp == pcb && pcb->state == CLOSE_WAIT);
    assert(vinix_socket_shutdown(socket, 1) == 0 && socket->tcp == NULL);
    assert(pcb->state == LAST_ACK);
    incoming_control(pcb, 0, 1);
    struct vinix_socket *replacement = vinix_socket_new(VINIX_NET_STREAM, 0);
    assert(replacement);
    char bytes[10];
    assert(vinix_socket_recv(socket, bytes, sizeof bytes, NULL, NULL) == sizeof bytes);
    assert(memcmp(bytes, "finalbytes", sizeof bytes) == 0);
    assert(vinix_socket_recv(socket, bytes, sizeof bytes, NULL, NULL) == 0);
    check_endpoints(socket, &local, &remote);
    vinix_socket_free(socket);
    assert(replacement->tcp->state == CLOSED);
    vinix_socket_free(replacement);
}

static void test_listener_error_ownership(void) {
    struct vinix_socket *socket = vinix_socket_new(VINIX_NET_STREAM, 0);
    assert(socket && vinix_socket_listen(socket, 8) == 0);
    struct tcp_pcb *pcb = socket->tcp;
    assert(vinix_socket_shutdown(socket, 2) == 107 && socket->tcp == pcb);
    assert(pcb->callback_arg == socket);
    assert(((struct tcp_pcb_listen *)pcb)->accept == accept_callback);
    vinix_socket_free(socket);
}

static void test_ipv6_endpoint_cache(void) {
    struct vinix_socket *socket = vinix_socket_new_family(VINIX_NET_STREAM, 0, 10);
    assert(socket);
    ip6_addr_t local, remote;
    IP6_ADDR(&local, PP_HTONL(0xfe800000), 0, 0, PP_HTONL(1));
    IP6_ADDR(&remote, PP_HTONL(0xfe800000), 0, 0, PP_HTONL(2));
    /* Native zones include the merged stack's explicit loopback interface;
     * the physical interface still reports Linux ifindex 2 publicly. */
    ip6_addr_set_zone(&local, netif_get_index(&physical_netif));
    ip6_addr_set_zone(&remote, netif_get_index(&physical_netif));
    ip_addr_copy_from_ip6(socket->tcp->local_ip, local);
    ip_addr_copy_from_ip6(socket->tcp->remote_ip, remote);
    socket->tcp->local_port = 8888; socket->tcp->remote_port = 9999;
    socket->connected = 1;
    struct vinix_net_endpoint before_local, before_remote;
    assert(vinix_socket_name_endpoint(socket, &before_local, 0) == 0);
    assert(vinix_socket_name_endpoint(socket, &before_remote, 1) == 0);
    assert(before_local.scope == 2 && before_remote.scope == 2);
    assert(vinix_socket_shutdown(socket, 2) == 0 && socket->tcp == NULL);
    check_endpoints(socket, &before_local, &before_remote);
    vinix_socket_free(socket);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    uint8_t mac[6] = {0x52,0x54,0,0x12,0x34,0x56};
    vinix_net_init(); assert(vinix_net_attach(mac, DRIVER_VIRTIO) == 0);
    dhcp_stop(&physical_netif);
    ip4_addr_t local = { PP_HTONL(0x0a00020f) }, mask = { PP_HTONL(0xffffff00) }, gateway = { PP_HTONL(0x0a000202) };
    netif_set_addr(&physical_netif, &local, &mask, &gateway);
    physical_netif.output = wire_output;
    test_shutdown_pool_ownership();
    test_shutdown_order(0); test_shutdown_order(1);
    test_write_shutdown_eof(1); test_write_shutdown_eof(0);
    test_final_data_budget(1); test_final_data_budget(0);
    test_final_data_metadata_failure();
    test_write_shutdown_after_peer_eof();
    test_deferred_fin(); test_listener_error_ownership(); test_ipv6_endpoint_cache();
    puts("NETWORK TCP LIFETIME: PASS");
    return 0;
}
