// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

#include "vinix_net.h"
#include "net_random.h"

#include <lwip/dhcp.h>
#include <lwip/dns.h>
#include <lwip/etharp.h>
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

/* Drivers are deliberately below the IP stack.  Their transmit functions are
 * weak so that the stack links whichever of them an architecture leaves out:
 * VirtIO-MMIO and Apple Wi-Fi exist only on arm64, the e1000 driver on both. */
extern int vinix_virtio_net_send(const void *, uint64_t) __attribute__((weak));
extern int vinix_apple_wifi_send(const void *, uint64_t) __attribute__((weak));
extern int vinix_e1000_send(const void *, uint64_t) __attribute__((weak));

enum {
    DRIVER_NONE = 0,
    DRIVER_VIRTIO = 1,
    DRIVER_APPLE_WIFI = 2,
    DRIVER_E1000 = 3,
};

typedef int (*driver_send_fn)(const void *, uint64_t);

/* The transmit function of a driver, or NULL if it is not in this kernel. */
static driver_send_fn driver_send(int driver) {
    switch (driver) {
        case DRIVER_VIRTIO:     return vinix_virtio_net_send;
        case DRIVER_APPLE_WIFI: return vinix_apple_wifi_send;
        case DRIVER_E1000:      return vinix_e1000_send;
        default:                return NULL;
    }
}

struct packet {
    struct packet *next;
    struct pbuf *p;
    uint16_t offset;
    ip_addr_t address;
    uint16_t port;
    uint32_t charge;
};

