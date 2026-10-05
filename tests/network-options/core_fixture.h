/* SPDX-License-Identifier: GPL-2.0-or-later
 * Independent original C layouts and borrowed views of the production V core.
 * No adapter algorithms are reproduced here. */
#ifndef VINIX_NET_CORE_FIXTURE_H
#define VINIX_NET_CORE_FIXTURE_H
#include "../../kernel/c/vinix_net.h"
#include "../../kernel/c/net_random.h"

#include <lwip/dhcp.h>
#include <lwip/dns.h>
#include <lwip/etharp.h>
#include <lwip/ethip6.h>
#include <lwip/igmp.h>
#include <lwip/mld6.h>
#include <lwip/ip6_zone.h>
#include <lwip/nd6.h>
#include <lwip/inet_chksum.h>
#include <lwip/init.h>
#include <lwip/ip.h>
#include <lwip/ethip6.h>
#include <lwip/ip6_addr.h>
#include <lwip/ip6_zone.h>
#include <lwip/mem.h>
#include <lwip/netif.h>
#include <lwip/pbuf.h>
#include <lwip/priv/tcp_priv.h>
#include <lwip/prot/ip4.h>
#include <lwip/tcp.h>
#include <lwip/timeouts.h>
#include <lwip/udp.h>
#include <netif/ethernet.h>

#include <stdio.h>
#include <string.h>

enum { DRIVER_NONE, DRIVER_VIRTIO, DRIVER_APPLE_WIFI, DRIVER_E1000 };
struct packet {
    struct packet *next;
    struct pbuf *p;
    uint16_t offset;
    ip_addr_t address;
    uint16_t port;
    uint32_t charge;
};

struct membership {
    ip_addr_t group;
    uint64_t epoch;
    uint8_t ifindex;
    uint8_t used;
};

#define SOCKET_MEMBERSHIPS 16

struct vinix_socket {
    int family;
    int v6only;
    int bound;
    int hops4, hops6;
    int multicast_hops4, multicast_hops6;
    int multicast_loop4, multicast_loop6;
    uint32_t multicast_if4, multicast_if6, multicast_addr4;
    struct membership memberships[SOCKET_MEMBERSHIPS];
    int type;
    int protocol;
    int error;
    int listening;
    int connecting;
    int connected;
    int peer_closed;
    int read_shutdown;
    int write_shutdown;
    int reuseaddr;
    int broadcast;
    int keepalive;
    /* TCP_NODELAY on a listening socket, for the connections it accepts. */
    int nodelay;
    uint32_t keep_idle, keep_interval, keep_count;
    uint32_t send_limit, receive_limit, send_queued, receive_queued;
    int abort_on_close;
    struct tcp_pcb *tcp;
    struct udp_pcb *udp;
    /* tcp_err releases the PCB before user space can query this socket. */
    ip_addr_t last_local_address;
    uint16_t last_local_port;
    ip_addr_t last_remote_address;
    uint16_t last_remote_port;
    struct packet *rx_head;
    struct packet *rx_tail;
    struct vinix_socket *accept_head;
    struct vinix_socket *accept_tail;
    struct vinix_socket *accept_next;
};


err_t vinix_net_core_tcp_received(void *, struct tcp_pcb *, struct pbuf *, err_t);
err_t vinix_net_core_tcp_sent_data(void *, struct tcp_pcb *, uint16_t);
err_t vinix_net_core_accept_callback(void *, struct tcp_pcb *, err_t);
#define tcp_received(...) vinix_net_core_tcp_received(__VA_ARGS__)
#define tcp_sent_data(...) vinix_net_core_tcp_sent_data(__VA_ARGS__)
typedef err_t (*fixture_accept_fn)(void *, struct tcp_pcb *, err_t);
fixture_accept_fn vinix_net_core_accept_fn(void);
#define accept_callback (*vinix_net_core_accept_fn())
int vinix_net_core_endpoint_ip(struct vinix_socket *, const struct vinix_net_endpoint *, ip_addr_t *);
void *vinix_net_core_mac(void);
#define endpoint_ip(...) vinix_net_core_endpoint_ip(__VA_ARGS__)
#define active_mac ((uint8_t *)vinix_net_core_mac())
void *vinix_net_core_physical(void);
uint64_t vinix_net_core_epoch(void);
void vinix_net_core_udp_received(void *, struct udp_pcb *, struct pbuf *, ip_addr_t *, uint16_t);
struct netif *vinix_net_core_interface_index(uint32_t);
#define physical_netif (*(struct netif *)vinix_net_core_physical())
#define link_epoch (vinix_net_core_epoch())
#define udp_received(...) vinix_net_core_udp_received(__VA_ARGS__)
#define interface_index(...) vinix_net_core_interface_index(__VA_ARGS__)
#endif
