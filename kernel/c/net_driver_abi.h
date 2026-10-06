// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VINIX_NET_DRIVER_ABI_H
#define VINIX_NET_DRIVER_ABI_H
#include <stdint.h>
/* Missing architecture drivers remain null weak function pointers. */
int vinix_virtio_net_send(void *, uint64_t) __attribute__((weak));
int vinix_apple_wifi_send(void *, uint64_t) __attribute__((weak));
int vinix_e1000_send(void *, uint64_t) __attribute__((weak));
/* These adapters only preserve const-qualified lwIP callback types at the V ABI. */
#include <lwip/netif.h>
#include <lwip/udp.h>
#include <lwip/priv/tcp_priv.h>
_Static_assert(sizeof(netif_output_fn) == sizeof(void *) &&
               sizeof(netif_output_ip6_fn) == sizeof(void *) &&
               sizeof(udp_recv_fn) == sizeof(void *), "native callback address width");
void *vinix_lwip_tcp_lists(void);
void vinix_lwip_set_output4(struct netif *,
        err_t (*)(struct netif *, struct pbuf *, ip4_addr_t *));
void vinix_lwip_set_output6(struct netif *,
        err_t (*)(struct netif *, struct pbuf *, ip6_addr_t *));
void vinix_lwip_udp_recv(struct udp_pcb *,
        void (*)(void *, struct udp_pcb *, struct pbuf *, ip_addr_t *, u16_t), void *);
#endif
