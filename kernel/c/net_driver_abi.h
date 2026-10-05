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
static inline void *vinix_lwip_tcp_lists(void) { return (void *)tcp_pcb_lists; }
static inline void vinix_lwip_set_output4(struct netif *n,
        err_t (*f)(struct netif *, struct pbuf *, ip4_addr_t *)) {
    n->output = (netif_output_fn)f;
}
static inline void vinix_lwip_set_output6(struct netif *n,
        err_t (*f)(struct netif *, struct pbuf *, ip6_addr_t *)) {
    n->output_ip6 = (netif_output_ip6_fn)f;
}
static inline void vinix_lwip_udp_recv(struct udp_pcb *p,
        void (*f)(void *, struct udp_pcb *, struct pbuf *, ip_addr_t *, u16_t), void *arg) {
    udp_recv(p, (udp_recv_fn)f, arg);
}
#endif
