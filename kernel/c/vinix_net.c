#include "vinix_net.h"

#include <lwip/dhcp.h>
#include <lwip/dns.h>
#include <lwip/etharp.h>
#include <lwip/init.h>
#include <lwip/ip.h>
#include <lwip/mem.h>
#include <lwip/netif.h>
#include <lwip/pbuf.h>
#include <lwip/tcp.h>
#include <lwip/timeouts.h>
#include <lwip/udp.h>
#include <netif/ethernet.h>

#include <stdio.h>
#include <string.h>

/* Drivers are deliberately below the IP stack.  The weak VirtIO symbol keeps
 * the same stack buildable on x86, while Apple's C bridge is already built on
 * both architectures. */
extern int vinix_virtio_net_send(const void *, uint64_t) __attribute__((weak));
extern int vinix_apple_wifi_send(const void *, uint64_t) __attribute__((weak));

enum {
    DRIVER_NONE = 0,
    DRIVER_VIRTIO = 1,
    DRIVER_APPLE_WIFI = 2,
};

struct packet {
    struct packet *next;
    struct pbuf *p;
    uint16_t offset;
    uint32_t address;
    uint16_t port;
};

struct vinix_socket {
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
    struct tcp_pcb *tcp;
    struct udp_pcb *udp;
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
static uint32_t random_state = 0x6d2b79f5U;

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

void vinix_lwip_assert(const char *message, const char *file, int line) {
    printf("lwip: assertion '%s' at %s:%d\n", message, file, line);
    for (;;) { }
}

uint32_t vinix_lwip_rand(void) {
    uint32_t value = random_state ^ clock_ms;
    value ^= value << 13;
    value ^= value >> 17;
    value ^= value << 5;
    random_state = value ? value : 0x6d2b79f5U;
    return random_state;
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
}

static int queue_packet(struct vinix_socket *socket, struct pbuf *p,
                        uint32_t address, uint16_t port) {
    struct packet *packet = (struct packet *)mem_malloc(sizeof(*packet));
    if (!packet) {
        return 0;
    }
    memset(packet, 0, sizeof(*packet));
    packet->p = p;
    packet->address = address;
    packet->port = port;
    if (socket->rx_tail) {
        socket->rx_tail->next = packet;
    } else {
        socket->rx_head = packet;
    }
    socket->rx_tail = packet;
    return 1;
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
        return ERR_OK;
    }
    if (socket->read_shutdown) {
        tcp_recved(pcb, p->tot_len);
        pbuf_free(p);
        return ERR_OK;
    }
    if (!queue_packet(socket, p, 0, 0)) {
        /* Keeping lwIP's ownership by refusing the packet applies TCP
         * backpressure instead of silently losing stream bytes. */
        return ERR_MEM;
    }
    return ERR_OK;
}

static err_t tcp_sent_data(void *argument, struct tcp_pcb *pcb, uint16_t length) {
    (void)argument;
    (void)pcb;
    (void)length;
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
    child->type = VINIX_NET_STREAM;
    child->protocol = 6;
    child->connected = 1;
    child->tcp = pcb;
    child->reuseaddr = ip_get_option(pcb, SOF_REUSEADDR) != 0;
    child->keepalive = ip_get_option(pcb, SOF_KEEPALIVE) != 0;
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
        !queue_packet(socket, p, ip_2_ip4(address)->addr, port)) {
        pbuf_free(p);
    }
}

void vinix_net_init(void) {
    if (stack_initialised) {
        return;
    }
    lwip_init();
    stack_initialised = 1;
    printf("net: lwIP 2.2.1, IPv4 TCP/UDP loopback ready\n");
}

