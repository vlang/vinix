#ifndef VINIX_INET6_H
#define VINIX_INET6_H
#include <stddef.h>
#ifndef VINIX_NET_CONST
#ifdef VINIX_V_RUNTIME
#define VINIX_NET_CONST
#define vinix_socket netcore__Vinix_socket
#else
#define VINIX_NET_CONST const
#endif
#endif
#include "vinix_endpoint.h"
struct vinix_socket;
struct vinix_socket *vinix_socket_new_family(int type, int protocol, int family);
int vinix_socket_bind_endpoint(struct vinix_socket *, VINIX_NET_CONST struct vinix_net_endpoint *);
int vinix_socket_connect_endpoint(struct vinix_socket *, VINIX_NET_CONST struct vinix_net_endpoint *);
int vinix_socket_send_endpoint(struct vinix_socket *, VINIX_NET_CONST void *, size_t,
                               VINIX_NET_CONST struct vinix_net_endpoint *, int);
int vinix_socket_recv_endpoint(struct vinix_socket *, void *, size_t, struct vinix_net_endpoint *);
int vinix_socket_name_endpoint(struct vinix_socket *, struct vinix_net_endpoint *, int);
int vinix_socket_membership(struct vinix_socket *, VINIX_NET_CONST struct vinix_net_endpoint *,
                            uint32_t interface_address, int join);
int vinix_socket_multicast_interface(struct vinix_socket *, int family, uint32_t index,
                                     uint32_t interface_address);
int vinix_net_ipv6_address(uint32_t index, uint32_t slot, struct vinix_net_endpoint *,
                           uint32_t *state, uint32_t *valid_life, uint32_t *preferred_life);
#endif
