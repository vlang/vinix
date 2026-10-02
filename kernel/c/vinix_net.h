#ifndef VINIX_NET_H
#define VINIX_NET_H

#include <stddef.h>
#include <stdint.h>

struct vinix_socket;

/* Family and public interface index, followed by bytes in network order. */
struct vinix_ip_address {
    uint32_t family;
    uint32_t scope;
    uint8_t bytes[16];
};

enum {
    VINIX_NET_STREAM = 1,
    VINIX_NET_DGRAM = 2,
};

enum {
    VINIX_NET_READABLE = 1,
    VINIX_NET_WRITABLE = 2,
    VINIX_NET_ERROR = 4,
    VINIX_NET_HANGUP = 8,
};

void vinix_net_init(void);
void vinix_net_poll(uint32_t now_ms);
int vinix_net_attach(const uint8_t mac[6], int driver);
void vinix_net_detach(void);
int vinix_net_input(const void *frame, size_t length);
int vinix_net_config(uint32_t *address, uint32_t *netmask, uint32_t *gateway,
                     uint32_t dns[3]);
int vinix_net_link(uint8_t mac[6], uint32_t *mtu);

struct vinix_socket *vinix_socket_new(int type, int protocol);
struct vinix_socket *vinix_socket_new_family(int family, int type, int protocol);
int vinix_net_ipv6_address(unsigned index, unsigned slot, struct vinix_ip_address *address,
                           unsigned *prefix, unsigned *flags);
int vinix_socket_bind_ip(struct vinix_socket *, const struct vinix_ip_address *, uint16_t);
int vinix_socket_connect_ip(struct vinix_socket *, const struct vinix_ip_address *, uint16_t);
int vinix_socket_send_ip(struct vinix_socket *, const void *, size_t,
                         const struct vinix_ip_address *, uint16_t, int);
int vinix_socket_recv_ip(struct vinix_socket *, void *, size_t,
                         struct vinix_ip_address *, uint16_t *);
int vinix_socket_local_ip(struct vinix_socket *, struct vinix_ip_address *, uint16_t *);
int vinix_socket_peer_ip(struct vinix_socket *, struct vinix_ip_address *, uint16_t *);
void vinix_socket_free(struct vinix_socket *socket);
int vinix_socket_pending(struct vinix_socket *socket);
void vinix_socket_abort_close(struct vinix_socket *socket);
int vinix_socket_bind(struct vinix_socket *socket, uint32_t address, uint16_t port);
int vinix_socket_connect(struct vinix_socket *socket, uint32_t address, uint16_t port);
int vinix_socket_listen(struct vinix_socket *socket, int backlog);
struct vinix_socket *vinix_socket_accept(struct vinix_socket *socket);
int vinix_socket_send(struct vinix_socket *socket, const void *data, size_t length,
                      uint32_t address, uint16_t port, int has_address);
int vinix_socket_recv(struct vinix_socket *socket, void *data, size_t length,
                      uint32_t *address, uint16_t *port);
int vinix_socket_shutdown(struct vinix_socket *socket, int how);
int vinix_socket_local(struct vinix_socket *socket, uint32_t *address, uint16_t *port);
int vinix_socket_peer(struct vinix_socket *socket, uint32_t *address, uint16_t *port);
int vinix_socket_ready(struct vinix_socket *socket);
int vinix_socket_error(struct vinix_socket *socket, int clear);
int vinix_socket_available(struct vinix_socket *socket);
int vinix_socket_set_option(struct vinix_socket *socket, int level, int option,
                            int value);
int vinix_socket_get_option(struct vinix_socket *socket, int level, int option,
                            int *value);

uint32_t vinix_htonl(uint32_t value);
uint16_t vinix_htons(uint16_t value);

#endif