static int driver_output(const void *frame, size_t length) {
    if (active_driver == DRIVER_VIRTIO && vinix_virtio_net_send) {
        return vinix_virtio_net_send(frame, (uint64_t)length);
    }
    if (active_driver == DRIVER_APPLE_WIFI) {
        return vinix_apple_wifi_send ?
            vinix_apple_wifi_send(frame, (uint64_t)length) : -1;
    }
    return -1;
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

static err_t physical_init(struct netif *netif) {
    netif->name[0] = 'e';
    netif->name[1] = 'n';
    netif->hwaddr_len = 6;
    memcpy(netif->hwaddr, active_mac, 6);
    netif->mtu = 1500;
    netif->flags = NETIF_FLAG_BROADCAST | NETIF_FLAG_ETHARP | NETIF_FLAG_ETHERNET;
    netif->output = etharp_output;
    netif->linkoutput = link_output;
    return ERR_OK;
}

int vinix_net_attach(const uint8_t mac[6], int driver) {
    ip4_addr_t zero;
    if (!stack_initialised) {
        vinix_net_init();
    }
    if (driver != DRIVER_VIRTIO && driver != DRIVER_APPLE_WIFI) {
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

struct vinix_socket *vinix_socket_new(int type, int protocol) {
    struct vinix_socket *socket;
    if (!stack_initialised) {
        vinix_net_init();
    }
    if ((type == VINIX_NET_STREAM && protocol != 0 && protocol != 6) ||
        (type == VINIX_NET_DGRAM && protocol != 0 && protocol != 17)) {
        return NULL;
    }
    socket = (struct vinix_socket *)mem_calloc(1, sizeof(*socket));
    if (!socket) {
        return NULL;
    }
    socket->type = type;
    socket->protocol = protocol ? protocol : (type == VINIX_NET_STREAM ? 6 : 17);
    if (type == VINIX_NET_STREAM) {
        socket->tcp = tcp_new_ip_type(IPADDR_TYPE_V4);
        if (!socket->tcp) {
            mem_free(socket);
            return NULL;
        }
        install_tcp_callbacks(socket);
    } else if (type == VINIX_NET_DGRAM) {
        socket->udp = udp_new_ip_type(IPADDR_TYPE_V4);
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
    if (socket->tcp) {
        tcp_arg(socket->tcp, NULL);
        tcp_recv(socket->tcp, NULL);
        tcp_sent(socket->tcp, NULL);
        tcp_err(socket->tcp, NULL);
        if (tcp_close(socket->tcp) != ERR_OK) {
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

int vinix_socket_bind(struct vinix_socket *socket, uint32_t address, uint16_t port) {
    ip_addr_t ip;
    err_t error;
    if (!socket) {
        return 88;
    }
    ip = ipv4(address);
    if (socket->tcp) {
        error = tcp_bind(socket->tcp, &ip, lwip_ntohs(port));
    } else {
        error = udp_bind(socket->udp, &ip, lwip_ntohs(port));
    }
    return linux_error(error);
}

int vinix_socket_connect(struct vinix_socket *socket, uint32_t address, uint16_t port) {
    ip_addr_t ip;
    err_t error;
    if (!socket) {
        return 88;
    }
    ip = ipv4(address);
    if (socket->tcp) {
        if (socket->connected) {
            return 106;
        }
        if (socket->connecting) {
            return 114;
        }
        socket->connecting = 1;
        error = tcp_connect(socket->tcp, &ip, lwip_ntohs(port), tcp_connected);
        if (error != ERR_OK) {
            socket->connecting = 0;
            return linux_error(error);
        }
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

int vinix_socket_send(struct vinix_socket *socket, const void *data, size_t length,
                      uint32_t address, uint16_t port, int has_address) {
    err_t error;
    if (!socket || (!data && length)) {
        return -22;
    }
    if (socket->write_shutdown) {
        return -32;
    }
    if (socket->tcp) {
        uint16_t amount;
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
        error = tcp_output(socket->tcp);
        if (error != ERR_OK) {
            return -linux_error(error);
        }
        netif_poll_all();
        return amount;
    } else {
        struct pbuf *p;
        if (!has_address && !socket->connected) {
            return -89;
        }
        if (length > 65507) {
            return -90;
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
            ip_addr_t ip = ipv4(address);
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

int vinix_socket_recv(struct vinix_socket *socket, void *data, size_t length,
                      uint32_t *address, uint16_t *port) {
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
        if (socket->tcp && socket->peer_closed) {
            return 0;
        }
        if (socket->tcp && !socket->connected) {
            return -107;
        }
        return -11;
    }
    available = (uint16_t)(packet->p->tot_len - packet->offset);
    amount = available < length ? available : (uint16_t)length;
    if (amount) {
        pbuf_copy_partial(packet->p, data, amount, packet->offset);
    }
    if (address) {
        *address = packet->address;
    }
    if (port) {
        *port = lwip_htons(packet->port);
    }
    if (socket->tcp) {
        packet->offset = (uint16_t)(packet->offset + amount);
        tcp_recved(socket->tcp, amount);
        if (packet->offset == packet->p->tot_len) {
            socket->rx_head = packet->next;
            if (!socket->rx_head) {
                socket->rx_tail = NULL;
            }
            free_packet(packet);
        }
    } else {
        /* recvfrom consumes one datagram, including a truncated tail. */
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
    if (socket->tcp) {
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

int vinix_socket_local(struct vinix_socket *socket, uint32_t *address, uint16_t *port) {
    if (!socket) {
        return 88;
    }
    if (socket->tcp) {
        if (address) *address = ip_2_ip4(&socket->tcp->local_ip)->addr;
        if (port) *port = lwip_htons(socket->tcp->local_port);
    } else {
        if (address) *address = ip_2_ip4(&socket->udp->local_ip)->addr;
        if (port) *port = lwip_htons(socket->udp->local_port);
    }
    return 0;
}

int vinix_socket_peer(struct vinix_socket *socket, uint32_t *address, uint16_t *port) {
    if (!socket || !socket->connected) {
        return 107;
    }
    if (socket->tcp) {
        if (address) *address = ip_2_ip4(&socket->tcp->remote_ip)->addr;
        if (port) *port = lwip_htons(socket->tcp->remote_port);
    } else {
        if (address) *address = ip_2_ip4(&socket->udp->remote_ip)->addr;
        if (port) *port = lwip_htons(socket->udp->remote_port);
    }
    return 0;
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
        ((socket->tcp && socket->connected && tcp_sndbuf(socket->tcp) > 0) ||
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
            socket->reuseaddr = value;
            if (value) ip_set_option(pcb, SOF_REUSEADDR);
            else ip_reset_option(pcb, SOF_REUSEADDR);
            return 0;
        case 6: /* SO_BROADCAST */
            socket->broadcast = value;
            if (value) ip_set_option(pcb, SOF_BROADCAST);
            else ip_reset_option(pcb, SOF_BROADCAST);
            return 0;
        case 9: /* SO_KEEPALIVE */
            socket->keepalive = value;
            if (value) ip_set_option(pcb, SOF_KEEPALIVE);
            else ip_reset_option(pcb, SOF_KEEPALIVE);
            return 0;
        default:
            return 92;
        }
    }
    if (level == 0) { /* IPPROTO_IP */
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
        switch (option) {
        case 1: /* TCP_NODELAY */
            if (!socket->tcp) return 92;
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
        case 9: *value = socket->keepalive; return 0;
        default: return 92;
        }
    }
    if (level == 0) { /* IPPROTO_IP */
        switch (option) {
        case 1: *value = pcb->tos; return 0;
        case 2: *value = pcb->ttl; return 0;
        default: return 92;
        }
    }
    if (level == 6) { /* IPPROTO_TCP */
        switch (option) {
        case 1:
            if (!socket->tcp) return 92;
            *value = tcp_nagle_disabled(socket->tcp) ? 1 : 0;
            return 0;
        default: return 92;
        }
    }
    return 92;
}
