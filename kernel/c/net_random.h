/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_NET_RANDOM_H
#define VINIX_NET_RANDOM_H

#include <stddef.h>
#include <stdint.h>

/* The ephemeral ports, IANA's dynamic range, as lwIP and OpenBSD's
 * IP_PORTRANGE_HIGH have them. */
#define VINIX_EPHEMERAL_FIRST 49152
#define VINIX_EPHEMERAL_LAST 65535

void vinix_net_random_bytes(void *out, size_t length);
uint32_t vinix_net_random(void);
uint32_t vinix_net_random_uniform(uint32_t upper_bound);

uint16_t vinix_ip_randomid(void);

uint32_t vinix_tcp_isn(uint32_t local_address, uint16_t local_port,
                       uint32_t remote_address, uint16_t remote_port);
uint32_t vinix_tcp_isn_bytes(const void *local, uint16_t local_port,
                            const void *remote, uint16_t remote_port, unsigned length);
uint32_t vinix_tcp_isn_at(uint64_t now_ns, uint32_t local_address, uint16_t local_port,
                          uint32_t remote_address, uint16_t remote_port);

uint32_t vinix_tcp_isn6(const uint32_t local_address[4], uint16_t local_port,
                        const uint32_t remote_address[4], uint16_t remote_port);
uint32_t vinix_tcp_isn6_at(uint64_t now_ns, const uint32_t local_address[4], uint16_t local_port,
                           const uint32_t remote_address[4], uint16_t remote_port);

typedef int (*vinix_port_taken_fn)(uint16_t port, void *context);
uint16_t vinix_pick_port(uint16_t first, uint16_t last, vinix_port_taken_fn taken,
                         void *context);

uint64_t vinix_siphash24(const uint8_t key[16], const void *data, size_t length);

#endif
