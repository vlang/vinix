#ifndef VINIX_LWIPOPTS_H
#define VINIX_LWIPOPTS_H

/* The kernel serialises access to lwIP and drives it from its idle poller. */
#define NO_SYS 1
#define SYS_LIGHTWEIGHT_PROT 0
#define LWIP_TIMERS 1
#define LWIP_NO_CTYPE_H 1

#define LWIP_IPV4 1
#define LWIP_IPV6 1
#define LWIP_IPV6_AUTOCONFIG 1
#define LWIP_IPV6_SEND_ROUTER_SOLICIT 1
#define LWIP_IPV6_ADDRESS_LIFETIMES 1
#define LWIP_IPV6_MLD 1
#define LWIP_IPV6_NUM_ADDRESSES 6
/* The reassembly helper includes pointers and exceeds the 8-byte wire
 * fragmentation header on both 64-bit targets. */
#define IPV6_FRAG_COPYHEADER 1
#define LWIP_ARP 1
#define LWIP_ETHERNET 1
#define LWIP_ICMP 1
#define LWIP_RAW 1
#define LWIP_UDP 1
#define LWIP_TCP 1
#define LWIP_DHCP 1
#define LWIP_DNS 1
#define LWIP_IGMP 1
#define LWIP_LOOPIF_MULTICAST 1
#define MEMP_NUM_IGMP_GROUP 64
#define MEMP_NUM_MLD6_GROUP 64

#define LWIP_CALLBACK_API 1
#define LWIP_NETCONN 0
#define LWIP_SOCKET 0
#define TCP_LISTEN_BACKLOG 1
#define LWIP_TCP_KEEPALIVE 1
#define LWIP_TCP_SACK_OUT 1
#define LWIP_TCP_TIMESTAMPS 1
#define SO_REUSE 1
#define SO_REUSE_RXTOALL 1
#define IP_SOF_BROADCAST 1

/* A developer workstation can sustain package downloads and several tools at
 * once.  The defaults target tiny MCUs and run out after a handful of packets. */
#define MEM_ALIGNMENT 8
#define MEM_SIZE (4 * 1024 * 1024)
#define MEMP_NUM_PBUF 256
#define MEMP_NUM_RAW_PCB 16
#define MEMP_NUM_UDP_PCB 64
#define MEMP_NUM_TCP_PCB 64
#define MEMP_NUM_TCP_PCB_LISTEN 32
#define MEMP_NUM_TCP_SEG 512
#define PBUF_POOL_SIZE 512
#define PBUF_POOL_BUFSIZE 1700
#define TCP_MSS 1460
#define TCP_WND (16 * TCP_MSS)
#define TCP_SND_BUF (16 * TCP_MSS)
#define TCP_SND_QUEUELEN 128

#define DNS_TABLE_SIZE 16
#define DNS_MAX_SERVERS 3
#define LWIP_DHCP_MAX_DNS_SERVERS DNS_MAX_SERVERS
#define LWIP_DHCP_GET_NTP_SRV 0

#define LWIP_HAVE_LOOPIF 1
#define LWIP_NETIF_LOOPBACK 1
#define LWIP_LOOPBACK_MAX_PBUFS 64
#define LWIP_NETIF_LOOPBACK_MULTITHREADING 0
#define LWIP_NETIF_TX_SINGLE_PBUF 0

/* Initial sequence numbers as RFC 6528 has them, keyed by a secret, rather
 * than lwIP's sum of the ticks since boot: see inet/net_random.v. */
#include <stdint.h>
uint32_t vinix_tcp_isn(uint32_t local_address, uint16_t local_port,
                       uint32_t remote_address, uint16_t remote_port);
uint32_t vinix_tcp_isn6(const uint32_t local_address[4], uint16_t local_port,
                        const uint32_t remote_address[4], uint16_t remote_port);
#define LWIP_HOOK_TCP_ISN(local_ip, local_port, remote_ip, remote_port) \
    (IP_IS_V6(local_ip) ? \
     vinix_tcp_isn6(ip_2_ip6(local_ip)->addr, (local_port), \
                    ip_2_ip6(remote_ip)->addr, (remote_port)) : \
     vinix_tcp_isn(ip4_addr_get_u32(ip_2_ip4(local_ip)), (local_port), \
                   ip4_addr_get_u32(ip_2_ip4(remote_ip)), (remote_port)))

#define LWIP_STATS 0
#define LWIP_DEBUG 0
#define LWIP_CHECKSUM_CTRL_PER_NETIF 0
#define CHECKSUM_GEN_IP 1
#define CHECKSUM_GEN_UDP 1
#define CHECKSUM_GEN_TCP 1
#define CHECKSUM_CHECK_IP 1
#define CHECKSUM_CHECK_UDP 1
#define CHECKSUM_CHECK_TCP 1

#endif