struct vinix_socket {
    int family;
    int v6only;
    int bound;
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

static struct netif physical_netif;
static int stack_initialised;
static int link_attached;
static int active_driver;
static uint8_t active_mac[6];
static uint32_t clock_ms;
static uint32_t clock_anchor_ms;
static int clock_anchored;
/* The ID the fragments after the first of a datagram go out with. */
static uint16_t fragment_id;

static int linux_error(err_t error) {
    switch (error) {
        case ERR_OK:         return 0;
        case ERR_MEM:        return 12;  /* ENOMEM */
        case ERR_BUF:        return 105; /* ENOBUFS */
        case ERR_TIMEOUT:    return 110; /* ETIMEDOUT */
        case ERR_RTE:        return 101; /* ENETUNREACH */
        case ERR_INPROGRESS: return 115; /* EINPROGRESS */
        case ERR_VAL:        return 22;  /* EINVAL */
        case ERR_WOULDBLOCK: return 11;  /* EAGAIN */
        case ERR_USE:        return 98;  /* EADDRINUSE */
        case ERR_ALREADY:    return 114; /* EALREADY */
        case ERR_ISCONN:     return 106; /* EISCONN */
        case ERR_CONN:       return 107; /* ENOTCONN */
        case ERR_IF:         return 5;   /* EIO */
        case ERR_ABRT:       return 103; /* ECONNABORTED */
        case ERR_RST:        return 104; /* ECONNRESET */
        case ERR_CLSD:       return 107; /* ENOTCONN */
        case ERR_ARG:        return 22;  /* EINVAL */
        default:             return 5;
    }
}

#ifdef __AARCH64__
void aarch64__uart__putc(uint8_t);

static void assert_serial(const char *text) {
    while (*text) {
        aarch64__uart__putc((uint8_t)*text++);
    }
}
#endif

// A failed assertion stops this CPU for good, so say which one it was where it
// can be read: ordinary printf is compiled out of PROD kernels, and the stack
// was all that was left to find it by.
void vinix_lwip_assert(const char *message, const char *file, int line) {
    printf_panic("lwip: assertion '%s' at %s:%d\n", message, file, line);
#ifdef __AARCH64__
    char number[12];
    int at = sizeof number - 1;
    number[at] = 0;
    do {
        number[--at] = (char)('0' + line % 10);
        line /= 10;
    } while (line > 0 && at > 0);
    assert_serial("lwip: assertion '");
    assert_serial(message);
    assert_serial("' at ");
    assert_serial(file);
    assert_serial(":");
    assert_serial(&number[at]);
    assert_serial("\n");
#endif
    for (;;) { }
}

uint32_t sys_now(void) {
    return clock_ms;
}

uint32_t vinix_htonl(uint32_t value) {
    return lwip_htonl(value);
}

uint16_t vinix_htons(uint16_t value) {
    return lwip_htons(value);
}

static void free_packet(struct packet *packet) {
    if (packet->p) {
        pbuf_free(packet->p);
    }
    mem_free(packet);
}

static void free_packets(struct vinix_socket *socket) {
    while (socket->rx_head) {
        struct packet *packet = socket->rx_head;
        socket->rx_head = packet->next;
        free_packet(packet);
    }
    socket->rx_tail = NULL;
    socket->receive_queued = 0;
}

static int queue_packet(struct vinix_socket *socket, struct pbuf *p,
                        const ip_addr_t *address, uint16_t port, int terminal) {
    struct packet *packet;
    uint32_t charge = p->tot_len + sizeof(*packet) + 64;
    if ((charge > socket->receive_limit ||
         socket->receive_queued > socket->receive_limit - charge) &&
        !(socket->type == VINIX_NET_STREAM &&
          (socket->receive_queued == 0 || terminal))) {
        return 0;
    }
    /* TCP may coalesce an entire advertised window into one pbuf chain.
     * Permit that one chain in an empty queue even after SO_RCVBUF shrinks;
     * rejecting it forever would deadlock the stream. Further chains still
     * apply backpressure. Also keep the final TCP chain: a PCB already in
     * CLOSING or TIME-WAIT will not retry refused data before its timer frees
     * it. That chain is still bounded by the advertised receive window.
     * UDP drops datagrams that exceed its budget. */
    packet = (struct packet *)mem_malloc(sizeof(*packet));
    if (!packet) {
        return 0;
    }
    memset(packet, 0, sizeof(*packet));
    packet->p = p;
    if (address) ip_addr_copy(packet->address, *address);
    packet->port = port;
    packet->charge = charge;
    if (socket->rx_tail) {
        socket->rx_tail->next = packet;
    } else {
        socket->rx_head = packet;
    }
    socket->rx_tail = packet;
    socket->receive_queued += charge;
    return 1;
}

/* lwIP owns a successfully closed PCB, including one still on TIME-WAIT.
 * Keep only endpoint values after that transfer: its timers may free the PCB
 * without an error callback. The caller holds the kernel's network lock.
 */
static void detach_tcp(struct vinix_socket *socket, struct tcp_pcb *pcb) {
    ip_addr_copy(socket->last_local_address, pcb->local_ip);
    socket->last_local_port = lwip_htons(pcb->local_port);
    ip_addr_copy(socket->last_remote_address, pcb->remote_ip);
    socket->last_remote_port = lwip_htons(pcb->remote_port);
    tcp_arg(pcb, NULL);
    tcp_recv(pcb, NULL);
    tcp_sent(pcb, NULL);
    tcp_err(pcb, NULL);
    socket->tcp = NULL;
    socket->connecting = 0;
}

static err_t tcp_received(void *argument, struct tcp_pcb *pcb,
                          struct pbuf *p, err_t error) {
    struct vinix_socket *socket = (struct vinix_socket *)argument;
    (void)pcb;
    if (!socket) {
        if (p) {
            pbuf_free(p);
        }
        return ERR_OK;
    }
    if (error != ERR_OK) {
        socket->error = linux_error(error);
    }
    if (!p) {
        socket->peer_closed = 1;
        if (pcb->state == TIME_WAIT || pcb->state == CLOSING) {
            detach_tcp(socket, pcb);
        }
        return ERR_OK;
    }
    if (socket->read_shutdown) {
        tcp_recved(pcb, p->tot_len);
        pbuf_free(p);
        return ERR_OK;
    }
    int terminal = pcb->state == TIME_WAIT || pcb->state == CLOSING;
    if (!queue_packet(socket, p, &pcb->remote_ip, pcb->remote_port, terminal)) {
        if (terminal) {
            /* No metadata memory remains for the final payload. Report the
             * failure instead of retaining a PCB that will expire silently.
             * This callback owns p only when accepting it or returning ABRT;
             * tcp_input will not free it again after ERR_ABRT.
             */
            detach_tcp(socket, pcb);
            socket->connected = 0;
            socket->peer_closed = 1;
            socket->error = 12; /* ENOMEM */
            pbuf_free(p);
            tcp_abort(pcb);
            return ERR_ABRT;
        }
        /* Keeping lwIP's ownership by refusing the packet applies TCP
         * backpressure instead of silently losing stream bytes. */
        return ERR_MEM;
    }
    return ERR_OK;
}

static err_t tcp_sent_data(void *argument, struct tcp_pcb *pcb, uint16_t length) {
    struct vinix_socket *socket = (struct vinix_socket *)argument;
    (void)pcb;
    if (socket) {
        socket->send_queued = length >= socket->send_queued ?
            0 : socket->send_queued - length;
    }
    return ERR_OK;
}

static err_t tcp_connected(void *argument, struct tcp_pcb *pcb, err_t error) {
    struct vinix_socket *socket = (struct vinix_socket *)argument;
    (void)pcb;
    if (!socket) {
        return ERR_OK;
    }
    socket->connecting = 0;
    if (error == ERR_OK) {
        socket->connected = 1;
    } else {
        socket->error = linux_error(error);
    }
    return ERR_OK;
}

static void tcp_failed(void *argument, err_t error) {
    struct vinix_socket *socket = (struct vinix_socket *)argument;
    if (!socket) {
        return;
    }
    socket->tcp = NULL;
    socket->connecting = 0;
    socket->connected = 0;
    socket->peer_closed = 1;
    socket->error = linux_error(error);
}

static void install_tcp_callbacks(struct vinix_socket *socket) {
    tcp_arg(socket->tcp, socket);
    tcp_recv(socket->tcp, tcp_received);
    tcp_sent(socket->tcp, tcp_sent_data);
    tcp_err(socket->tcp, tcp_failed);
}

static err_t accept_callback(void *argument, struct tcp_pcb *pcb, err_t error) {
    struct vinix_socket *listener = (struct vinix_socket *)argument;
    struct vinix_socket *child;
    if (!listener || error != ERR_OK) {
        if (pcb) {
            tcp_abort(pcb);
        }
        return ERR_ABRT;
    }
    child = (struct vinix_socket *)mem_calloc(1, sizeof(*child));
    if (!child) {
        tcp_abort(pcb);
        return ERR_ABRT;
    }
    child->family = listener->family;
    child->v6only = listener->v6only;
    child->bound = 1;
    child->type = VINIX_NET_STREAM;
    child->protocol = 6;
    child->connected = 1;
    child->tcp = pcb;
    child->reuseaddr = ip_get_option(pcb, SOF_REUSEADDR) != 0;
    child->keepalive = listener->keepalive;
    if (child->keepalive) ip_set_option(pcb, SOF_KEEPALIVE);
    else ip_reset_option(pcb, SOF_KEEPALIVE);
    child->keep_idle = listener->keep_idle;
    child->keep_interval = listener->keep_interval;
    child->keep_count = listener->keep_count;
    pcb->keep_idle = child->keep_idle;
    pcb->keep_intvl = child->keep_interval;
    pcb->keep_cnt = child->keep_count;
    child->send_limit = listener->send_limit;
    child->receive_limit = listener->receive_limit;
    child->abort_on_close = listener->abort_on_close;
    /* A connection takes TCP_NODELAY from the socket it was accepted on. */
    if (listener->nodelay) {
        tcp_nagle_disable(pcb);
    }
    install_tcp_callbacks(child);

    if (listener->accept_tail) {
        listener->accept_tail->accept_next = child;
    } else {
        listener->accept_head = child;
    }
    listener->accept_tail = child;
    return ERR_OK;
}

static void udp_received(void *argument, struct udp_pcb *pcb, struct pbuf *p,
                         const ip_addr_t *address, uint16_t port) {
    struct vinix_socket *socket = (struct vinix_socket *)argument;
    (void)pcb;
    if (!socket || socket->read_shutdown ||
        !queue_packet(socket, p, address, port, 0)) {
        pbuf_free(p);
    }
}

void vinix_net_init(void) {
    if (stack_initialised) {
        return;
    }
    lwip_init();
    stack_initialised = 1;
    printf("net: lwIP 2.2.1, IPv4/IPv6 TCP/UDP loopback ready\n");
}

static int driver_output(const void *frame, size_t length) {
    driver_send_fn send = driver_send(active_driver);
    return send ? send(frame, (uint64_t)length) : -1;
}

static err_t link_output(struct netif *netif, struct pbuf *p) {
    uint8_t frame[1522];
    uint16_t copied;
    (void)netif;
    if (p->tot_len > sizeof(frame)) {
        return ERR_BUF;
    }
    copied = pbuf_copy_partial(p, frame, p->tot_len, 0);
    if (copied != p->tot_len || driver_output(frame, copied) < 0) {
        return ERR_IF;
    }
    return ERR_OK;
}

/* Every datagram leaves the machine with an ID from ip_randomid() in place of
 * lwIP's, which counts up by one: anyone who saw two of them knew how much the
 * machine had sent in between. The fragments of a datagram share its ID, and
 * ip4_frag() sends them in order, one after another, the first at offset 0. */
static err_t output_ipv4(struct netif *netif, struct pbuf *p, const ip4_addr_t *destination) {
    struct ip_hdr *header = (struct ip_hdr *)p->payload;
    uint16_t header_length;
    if (p->len >= IP_HLEN && IPH_V(header) == 4) {
        header_length = IPH_HL_BYTES(header);
        if (header_length >= IP_HLEN && p->len >= header_length) {
            if ((lwip_ntohs(IPH_OFFSET(header)) & IP_OFFMASK) == 0) {
                fragment_id = vinix_ip_randomid();
            }
            IPH_ID_SET(header, fragment_id);
            IPH_CHKSUM_SET(header, 0);
            IPH_CHKSUM_SET(header, inet_chksum(header, header_length));
        }
    }
    return etharp_output(netif, p, destination);
}

static err_t physical_init(struct netif *netif) {
    netif->name[0] = 'e';
    netif->name[1] = 'n';
    netif->hwaddr_len = 6;
    memcpy(netif->hwaddr, active_mac, 6);
    netif->mtu = 1500;
    netif->flags = NETIF_FLAG_BROADCAST | NETIF_FLAG_ETHARP | NETIF_FLAG_ETHERNET;
    netif->output = output_ipv4;
    netif->output_ip6 = ethip6_output;
    netif->flags |= NETIF_FLAG_MLD6;
    netif->linkoutput = link_output;
    return ERR_OK;
}

int vinix_net_attach(const uint8_t mac[6], int driver) {
    ip4_addr_t zero;
    if (!stack_initialised) {
        vinix_net_init();
    }
    if (!driver_send(driver)) {
        return -22;
    }
    if (link_attached) {
        vinix_net_detach();
    }
    active_driver = driver;
    memcpy(active_mac, mac, 6);
    ip4_addr_set_zero(&zero);
    memset(&physical_netif, 0, sizeof(physical_netif));
    if (!netif_add(&physical_netif, &zero, &zero, &zero, NULL,
                   physical_init, netif_input)) {
        active_driver = DRIVER_NONE;
        return -12;
    }
    netif_create_ip6_linklocal_address(&physical_netif, 1);
    netif_set_default(&physical_netif);
    netif_set_link_up(&physical_netif);
    netif_set_up(&physical_netif);
    link_attached = 1;
    if (dhcp_start(&physical_netif) != ERR_OK) {
        vinix_net_detach();
        return -12;
    }
    printf("net: attached %c%c%u, DHCP started\n", physical_netif.name[0],
           physical_netif.name[1], physical_netif.num);
    return 0;
}

void vinix_net_detach(void) {
    if (!link_attached) {
        return;
    }
    dhcp_release_and_stop(&physical_netif);
    netif_set_down(&physical_netif);
    netif_set_link_down(&physical_netif);
    netif_remove(&physical_netif);
    link_attached = 0;
    active_driver = DRIVER_NONE;
}

int vinix_net_input(const void *frame, size_t length) {
    struct pbuf *p;
    err_t error;
    if (!link_attached || !frame || length < 14 || length > 65535) {
        return -22;
    }
    p = pbuf_alloc(PBUF_RAW, (uint16_t)length, PBUF_POOL);
    if (!p) {
        return -12;
    }
    if (pbuf_take(p, frame, (uint16_t)length) != ERR_OK) {
        pbuf_free(p);
        return -12;
    }
    error = physical_netif.input(p, &physical_netif);
    if (error != ERR_OK) {
        pbuf_free(p);
        return -linux_error(error);
    }
    return 0;
}

void vinix_net_poll(uint32_t now_ms) {
    if (!stack_initialised) {
        return;
    }
    /* lwIP wants milliseconds that start near zero and only go up. Vinix's
     * monotonic clock is seeded from the platform's idea of elapsed time and is
     * already a few weeks along at boot, so feeding it in raw put every timer
     * lwip_init() had scheduled -- at a sys_now() of 0 -- more than 2^31 ms in
     * the past, which its wraparound-safe comparison reads as far in the
     * future. No cyclic timer ever fired: DHCP sent its DISCOVER and REQUEST
     * from the receive path, then sat in CHECKING for ever because the address
     * conflict check is timer-driven, and the machine never got a lease.
     *
     * Anchor the clock at the first sample instead. */
    if (!clock_anchored) {
        clock_anchor_ms = now_ms;
        clock_anchored = 1;
    }
    clock_ms = now_ms - clock_anchor_ms;
    sys_check_timeouts();
    netif_poll_all();
}

int vinix_net_config(uint32_t *address, uint32_t *netmask, uint32_t *gateway,
                     uint32_t dns[3]) {
    unsigned int index;
    if (!link_attached || !dhcp_supplied_address(&physical_netif)) {
        return 0;
    }
    if (address) {
        *address = netif_ip4_addr(&physical_netif)->addr;
    }
    if (netmask) {
        *netmask = netif_ip4_netmask(&physical_netif)->addr;
    }
    if (gateway) {
        *gateway = netif_ip4_gw(&physical_netif)->addr;
    }
    if (dns) {
        for (index = 0; index < 3; ++index) {
            const ip_addr_t *server = dns_getserver((uint8_t)index);
            dns[index] = IP_IS_V4(server) ? ip_2_ip4(server)->addr : 0;
        }
    }
    return 1;
}

int vinix_net_link(uint8_t mac[6], uint32_t *mtu) {
    if (!link_attached) {
        return 0;
    }
    memcpy(mac, physical_netif.hwaddr, 6);
    *mtu = physical_netif.mtu;
    return 1;
}

struct vinix_socket *vinix_socket_new_family(int family, int type, int protocol) {
    struct vinix_socket *socket;
    if (!stack_initialised) {
        vinix_net_init();
    }
    if (family != 2 && family != 10) return NULL;
    if ((type == VINIX_NET_STREAM && protocol != 0 && protocol != 6) ||
        (type == VINIX_NET_DGRAM && protocol != 0 && protocol != 17)) {
        return NULL;
    }
    socket = (struct vinix_socket *)mem_calloc(1, sizeof(*socket));
    if (!socket) {
        return NULL;
    }
    socket->family = family;
    ip_addr_set_any(family == 10, &socket->last_local_address);
    socket->type = type;
    socket->protocol = protocol ? protocol : (type == VINIX_NET_STREAM ? 6 : 17);
    socket->send_limit = type == VINIX_NET_STREAM ? TCP_SND_BUF : 212992;
    socket->receive_limit = type == VINIX_NET_STREAM ? TCP_WND + 4096 : 212992;
    socket->keep_idle = TCP_KEEPIDLE_DEFAULT;
    socket->keep_interval = TCP_KEEPINTVL_DEFAULT;
    socket->keep_count = TCP_KEEPCNT_DEFAULT;
    if (type == VINIX_NET_STREAM) {
        socket->tcp = tcp_new_ip_type(family == 10 ? IPADDR_TYPE_ANY : IPADDR_TYPE_V4);
        if (!socket->tcp) {
            mem_free(socket);
            return NULL;
        }
        install_tcp_callbacks(socket);
    } else if (type == VINIX_NET_DGRAM) {
        socket->udp = udp_new_ip_type(family == 10 ? IPADDR_TYPE_ANY : IPADDR_TYPE_V4);
        if (!socket->udp) {
            mem_free(socket);
            return NULL;
        }
        udp_recv(socket->udp, udp_received, socket);
    } else {
        mem_free(socket);
        return NULL;
    }
    return socket;
}

void vinix_socket_free(struct vinix_socket *socket) {
    if (!socket) {
        return;
    }
    free_packets(socket);
    while (socket->accept_head) {
        struct vinix_socket *child = socket->accept_head;
        socket->accept_head = child->accept_next;
        child->accept_next = NULL;
        vinix_socket_free(child);
    }
    if (socket->tcp && socket->tcp->state == LISTEN) {
        // A listening pcb is lwIP's smaller tcp_pcb_listen. It has no data
        // callbacks, and lwIP asserts if asked to clear them. Closing one
        // cannot fail.
        tcp_arg(socket->tcp, NULL);
        tcp_accept(socket->tcp, NULL);
        tcp_close(socket->tcp);
        socket->tcp = NULL;
    } else if (socket->tcp) {
        tcp_arg(socket->tcp, NULL);
        tcp_recv(socket->tcp, NULL);
        tcp_sent(socket->tcp, NULL);
        tcp_err(socket->tcp, NULL);
        if (socket->abort_on_close || tcp_close(socket->tcp) != ERR_OK) {
            tcp_abort(socket->tcp);
        }
        socket->tcp = NULL;
    }
    if (socket->udp) {
        udp_recv(socket->udp, NULL, NULL);
        udp_remove(socket->udp);
        socket->udp = NULL;
    }
    mem_free(socket);
}

static ip_addr_t ipv4(uint32_t address) {
    ip_addr_t result;
    IP_SET_TYPE_VAL(result, IPADDR_TYPE_V4);
    ip_2_ip4(&result)->addr = address;
    return result;
}

/* The IPv4 ABI remains available to procfs and existing consumers. */
struct vinix_socket *vinix_socket_new(int type, int protocol) {
    return vinix_socket_new_family(2, type, protocol);
}

static struct vinix_ip_address public_ipv4(uint32_t address) {
    struct vinix_ip_address result = { .family = 2 };
    memcpy(result.bytes, &address, 4);
    return result;
}

static int decode_address(struct vinix_socket *socket,
                          const struct vinix_ip_address *address, ip_addr_t *ip,
                          int binding) {
    if (!address || !socket) return 22;
    if (address->family == 2) {
        if (socket->family != 2) return 97;
        *ip = ipv4(0);
        memcpy(&ip_2_ip4(ip)->addr, address->bytes, 4);
        return 0;
    }
    if (address->family != 10 || socket->family != 10) return 97;
    ip_addr_set_zero_ip6(ip);
    memcpy(ip_2_ip6(ip)->addr, address->bytes, 16);
    if (ip6_addr_isipv4mappedipv6(ip_2_ip6(ip))) {
        if (socket->v6only) return binding ? 22 : 101;
        uint32_t mapped = ip_2_ip6(ip)->addr[3];
        *ip = ipv4(mapped);
        return 0;
    }
    if (ip6_addr_has_scope(ip_2_ip6(ip), IP6_UNKNOWN)) {
        if (!address->scope) return 22;
        if (address->scope != 2 || !link_attached) return 19;
        ip6_addr_assign_zone(ip_2_ip6(ip), IP6_UNKNOWN, &physical_netif);
    } else if (address->scope > 2) {
        return 19;
    }
    if (binding && !ip6_addr_isany(ip_2_ip6(ip)) &&
        !ip6_addr_isloopback(ip_2_ip6(ip)) && !ip6_addr_ismulticast(ip_2_ip6(ip))) {
        int found = 0;
        if (link_attached) {
            for (unsigned i = 0; i < LWIP_IPV6_NUM_ADDRESSES; ++i) {
                if (ip6_addr_isvalid(netif_ip6_addr_state(&physical_netif, i)) &&
                    ip6_addr_cmp(ip_2_ip6(ip), netif_ip6_addr(&physical_netif, i))) found = 1;
            }
        }
        if (!found) return 99;
    }
    if (binding && !socket->v6only && ip6_addr_isany(ip_2_ip6(ip))) {
        IP_SET_TYPE(ip, IPADDR_TYPE_ANY);
    }
    return 0;
}

static void encode_address(struct vinix_socket *socket, const ip_addr_t *ip,
                           struct vinix_ip_address *address) {
    if (!address) return;
    memset(address, 0, sizeof(*address));
    address->family = (uint32_t)socket->family;
    if (socket->family == 10) {
        if (IP_IS_V4(ip)) {
            address->bytes[10] = address->bytes[11] = 0xff;
            memcpy(address->bytes + 12, &ip_2_ip4(ip)->addr, 4);
        } else if (IP_IS_V6(ip)) {
            memcpy(address->bytes, ip_2_ip6(ip)->addr, 16);
            if (ip6_addr_has_zone(ip_2_ip6(ip))) address->scope = 2;
        }
    } else if (IP_IS_V4(ip)) {
        memcpy(address->bytes, &ip_2_ip4(ip)->addr, 4);
    }
}

int vinix_net_ipv6_address(unsigned index, unsigned slot,
                           struct vinix_ip_address *address,
                           unsigned *prefix, unsigned *flags) {
    if (!address || !prefix || !flags) return 0;
    memset(address, 0, sizeof(*address));
    address->family = 10;
    if (index == 1 && slot == 0) {
        address->bytes[15] = 1;
        *prefix = 128;
        *flags = 0x80; /* IFA_F_PERMANENT */
        return 1;
    }
    if (index != 2 || !link_attached || slot >= LWIP_IPV6_NUM_ADDRESSES) return 0;
    unsigned state = netif_ip6_addr_state(&physical_netif, slot);
    if (state == IP6_ADDR_INVALID) return 0;
    const ip6_addr_t *ip = netif_ip6_addr(&physical_netif, slot);
    memcpy(address->bytes, ip->addr, 16);
    address->scope = ip6_addr_islinklocal(ip) ? 2 : 0;
    *prefix = 64; /* lwIP SLAAC and EUI-64 link-local prefixes. */
    *flags = ip6_addr_istentative(state) ? 0x40 : 0;
    if (state == IP6_ADDR_DEPRECATED) *flags |= 0x20;
    return 1;
}

static int tcp_port_taken(uint16_t port, void *context) {
    int i;
    struct tcp_pcb *pcb;
    (void)context;
    for (i = 0; i < NUM_TCP_PCB_LISTS; i++) {
        for (pcb = *tcp_pcb_lists[i]; pcb != NULL; pcb = pcb->next) {
            if (pcb->local_port == port) {
                return 1;
            }
        }
    }
    return 0;
}

static int udp_port_taken(uint16_t port, void *context) {
    struct udp_pcb *pcb;
    (void)context;
    for (pcb = udp_pcbs; pcb != NULL; pcb = pcb->next) {
        if (pcb->local_port == port) {
            return 1;
        }
    }
    return 0;
}

/* Bind an unbound socket to an ephemeral port picked at random, where lwIP
 * would have taken the one after the last it gave out. Every way a socket can
 * be given a port without naming one comes through here: bind() to port 0,
 * and connect(), listen() and sendto() on a socket not yet bound. 99 is
 * EADDRNOTAVAIL, Linux's answer when the range is used up. */
static int bind_ephemeral(struct vinix_socket *socket, const ip_addr_t *address) {
    int stream = socket->type == VINIX_NET_STREAM;
    uint16_t port = vinix_pick_port(VINIX_EPHEMERAL_FIRST, VINIX_EPHEMERAL_LAST,
                                    stream ? tcp_port_taken : udp_port_taken, NULL);
    if (!port) {
        return 99;
    }
    return linux_error(stream ? tcp_bind(socket->tcp, address, port)
                              : udp_bind(socket->udp, address, port));
}

int vinix_socket_bind_ip(struct vinix_socket *socket, const struct vinix_ip_address *address, uint16_t port) {
    ip_addr_t ip;
    err_t error;
    if (!socket) {
        return 88;
    }
    int decoded = decode_address(socket, address, &ip, 1);
    if (decoded) return decoded;
    if (socket->bound) return 22;
    if (socket->type == VINIX_NET_STREAM && !socket->tcp) {
        return socket->error ? socket->error : 107;
    }
    if (port == 0) {
        int result = bind_ephemeral(socket, &ip);
        if (!result) socket->bound = 1;
        return result;
    }
    if (socket->type == VINIX_NET_STREAM) {
        error = tcp_bind(socket->tcp, &ip, lwip_ntohs(port));
    } else {
        error = udp_bind(socket->udp, &ip, lwip_ntohs(port));
    }
    if (error == ERR_OK) socket->bound = 1;
    return linux_error(error);
}

int vinix_socket_connect_ip(struct vinix_socket *socket, const struct vinix_ip_address *address, uint16_t port) {
    ip_addr_t ip;
    err_t error;
    if (!socket) {
        return 88;
    }
    int decoded = decode_address(socket, address, &ip, 0);
    if (decoded) return decoded;
    if (socket->type == VINIX_NET_STREAM) {
        if (!socket->tcp) return socket->error ? socket->error : 107;
        if (socket->connected) {
            return 106;
        }
        if (socket->connecting) {
            return 114;
        }
        if (socket->tcp->local_port == 0) {
            int bound = bind_ephemeral(socket, &socket->tcp->local_ip);
            if (bound) {
                return bound;
            }
        }
        socket->connecting = 1;
        error = tcp_connect(socket->tcp, &ip, lwip_ntohs(port), tcp_connected);
        if (error != ERR_OK) {
            socket->connecting = 0;
            return linux_error(error);
        }
        ip_addr_copy(socket->last_local_address, socket->tcp->local_ip);
        socket->last_local_port = lwip_htons(socket->tcp->local_port);
        /* NO_SYS loopback queues packets until netif_poll_all().  A busy
         * nonblocking client may never let the scheduler reach its idle
         * poller, so complete the in-kernel handshake synchronously. */
        netif_poll_all();
        if (socket->error) {
            return socket->error;
        }
        if (socket->connected) {
            return 0;
        }
        return 115;
    }
    if (socket->udp->local_port == 0) {
        int bound = bind_ephemeral(socket, &socket->udp->local_ip);
        if (bound) {
            return bound;
        }
    }
    error = udp_connect(socket->udp, &ip, lwip_ntohs(port));
    if (error == ERR_OK) {
        socket->connected = 1;
    }
    return linux_error(error);
}

int vinix_socket_listen(struct vinix_socket *socket, int backlog) {
    struct tcp_pcb *listener;
    err_t error = ERR_OK;
    if (!socket || !socket->tcp || socket->connected || socket->connecting) {
        return 95;
    }
    if (backlog < 0) {
        return 22;
    }
    if (backlog > 255) {
        backlog = 255;
    }
    if (socket->tcp->local_port == 0) {
        int bound = bind_ephemeral(socket, &socket->tcp->local_ip);
        if (bound) {
            return bound;
        }
    }
    listener = tcp_listen_with_backlog_and_err(socket->tcp, (uint8_t)backlog, &error);
    if (!listener) {
        return linux_error(error);
    }
    socket->tcp = listener;
    socket->listening = 1;
    tcp_arg(socket->tcp, socket);
    tcp_accept(socket->tcp, accept_callback);
    return 0;
}

struct vinix_socket *vinix_socket_accept(struct vinix_socket *socket) {
    struct vinix_socket *child;
    if (!socket || !socket->listening || !socket->accept_head) {
        return NULL;
    }
    child = socket->accept_head;
    socket->accept_head = child->accept_next;
    if (!socket->accept_head) {
        socket->accept_tail = NULL;
    }
    child->accept_next = NULL;
    tcp_backlog_accepted(socket->tcp);
    return child;
}

int vinix_socket_send_ip(struct vinix_socket *socket, const void *data, size_t length,
                      const struct vinix_ip_address *address, uint16_t port, int has_address) {
    err_t error;
    if (!socket || (!data && length)) {
        return -22;
    }
    if (socket->write_shutdown) {
        return -32;
    }
    if (socket->type == VINIX_NET_STREAM) {
        uint16_t amount;
        if (!socket->tcp) return -(socket->error ? socket->error : 107);
        if (!socket->connected) {
            return -107;
        }
        if (has_address) {
            return -106;
        }
        if (length == 0) {
            return 0;
        }
        amount = tcp_sndbuf(socket->tcp);
        if (socket->send_queued >= socket->send_limit) return -11;
        if (amount > socket->send_limit - socket->send_queued) {
            amount = (uint16_t)(socket->send_limit - socket->send_queued);
        }
        if (amount > length) {
            amount = (uint16_t)length;
        }
        if (!amount) {
            return -11;
        }
        error = tcp_write(socket->tcp, data, amount, TCP_WRITE_FLAG_COPY);
        if (error != ERR_OK) {
            return -linux_error(error);
        }
        socket->send_queued += amount;
        /* tcp_write accepted these bytes. Output failure leaves them queued
         * for retransmission; reporting failure would let callers duplicate
         * the same bytes on retry. */
        (void)tcp_output(socket->tcp);
        netif_poll_all();
        return amount;
    } else {
        struct pbuf *p;
        if (!has_address && !socket->connected) {
            return -89;
        }
        if (length > 65507 || length > socket->send_limit) {
            return -90;
        }
        if (socket->udp->local_port == 0) {
            int bound = bind_ephemeral(socket, &socket->udp->local_ip);
            if (bound) {
                return -bound;
            }
        }
        p = pbuf_alloc(PBUF_TRANSPORT, (uint16_t)length, PBUF_RAM);
        if (!p) {
            return -12;
        }
        if (length && pbuf_take(p, data, (uint16_t)length) != ERR_OK) {
            pbuf_free(p);
            return -12;
        }
        if (has_address) {
            ip_addr_t ip;
            int decoded = decode_address(socket, address, &ip, 0);
            if (decoded) { pbuf_free(p); return -decoded; }
            error = udp_sendto(socket->udp, p, &ip, lwip_ntohs(port));
        } else {
            error = udp_send(socket->udp, p);
        }
        pbuf_free(p);
        if (error != ERR_OK) {
            return -linux_error(error);
        }
        /* Deliver loopback datagrams before returning.  External packets do
         * not use a loop queue, so polling here is a cheap no-op for them. */
        netif_poll_all();
        return (int)length;
    }
}

int vinix_socket_recv_ip(struct vinix_socket *socket, void *data, size_t length,
                      struct vinix_ip_address *address, uint16_t *port) {
    struct packet *packet;
    uint16_t available;
    uint16_t amount;
    if (!socket || (!data && length)) {
        return -22;
    }
    if (socket->read_shutdown) {
        return 0;
    }
    packet = socket->rx_head;
    if (!packet) {
        if (socket->type == VINIX_NET_STREAM && socket->peer_closed && !socket->error) {
            return 0;
        }
        if (socket->type == VINIX_NET_STREAM && !socket->connected) {
            return -(socket->error ? socket->error : 107);
        }
        return -11;
    }
    available = (uint16_t)(packet->p->tot_len - packet->offset);
    amount = available < length ? available : (uint16_t)length;
    if (amount) {
        pbuf_copy_partial(packet->p, data, amount, packet->offset);
    }
    if (address) {
        encode_address(socket, &packet->address, address);
    }
    if (port) {
        *port = lwip_htons(packet->port);
    }
    if (socket->type == VINIX_NET_STREAM) {
        packet->offset = (uint16_t)(packet->offset + amount);
        if (socket->tcp) tcp_recved(socket->tcp, amount);
        if (packet->offset == packet->p->tot_len) {
            socket->receive_queued -= packet->charge;
            socket->rx_head = packet->next;
            if (!socket->rx_head) {
                socket->rx_tail = NULL;
            }
            free_packet(packet);
        }
    } else {
        /* recvfrom consumes one datagram, including a truncated tail. */
        socket->receive_queued -= packet->charge;
        socket->rx_head = packet->next;
        if (!socket->rx_head) {
            socket->rx_tail = NULL;
        }
        free_packet(packet);
    }
    return amount;
}

int vinix_socket_shutdown(struct vinix_socket *socket, int how) {
    err_t error;
    if (!socket || how < 0 || how > 2) {
        return 22;
    }
    if (how == 0 || how == 2) {
        socket->read_shutdown = 1;
        free_packets(socket);
    }
    if (how == 1 || how == 2) {
        socket->write_shutdown = 1;
    }
    if (socket->type == VINIX_NET_STREAM) {
        if (!socket->tcp) return socket->connected ? 0 : 107;
        if (socket->write_shutdown &&
            (socket->read_shutdown || socket->peer_closed) &&
            socket->tcp->state != LISTEN) {
            struct tcp_pcb *pcb = socket->tcp;
            int connecting = socket->connecting;
            /* Even ERR_MEM while enqueueing FIN is converted by lwIP into
             * ERR_OK plus TF_CLOSEPEND. Detach before calling: a successful
             * full shutdown may free pcb immediately, or from a later timer.
             * After peer EOF, write shutdown also completes the protocol;
             * keep queued receive bytes by leaving its receive side open.
             */
            detach_tcp(socket, pcb);
            error = tcp_shutdown(pcb, socket->read_shutdown, 1);
            if (error != ERR_OK) {
                socket->tcp = pcb;
                socket->connecting = connecting;
                install_tcp_callbacks(socket);
            }
            return linux_error(error);
        }
        error = tcp_shutdown(socket->tcp, how == 0 || how == 2,
                             how == 1 || how == 2);
        return linux_error(error);
    }
    if (how == 1 || how == 2) {
        udp_disconnect(socket->udp);
        socket->connected = 0;
    }
    return 0;
}

int vinix_socket_local_ip(struct vinix_socket *socket,
                           struct vinix_ip_address *address, uint16_t *port) {
    if (!socket) return 88;
    if (socket->type == VINIX_NET_STREAM) {
        encode_address(socket, socket->tcp ? &socket->tcp->local_ip :
                        &socket->last_local_address, address);
        if (port) *port = socket->tcp ? lwip_htons(socket->tcp->local_port) : socket->last_local_port;
    } else {
        encode_address(socket, &socket->udp->local_ip, address);
        if (port) *port = lwip_htons(socket->udp->local_port);
    }
    return 0;
}

int vinix_socket_peer_ip(struct vinix_socket *socket,
                          struct vinix_ip_address *address, uint16_t *port) {
    if (!socket || !socket->connected) return 107;
    if (socket->type == VINIX_NET_STREAM) {
        encode_address(socket, socket->tcp ? &socket->tcp->remote_ip :
                        &socket->last_remote_address, address);
        if (port) *port = socket->tcp ? lwip_htons(socket->tcp->remote_port) : socket->last_remote_port;
    } else {
        encode_address(socket, &socket->udp->remote_ip, address);
        if (port) *port = lwip_htons(socket->udp->remote_port);
    }
    return 0;
}

int vinix_socket_bind(struct vinix_socket *socket, uint32_t address, uint16_t port) {
    struct vinix_ip_address ip = public_ipv4(address);
    return vinix_socket_bind_ip(socket, &ip, port);
}
int vinix_socket_connect(struct vinix_socket *socket, uint32_t address, uint16_t port) {
    struct vinix_ip_address ip = public_ipv4(address);
    return vinix_socket_connect_ip(socket, &ip, port);
}
int vinix_socket_send(struct vinix_socket *socket, const void *data, size_t length,
                      uint32_t address, uint16_t port, int has_address) {
    struct vinix_ip_address ip = public_ipv4(address);
    return vinix_socket_send_ip(socket, data, length, &ip, port, has_address);
}
int vinix_socket_recv(struct vinix_socket *socket, void *data, size_t length,
                      uint32_t *address, uint16_t *port) {
    struct vinix_ip_address ip = {0};
    int result = vinix_socket_recv_ip(socket, data, length, &ip, port);
    if (result >= 0 && address) memcpy(address, ip.bytes, 4);
    return result;
}
int vinix_socket_local(struct vinix_socket *socket, uint32_t *address, uint16_t *port) {
    struct vinix_ip_address ip;
    int result = vinix_socket_local_ip(socket, &ip, port);
    if (!result && address) memcpy(address, ip.bytes, 4);
    return result;
}
int vinix_socket_peer(struct vinix_socket *socket, uint32_t *address, uint16_t *port) {
    struct vinix_ip_address ip;
    int result = vinix_socket_peer_ip(socket, &ip, port);
    if (!result && address) memcpy(address, ip.bytes, 4);
    return result;
}

int vinix_socket_ready(struct vinix_socket *socket) {
    int ready = 0;
    if (!socket) {
        return VINIX_NET_ERROR;
    }
    if (socket->listening ? socket->accept_head != NULL :
        (socket->rx_head != NULL || socket->peer_closed || socket->read_shutdown)) {
        ready |= VINIX_NET_READABLE;
    }
    if (!socket->write_shutdown &&
        ((socket->tcp && socket->connected && tcp_sndbuf(socket->tcp) > 0 &&
          socket->send_queued < socket->send_limit) ||
         socket->udp)) {
        ready |= VINIX_NET_WRITABLE;
    }
    if (socket->error) {
        ready |= VINIX_NET_ERROR;
    }
    if (socket->peer_closed) {
        ready |= VINIX_NET_HANGUP;
    }
    return ready;
}

int vinix_socket_error(struct vinix_socket *socket, int clear) {
    int error;
    if (!socket) {
        return 88;
    }
    error = socket->error;
    if (clear) {
        socket->error = 0;
    }
    return error;
}

int vinix_socket_available(struct vinix_socket *socket) {
    struct packet *packet;
    unsigned int total = 0;
    if (!socket) {
        return 0;
    }
    for (packet = socket->rx_head; packet; packet = packet->next) {
        total += packet->p->tot_len - packet->offset;
        if (socket->udp) {
            break;
        }
    }
    return total > 0x7fffffffU ? 0x7fffffff : (int)total;
}

static struct ip_pcb *socket_ip_pcb(struct vinix_socket *socket) {
    if (socket->tcp) {
        return (struct ip_pcb *)socket->tcp;
    }
    return (struct ip_pcb *)socket->udp;
}

int vinix_socket_set_option(struct vinix_socket *socket, int level, int option,
                            int value) {
    struct ip_pcb *pcb;
    if (!socket) {
        return 88;
    }
    pcb = socket_ip_pcb(socket);
    if (level == 1) { /* SOL_SOCKET */
        switch (option) {
        case 2:  /* SO_REUSEADDR */
        case 15: /* SO_REUSEPORT: lwIP shares address-reuse semantics. */
            socket->reuseaddr = value != 0;
            if (pcb) {
                if (value) ip_set_option(pcb, SOF_REUSEADDR);
                else ip_reset_option(pcb, SOF_REUSEADDR);
            }
            return 0;
        case 6: /* SO_BROADCAST */
            socket->broadcast = value != 0;
            if (pcb) {
                if (value) ip_set_option(pcb, SOF_BROADCAST);
                else ip_reset_option(pcb, SOF_BROADCAST);
            }
            return 0;
        case 7: /* SO_SNDBUF: Linux doubles the requested size. */
        case 8: /* SO_RCVBUF */
            if (value < 0) return 22;
            if (value > 2 * 1024 * 1024) value = 2 * 1024 * 1024;
            value = value < 2048 ? 4096 : value * 2;
            if (option == 7) socket->send_limit = (uint32_t)value;
            else socket->receive_limit = (uint32_t)value;
            return 0;
        case 9: /* SO_KEEPALIVE */
            socket->keepalive = value != 0;
            if (pcb) {
                if (value) ip_set_option(pcb, SOF_KEEPALIVE);
                else ip_reset_option(pcb, SOF_KEEPALIVE);
            }
            return 0;
        default:
            return 92;
        }
    }
    if (level == 41 && socket->family == 10) {
        if (!pcb) return 107;
        if (option == 26) { /* IPV6_V6ONLY, before binding or connecting. */
            if (value != 0 && value != 1) return 22;
            if (socket->bound || socket->connected || socket->connecting || socket->listening ||
                (socket->tcp && socket->tcp->local_port) ||
                (socket->udp && socket->udp->local_port)) return 22;
            socket->v6only = value;
            ip_addr_set_any(value, &pcb->local_ip);
            if (!value) IP_SET_TYPE(&pcb->local_ip, IPADDR_TYPE_ANY);
            return 0;
        }
        if (option == 16) { /* IPV6_UNICAST_HOPS */
            if (value < -1 || value > 255) return 22;
            pcb->ttl = value == -1 ? 64 : (uint8_t)value;
            return 0;
        }
        return 92;
    }
    if (level == 0) { /* IPPROTO_IP */
        if (!pcb) return 107;
        if (value < 0 || value > 255) {
            return 22;
        }
        switch (option) {
        case 1: /* IP_TOS */
            pcb->tos = (uint8_t)value;
            return 0;
        case 2: /* IP_TTL */
            if (value == 0) return 22;
            pcb->ttl = (uint8_t)value;
            return 0;
        default:
            return 92;
        }
    }
    if (level == 6) { /* IPPROTO_TCP */
        if (socket->type != VINIX_NET_STREAM) return 92;
        switch (option) {
        case 4: /* TCP_KEEPIDLE */
        case 5: /* TCP_KEEPINTVL */
        case 6: /* TCP_KEEPCNT */
            if (value < 1 || value > (option == 6 ? 127 : 32767)) return 22;
            if (option == 4) socket->keep_idle = (uint32_t)value * 1000;
            else if (option == 5) socket->keep_interval = (uint32_t)value * 1000;
            else socket->keep_count = (uint32_t)value;
            if (socket->tcp && socket->tcp->state != LISTEN) {
                socket->tcp->keep_idle = socket->keep_idle;
                socket->tcp->keep_intvl = socket->keep_interval;
                socket->tcp->keep_cnt = socket->keep_count;
                socket->tcp->keep_cnt_sent = 0;
            }
            return 0;
        case 1: /* TCP_NODELAY */
            if (!socket->tcp) return 92;
            /* A listening pcb is lwIP's smaller tcp_pcb_listen, which has no
             * flags: its accept callback lies where they would be, and
             * setting TF_NODELAY there turned the callback into a pointer
             * to nowhere, which the next connection to finish its handshake
             * called. Varnish sets it on its listening socket. */
            socket->nodelay = value != 0;
            if (socket->tcp->state == LISTEN) {
                return 0;
            }
            if (value) tcp_nagle_disable(socket->tcp);
            else tcp_nagle_enable(socket->tcp);
            return 0;
        default:
            return 92;
        }
    }
    return 92;
}

int vinix_socket_get_option(struct vinix_socket *socket, int level, int option,
                            int *value) {
    struct ip_pcb *pcb;
    if (!socket || !value) {
        return 22;
    }
    pcb = socket_ip_pcb(socket);
    if (level == 1) { /* SOL_SOCKET */
        switch (option) {
        case 2:
        case 15: *value = socket->reuseaddr; return 0;
        case 6: *value = socket->broadcast; return 0;
        case 7: *value = (int)socket->send_limit; return 0;
        case 8: *value = (int)socket->receive_limit; return 0;
        case 9: *value = socket->keepalive; return 0;
        default: return 92;
        }
    }
    if (level == 41 && socket->family == 10) {
        if (option == 26) { *value = socket->v6only; return 0; }
        if (option == 16 && pcb) { *value = pcb->ttl; return 0; }
        return 92;
    }
    if (level == 0) { /* IPPROTO_IP */
        if (!pcb) return 107;
        switch (option) {
        case 1: *value = pcb->tos; return 0;
        case 2: *value = pcb->ttl; return 0;
        default: return 92;
        }
    }
    if (level == 6) { /* IPPROTO_TCP */
        if (socket->type != VINIX_NET_STREAM) return 92;
        switch (option) {
        case 4: *value = (int)(socket->keep_idle / 1000); return 0;
        case 5: *value = (int)(socket->keep_interval / 1000); return 0;
        case 6: *value = (int)socket->keep_count; return 0;
        case 1:
            if (!socket->tcp) return 92;
            if (socket->tcp->state == LISTEN) {
                *value = socket->nodelay;
                return 0;
            }
            *value = tcp_nagle_disabled(socket->tcp) ? 1 : 0;
            return 0;
        default: return 92;
        }
    }
    return 92;
}

/* The V descriptor remains registered while close waits for acknowledgments.
 * Abort is also used after a linger timeout, before freeing callbacks. */
int vinix_socket_pending(struct vinix_socket *socket) {
    return socket && socket->tcp && !socket->listening ?
        (int)socket->send_queued : 0;
}

void vinix_socket_abort_close(struct vinix_socket *socket) {
    if (socket) socket->abort_on_close = 1;
}
