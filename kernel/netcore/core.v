// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// GPL-2.0-only; native raw-lwIP socket, endpoint and link ownership.
@[translated]
module netcore

#include "vinix_net.h"
#include "net_random.h"
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
#include "net_driver_abi.h"
#include "stack_slots.h"

fn C.vinix_stack_alloc(size u64) voidptr
fn C.vinix_lwip_set_output4(&C.netif, Netif_output_fn)
fn C.vinix_lwip_set_output6(&C.netif, Netif_output_ip6_fn)

pub struct C.ip_globals {
	//*The interface that accepted the packet for the current callback invocation.

pub mut:
	current_netif &C.netif
	//*The interface that received the packet for the current callback invocation.
	current_input_netif &C.netif
	//*Header of the input packet currently being processed.
	current_ip4_header &C.ip_hdr
	// LWIP_IPV4

	//*Header of the input IPv6 packet currently being processed.
	current_ip6_header &C.ip6_hdr
	// LWIP_IPV6

	//*Total header length of current_ip4/6_header (i.e. after this, the UDP/TCP header starts)
	current_ip_header_tot_len u16
	//*Source IP address of current_header
	current_iphdr_src C.ip_addr
	//*Destination IP address of current_header
	current_iphdr_dest C.ip_addr
}

pub struct C.ip6_hdr {
	//*version / traffic class / flow label

	//*payload length

	//*next header

	//*hop limit

	//*source and destination IP addresses

pub mut:
	_v_tc_fl u32
	_plen    u16
	_nexth   u8
	_hoplim  u8
	src      C.ip6_addr_p
	dest     C.ip6_addr_p
}

pub struct C.ip6_addr_p {
pub mut:
	addr [4]u32
}

fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.printf(&char, ...) i32
fn C.printf_panic(&char, ...) i32

pub struct C.acd {
pub mut:
	next                  &C.acd
	ipaddr                C.ip4_addr
	state                 Acd_state_enum_t
	sent_num              U8_t
	ttw                   U16_t
	lastconflict          U8_t
	num_conflicts         U8_t
	acd_conflict_callback Acd_conflict_callback_t
}

pub enum Acd_callback_enum_t {
	acd_ip_ok
	acd_restart_client
	acd_decline
}

pub type Acd_conflict_callback_t = fn (&C.netif, Acd_callback_enum_t)

pub enum Acd_state_enum_t {
	acd_state_off
	acd_state_probe_wait
	acd_state_probing
	acd_state_announce_wait
	acd_state_announcing
	acd_state_ongoing
	acd_state_passive_ongoing
	acd_state_rate_limit
}

pub type C2vFn_666e2028766f69647074722c207536342920693332 = fn (voidptr, u64) i32

pub enum Err_enum_t {
	err_ok         = 0
	err_mem        = -1
	err_buf        = -2
	err_timeout    = -3
	err_rte        = -4
	err_inprogress = -5
	err_val        = -6
	err_wouldblock = -7
	err_use        = -8
	err_already    = -9
	err_isconn     = -10
	err_conn       = -11
	err_if         = -12
	err_abrt       = -13
	err_rst        = -14
	err_clsd       = -15
	err_arg        = -16
}

pub type Err_t = i8

pub struct C.igmp_group {
pub mut:
	next               &C.igmp_group
	group_address      C.ip4_addr
	last_reporter_flag U8_t
	group_state        U8_t
	timer              U16_t
	use                U8_t
}

pub struct C.ip4_addr_p {
pub mut:
	addr U32_t
}

pub struct C.ip4_addr {
pub mut:
	addr U32_t
}

pub struct C.ip6_addr {
pub mut:
	addr [4]U32_t
	zone U8_t
}

pub struct C.ip_addr {
pub mut:
	u_addr Ip_addr_t_u_addr
	@type  U8_t
}

pub union Ip_addr_t_u_addr {
pub mut:
	ip6 C.ip6_addr
	ip4 C.ip4_addr
}

pub struct C.ip_hdr {
pub mut:
	_v_hl   U8_t
	_tos    U8_t
	_len    U16_t
	_id     U16_t
	_offset U16_t
	_ttl    U8_t
	_proto  U8_t
	_chksum U16_t
	src     C.ip4_addr_p
	dest    C.ip4_addr_p
}

pub struct C.ip_pcb {
pub mut:
	local_ip   C.ip_addr
	remote_ip  C.ip_addr
	netif_idx  U8_t
	so_options U8_t
	tos        U8_t
	ttl        U8_t
}

pub enum Lwip_ip_addr_type {
	ipaddr_type_v4  = 0
	ipaddr_type_v6  = 6
	ipaddr_type_any = 46
}

pub enum Lwip_ipv6_scope_type {
	ip6_unknown   = 0
	ip6_unicast   = 1
	ip6_multicast = 2
}

pub type Mem_size_t = u32

pub struct C.mld_group {
pub mut:
	next               &C.mld_group
	group_address      C.ip6_addr
	last_reporter_flag U8_t
	group_state        U8_t
	timer              U16_t
	use                U8_t
}

pub struct C.netif {
pub mut:
	next    &C.netif
	ip_addr C.ip_addr
	netmask C.ip_addr
	gw      C.ip_addr

	ip6_addr            [6]C.ip_addr
	ip6_addr_state      [6]U8_t
	ip6_addr_valid_life [6]U32_t
	ip6_addr_pref_life  [6]U32_t

	input  Netif_input_fn
	output Netif_output_fn

	linkoutput Netif_linkoutput_fn
	output_ip6 Netif_output_ip6_fn

	state       voidptr
	client_data [4]voidptr

	mtu  U16_t
	mtu6 U16_t

	hwaddr                 [6]U8_t
	hwaddr_len             U8_t
	flags                  U8_t
	name                   [2]char
	num                    U8_t
	ip6_autoconfig_enabled U8_t

	rs_count U8_t

	igmp_mac_filter Netif_igmp_mac_filter_fn

	mld_mac_filter Netif_mld_mac_filter_fn
	acd_list       &C.acd

	loop_first       &C.pbuf
	loop_last        &C.pbuf
	loop_cnt_current U16_t
}

pub type Netif_igmp_mac_filter_fn = fn (&C.netif, &C.ip4_addr, Netif_mac_filter_action) Err_t

pub type Netif_init_fn = fn (&C.netif) Err_t

pub type Netif_input_fn = fn (&C.pbuf, &C.netif) Err_t

pub type Netif_linkoutput_fn = fn (&C.netif, &C.pbuf) Err_t

pub enum Netif_mac_filter_action {
	netif_del_mac_filter = 0
	netif_add_mac_filter = 1
}

pub type Netif_mld_mac_filter_fn = fn (&C.netif, &C.ip6_addr, Netif_mac_filter_action) Err_t

pub type Netif_output_fn = fn (&C.netif, &C.pbuf, &C.ip4_addr) Err_t

pub type Netif_output_ip6_fn = fn (&C.netif, &C.pbuf, &C.ip6_addr) Err_t

pub struct C.pbuf {
pub mut:
	next          &C.pbuf
	payload       voidptr
	tot_len       U16_t
	len           U16_t
	type_internal U8_t
	flags         U8_t
	ref           U8_t
	if_idx        U8_t
}

pub enum Pbuf_layer {
	pbuf_transport = 74
	pbuf_ip        = 54
	pbuf_link      = 14
	pbuf_raw_tx    = 0
}

pub enum Pbuf_type {
	pbuf_ram  = 640
	pbuf_rom  = 1
	pbuf_ref  = 65
	pbuf_pool = 386
}

pub type S16_t = i16

pub type Tcp_accept_fn = fn (voidptr, &C.tcp_pcb, Err_t) Err_t

pub type Tcp_connected_fn = fn (voidptr, &C.tcp_pcb, Err_t) Err_t

pub type Tcp_err_fn = fn (voidptr, Err_t)

pub struct C.tcp_hdr {
pub mut:
	src                U16_t
	dest               U16_t
	seqno              U32_t
	ackno              U32_t
	_hdrlen_rsvd_flags U16_t
	wnd                U16_t
	chksum             U16_t
	urgp               U16_t
}

pub struct C.tcp_pcb {
pub mut:
	local_ip     C.ip_addr
	remote_ip    C.ip_addr
	netif_idx    U8_t
	so_options   U8_t
	tos          U8_t
	ttl          U8_t
	next         &C.tcp_pcb
	callback_arg voidptr
	state        Tcp_state
	prio         U8_t
	local_port   U16_t
	remote_port  U16_t
	flags        Tcpflags_t

	polltmr            U8_t
	pollinterval       U8_t
	last_timer         U8_t
	tmr                U32_t
	rcv_nxt            U32_t
	rcv_wnd            Tcpwnd_size_t
	rcv_ann_wnd        Tcpwnd_size_t
	rcv_ann_right_edge U32_t

	rcv_sacks [4]C.tcp_sack_range

	rtime S16_t
	mss   U16_t

	rttest U32_t
	rtseq  U32_t
	sa     S16_t
	sv     S16_t
	rto    S16_t
	nrtx   U8_t

	dupacks U8_t
	lastack U32_t

	cwnd         Tcpwnd_size_t
	ssthresh     Tcpwnd_size_t
	rto_end      U32_t
	snd_nxt      U32_t
	snd_wl1      U32_t
	snd_wl2      U32_t
	snd_lbb      U32_t
	snd_wnd      Tcpwnd_size_t
	snd_wnd_max  Tcpwnd_size_t
	snd_buf      Tcpwnd_size_t
	snd_queuelen U16_t

	unsent_oversize U16_t
	bytes_acked     Tcpwnd_size_t
	unsent          &C.tcp_seg
	unacked         &C.tcp_seg
	ooseq           &C.tcp_seg

	refused_data &C.pbuf
	listener     &C.tcp_pcb_listen

	sent           Tcp_sent_fn
	recv           Tcp_recv_fn
	connected      Tcp_connected_fn
	poll           Tcp_poll_fn
	errf           Tcp_err_fn
	ts_lastacksent U32_t
	ts_recent      U32_t

	keep_idle  U32_t
	keep_intvl U32_t
	keep_cnt   U32_t

	persist_cnt     U8_t
	persist_backoff U8_t
	persist_probe   U8_t
	keep_cnt_sent   U8_t
}

pub struct C.tcp_pcb_listen {
pub mut:
	local_ip        C.ip_addr
	remote_ip       C.ip_addr
	netif_idx       U8_t
	so_options      U8_t
	tos             U8_t
	ttl             U8_t
	next            &C.tcp_pcb_listen
	callback_arg    voidptr
	state           Tcp_state
	prio            U8_t
	local_port      U16_t
	accept          Tcp_accept_fn
	backlog         U8_t
	accepts_pending U8_t
}

pub type Tcp_poll_fn = fn (voidptr, &C.tcp_pcb) Err_t

pub type Tcp_recv_fn = fn (voidptr, &C.tcp_pcb, &C.pbuf, Err_t) Err_t

pub struct C.tcp_sack_range {
pub mut:
	left  U32_t
	right U32_t
}

pub struct C.tcp_seg {
pub mut:
	next          &C.tcp_seg
	p             &C.pbuf
	len           U16_t
	oversize_left U16_t

	flags U8_t

	tcphdr &C.tcp_hdr
}

pub type Tcp_sent_fn = fn (voidptr, &C.tcp_pcb, U16_t) Err_t

pub enum Tcp_state {
	closed      = 0
	listen      = 1
	syn_sent    = 2
	syn_rcvd    = 3
	established = 4
	fin_wait_1  = 5
	fin_wait_2  = 6
	close_wait  = 7
	closing     = 8
	last_ack    = 9
	time_wait   = 10
}

pub type Tcpflags_t = u16

pub type Tcpwnd_size_t = u16

pub type U16_t = u16

pub type U32_t = u32

pub type U8_t = u8

pub struct C.udp_pcb {
pub mut:
	local_ip    C.ip_addr
	remote_ip   C.ip_addr
	netif_idx   U8_t
	so_options  U8_t
	tos         U8_t
	ttl         U8_t
	next        &C.udp_pcb
	flags       U8_t
	local_port  U16_t
	remote_port U16_t
	mcast_ip4   C.ip4_addr

	mcast_ifindex U8_t
	mcast_ttl     U8_t

	recv     Udp_recv_fn
	recv_arg voidptr
}

pub type Udp_recv_fn = fn (voidptr, &C.udp_pcb, &C.pbuf, &C.ip_addr, U16_t)

pub struct C.vinix_net_endpoint {
pub mut:
	words  [4]u32
	scope  u32
	family u16
	port   u16
}

pub type Vinix_port_taken_fn = fn (u16, voidptr) i32

fn C.dhcp_release_and_stop(netif &C.netif)
fn C.dhcp_start(netif &C.netif) Err_t
fn C.dhcp_supplied_address(netif &C.netif) U8_t
fn C.dns_getserver(numdns U8_t) &C.ip_addr
fn C.etharp_output(netif &C.netif, q &C.pbuf, ipaddr &C.ip4_addr) Err_t
fn C.ethip6_output(netif &C.netif, q &C.pbuf, ip6addr &C.ip6_addr) Err_t
fn C.igmp_init()
fn C.igmp_joingroup_netif(netif &C.netif, groupaddr &C.ip4_addr) Err_t
fn C.igmp_leavegroup_netif(netif &C.netif, groupaddr &C.ip4_addr) Err_t
fn C.igmp_lookfor_group(ifp &C.netif, addr &C.ip4_addr) &C.igmp_group
fn C.igmp_start(netif &C.netif) Err_t
fn C.igmp_stop(netif &C.netif) Err_t
fn C.inet_chksum(dataptr voidptr, len U16_t) U16_t
fn C.ip6_route(src &C.ip6_addr, dest &C.ip6_addr) &C.netif
fn C.lwip_htonl(x U32_t) U32_t
fn C.lwip_htons(x U16_t) U16_t
fn C.lwip_init()
fn C.mem_calloc(count Mem_size_t, size Mem_size_t) voidptr
fn C.mem_free(mem voidptr)
fn C.mem_malloc(size Mem_size_t) voidptr
fn C.mld6_joingroup_netif(netif &C.netif, groupaddr &C.ip6_addr) Err_t
fn C.mld6_leavegroup_netif(netif &C.netif, groupaddr &C.ip6_addr) Err_t
fn C.mld6_lookfor_group(ifp &C.netif, addr &C.ip6_addr) &C.mld_group
fn C.nd6_get_destination_mtu(ip6addr &C.ip6_addr, netif &C.netif) U16_t
fn C.netif_add(netif &C.netif, ipaddr &C.ip4_addr, netmask &C.ip4_addr, gw &C.ip4_addr, state voidptr, init_ Netif_init_fn, input Netif_input_fn) &C.netif
fn C.netif_create_ip6_linklocal_address(netif &C.netif, from_mac_48bit U8_t)
fn C.netif_get_by_index(idx U8_t) &C.netif
fn C.netif_init()
fn C.netif_input(p &C.pbuf, inp &C.netif) Err_t
fn C.netif_loop_output(netif &C.netif, p &C.pbuf) Err_t
fn C.netif_poll_all()
fn C.netif_remove(netif &C.netif)
fn C.netif_set_default(netif &C.netif)
fn C.netif_set_down(netif &C.netif)
fn C.netif_set_link_down(netif &C.netif)
fn C.netif_set_link_up(netif &C.netif)
fn C.netif_set_up(netif &C.netif)
fn C.pbuf_alloc(l i32, length U16_t, @type i32) &C.pbuf
fn C.pbuf_copy_partial(p &C.pbuf, dataptr voidptr, len U16_t, offset U16_t) U16_t
fn C.pbuf_free(p &C.pbuf) U8_t
fn C.pbuf_take(buf &C.pbuf, dataptr voidptr, len U16_t) Err_t
fn C.printf_panic(format &char, ...) i32
fn C.sys_check_timeouts()
fn C.tcp_abort(pcb &C.tcp_pcb)
fn C.tcp_accept(pcb &C.tcp_pcb, accept Tcp_accept_fn)
fn C.tcp_arg(pcb &C.tcp_pcb, arg voidptr)
fn C.tcp_backlog_accepted(pcb &C.tcp_pcb)
fn C.tcp_bind(pcb &C.tcp_pcb, ipaddr &C.ip_addr, port U16_t) Err_t
fn C.tcp_close(pcb &C.tcp_pcb) Err_t
fn C.tcp_connect(pcb &C.tcp_pcb, ipaddr &C.ip_addr, port U16_t, connected Tcp_connected_fn) Err_t
fn C.tcp_err(pcb &C.tcp_pcb, err Tcp_err_fn)
fn C.tcp_input(p &C.pbuf, inp &C.netif)
fn C.tcp_listen_with_backlog_and_err(pcb &C.tcp_pcb, backlog U8_t, err &Err_t) &C.tcp_pcb
fn C.tcp_new_ip_type(@type U8_t) &C.tcp_pcb
fn C.tcp_output(pcb &C.tcp_pcb) Err_t
fn C.tcp_recv(pcb &C.tcp_pcb, recv Tcp_recv_fn)
fn C.tcp_recved(pcb &C.tcp_pcb, len U16_t)
fn C.tcp_sent(pcb &C.tcp_pcb, sent Tcp_sent_fn)
fn C.tcp_shutdown(pcb &C.tcp_pcb, shut_rx i32, shut_tx i32) Err_t
fn C.tcp_write(pcb &C.tcp_pcb, dataptr voidptr, len U16_t, apiflags U8_t) Err_t
fn C.udp_bind(pcb &C.udp_pcb, ipaddr &C.ip_addr, port U16_t) Err_t
fn C.udp_connect(pcb &C.udp_pcb, ipaddr &C.ip_addr, port U16_t) Err_t
fn C.udp_disconnect(pcb &C.udp_pcb)
fn C.udp_new_ip_type(@type U8_t) &C.udp_pcb
fn C.vinix_lwip_udp_recv(pcb &C.udp_pcb, recv Udp_recv_fn, recv_arg voidptr)
fn C.udp_remove(pcb &C.udp_pcb)
fn C.udp_send(pcb &C.udp_pcb, p &C.pbuf) Err_t
fn C.udp_sendto(pcb &C.udp_pcb, p &C.pbuf, dst_ip &C.ip_addr, dst_port U16_t) Err_t
fn C.vinix_apple_wifi_send(arg voidptr, arg_2 u64) i32
fn C.vinix_e1000_send(arg voidptr, arg_2 u64) i32
fn C.vinix_ip_randomid() u16
fn C.vinix_pick_port(first u16, last u16, taken Vinix_port_taken_fn, context voidptr) u16
fn C.vinix_virtio_net_send(arg voidptr, arg_2 u64) i32

@[c_extern]
__global C.netif_list &C.netif

@[c_extern]
__global C.netif_default &C.netif

@[c_extern]
__global C.ip_data C.ip_globals

@[c_extern]
__global C.udp_pcbs &C.udp_pcb

fn C.vinix_lwip_tcp_lists() voidptr

pub const vinix_net_stream = 1
pub const vinix_net_dgram = 2
pub const vinix_net_readable = 1
pub const vinix_net_writable = 2
pub const vinix_net_error = 4
pub const vinix_net_hangup = 8
pub const driver_none = 0
pub const driver_virtio = 1
pub const driver_apple_wifi = 2
pub const driver_e1000 = 3

pub type Driver_send_fn = fn (voidptr, u64) i32

// The transmit function of a driver, or NULL if it is not in this kernel.

pub fn driver_send(driver i32) Driver_send_fn {
	unsafe {
		match driver {
			driver_virtio {
				return C.vinix_virtio_net_send
			}
			driver_apple_wifi {
				return C.vinix_apple_wifi_send
			}
			driver_e1000 {
				return C.vinix_e1000_send
			}
			else {
				return Driver_send_fn(nil)
			}
		}
		return C2vFn_666e2028766f69647074722c207536342920693332(voidptr(0))
	}
}

pub struct Packet {
pub mut:
	next    &Packet
	p       &C.pbuf
	offset  u16
	address C.ip_addr
	port    u16
	charge  u32
}

pub struct Membership {
pub mut:
	group   C.ip_addr
	epoch   u64
	ifindex u8
	used    u8
}

pub struct Vinix_socket {
pub mut:
	family          i32
	v6only          i32
	bound           i32
	hops4           i32
	hops6           i32
	multicast_hops4 i32
	multicast_hops6 i32
	multicast_loop4 i32
	multicast_loop6 i32
	multicast_if4   u32
	multicast_if6   u32
	multicast_addr4 u32
	memberships     [16]Membership
	@type           i32
	protocol        i32
	error           i32
	listening       i32
	connecting      i32
	connected       i32
	peer_closed     i32
	read_shutdown   i32
	write_shutdown  i32
	reuseaddr       i32
	broadcast       i32
	keepalive       i32
	// TCP_NODELAY on a listening socket, for the connections it accepts.
	nodelay        i32
	keep_idle      u32
	keep_interval  u32
	keep_count     u32
	send_limit     u32
	receive_limit  u32
	send_queued    u32
	receive_queued u32
	abort_on_close i32
	tcp            &C.tcp_pcb
	udp            &C.udp_pcb
	// C.tcp_err releases the PCB before user space can query this socket.
	last_local_address  C.ip_addr
	last_local_port     u16
	last_remote_address C.ip_addr
	last_remote_port    u16
	rx_head             &Packet
	rx_tail             &Packet
	accept_head         &Vinix_socket
	accept_tail         &Vinix_socket
	accept_next         &Vinix_socket
}

__global net_physical_netif C.netif

__global net_stack_initialised i32

__global net_link_attached i32

__global net_active_driver i32

__global net_active_mac [6]u8

__global net_clock_ms u32

__global net_clock_anchor_ms u32

__global net_clock_anchored i32

// The ID the fragments after the first of a datagram go out with.

__global net_fragment_id u16

// Static netif storage is reused after detach; memberships use scalar epochs.

__global net_link_epoch = u64(1)

pub fn linux_error(error_ Err_t) i32 {
	unsafe {
		return match i8(error_) {
			0 { 0 }
			-1 { 12 }
			-2 { 105 }
			-3 { 110 }
			-4 { 101 }
			-5 { 115 }
			-6 { 22 }
			-7 { 11 }
			-8 { 98 }
			-9 { 114 }
			-10 { 106 }
			-11 { 107 }
			-12 { 5 }
			-13 { 103 }
			-14 { 104 }
			-15 { 107 }
			-16 { 22 }
			else { 5 }
		}
	}
}

// A failed assertion stops this CPU for good, so say which one it was where it
// can be read: ordinary printf is compiled out of PROD kernels, and the stack
// was all that was left to find it by.
@[export: 'vinix_lwip_assert']
pub fn vinix_lwip_assert(message &char, file &char, line i32) {
	unsafe {
		C.printf_panic(c"lwip: assertion '%s' at %s:%d\n", message, file, line)
		assert_uart(message, file, line)
		for {}
	}
}

@[export: 'sys_now']
pub fn sys_now() u32 {
	unsafe {
		return net_clock_ms
	}
}

@[export: 'vinix_htonl']
pub fn vinix_htonl(value u32) u32 {
	unsafe {
		return C.lwip_htonl(value)
	}
}

@[export: 'vinix_htons']
pub fn vinix_htons(value u16) u16 {
	unsafe {
		return C.lwip_htons(value)
	}
}

pub fn free_packet(packet &Packet) {
	unsafe {
		if packet.p {
			C.pbuf_free(packet.p)
		}
		C.mem_free(voidptr(packet))
	}
}

pub fn free_packets(socket &Vinix_socket) {
	unsafe {
		for socket.rx_head {
			packet := socket.rx_head
			socket.rx_head = packet.next
			free_packet(packet)
		}
		socket.rx_tail = nil
		socket.receive_queued = u32(0)
	}
}

pub fn queue_packet(socket &Vinix_socket, p &C.pbuf, address &C.ip_addr, port u16, terminal i32) i32 {
	unsafe {
		packet := &Packet(0)
		charge := u32(u64(p.tot_len) + sizeof(Packet) + u64(64))
		if (charge > socket.receive_limit || socket.receive_queued > socket.receive_limit - charge) && !(socket.@type == vinix_net_stream && (socket.receive_queued == u32(0) || terminal)) {
			return 0
		}
		// TCP may coalesce an entire advertised window into one pbuf chain.
		//     *Permit that one chain in an empty queue even after SO_RCVBUF shrinks;
		//     *rejecting it forever would deadlock the stream. Further chains still
		//     *apply backpressure. Also keep the final TCP chain: a PCB already in
		//     *CLOSING or TIME-WAIT will not retry refused data before its timer frees
		//     *it. That chain is still bounded by the advertised receive window.
		//     *UDP drops datagrams that exceed its budget.

		packet = &Packet(C.mem_malloc(Mem_size_t(sizeof(Packet))))
		if usize(packet) == 0 {
			return 0
		}
		C.memset(voidptr(packet), 0, sizeof(Packet))
		packet.p = p
		if address {
			for {
				for {
					packet.address.@type = address.@type
					// while()
					break
				}
				if i32(address.@type) == Lwip_ip_addr_type.ipaddr_type_v6 {
					for {
						(&packet.address.u_addr.ip6).addr[0] = (&address.u_addr.ip6).addr[0]
						(&packet.address.u_addr.ip6).addr[1] = (&address.u_addr.ip6).addr[1]
						(&packet.address.u_addr.ip6).addr[2] = (&address.u_addr.ip6).addr[2]
						(&packet.address.u_addr.ip6).addr[3] = (&address.u_addr.ip6).addr[3]
						(*(&packet.address.u_addr.ip6)).zone = (*(&address.u_addr.ip6)).zone
						// while()
						break
					}
				} else {
					(&packet.address.u_addr.ip4).addr = (&address.u_addr.ip4).addr
					for {
						packet.address.u_addr.ip6.addr[3] = U32_t(0)
						packet.address.u_addr.ip6.addr[2] = U32_t(0)
						packet.address.u_addr.ip6.addr[1] = U32_t(0)
						packet.address.u_addr.ip6.zone = U8_t(0)
						// while()
						break
					}
				}
				// while()
				break
			}
		}
		packet.port = port
		packet.charge = charge
		if socket.rx_tail {
			socket.rx_tail.next = packet
		} else {
			socket.rx_head = packet
		}
		socket.rx_tail = packet
		socket.receive_queued += charge
		return 1
	}
}

// lwIP owns a successfully closed PCB, including one still on TIME-WAIT.
// *Keep only endpoint values after that transfer: its timers may free the PCB
// *without an error callback. The caller holds the kernel's network lock.
//

pub fn detach_tcp(socket &Vinix_socket, pcb &C.tcp_pcb) {
	unsafe {
		for {
			for {
				socket.last_local_address.@type = pcb.local_ip.@type
				// while()
				break
			}
			if i32(pcb.local_ip.@type) == Lwip_ip_addr_type.ipaddr_type_v6 {
				for {
					(&socket.last_local_address.u_addr.ip6).addr[0] = (&pcb.local_ip.u_addr.ip6).addr[0]
					(&socket.last_local_address.u_addr.ip6).addr[1] = (&pcb.local_ip.u_addr.ip6).addr[1]
					(&socket.last_local_address.u_addr.ip6).addr[2] = (&pcb.local_ip.u_addr.ip6).addr[2]
					(&socket.last_local_address.u_addr.ip6).addr[3] = (&pcb.local_ip.u_addr.ip6).addr[3]
					(*(&socket.last_local_address.u_addr.ip6)).zone = (*(&pcb.local_ip.u_addr.ip6)).zone
					// while()
					break
				}
			} else {
				(&socket.last_local_address.u_addr.ip4).addr = (&pcb.local_ip.u_addr.ip4).addr
				for {
					socket.last_local_address.u_addr.ip6.addr[3] = U32_t(0)
					socket.last_local_address.u_addr.ip6.addr[2] = U32_t(0)
					socket.last_local_address.u_addr.ip6.addr[1] = U32_t(0)
					socket.last_local_address.u_addr.ip6.zone = U8_t(0)
					// while()
					break
				}
			}
			// while()
			break
		}
		socket.last_local_port = C.lwip_htons(pcb.local_port)
		for {
			for {
				socket.last_remote_address.@type = pcb.remote_ip.@type
				// while()
				break
			}
			if i32(pcb.remote_ip.@type) == Lwip_ip_addr_type.ipaddr_type_v6 {
				for {
					(&socket.last_remote_address.u_addr.ip6).addr[0] = (&pcb.remote_ip.u_addr.ip6).addr[0]
					(&socket.last_remote_address.u_addr.ip6).addr[1] = (&pcb.remote_ip.u_addr.ip6).addr[1]
					(&socket.last_remote_address.u_addr.ip6).addr[2] = (&pcb.remote_ip.u_addr.ip6).addr[2]
					(&socket.last_remote_address.u_addr.ip6).addr[3] = (&pcb.remote_ip.u_addr.ip6).addr[3]
					(*(&socket.last_remote_address.u_addr.ip6)).zone = (*(&pcb.remote_ip.u_addr.ip6)).zone
					// while()
					break
				}
			} else {
				(&socket.last_remote_address.u_addr.ip4).addr = (&pcb.remote_ip.u_addr.ip4).addr
				for {
					socket.last_remote_address.u_addr.ip6.addr[3] = U32_t(0)
					socket.last_remote_address.u_addr.ip6.addr[2] = U32_t(0)
					socket.last_remote_address.u_addr.ip6.addr[1] = U32_t(0)
					socket.last_remote_address.u_addr.ip6.zone = U8_t(0)
					// while()
					break
				}
			}
			// while()
			break
		}
		socket.last_remote_port = C.lwip_htons(pcb.remote_port)
		C.tcp_arg(pcb, voidptr((voidptr(0))))
		C.tcp_recv(pcb, (voidptr(0)))
		C.tcp_sent(pcb, (voidptr(0)))
		C.tcp_err(pcb, (voidptr(0)))
		socket.tcp = nil
		socket.connecting = 0
	}
}

@[export: 'vinix_net_core_tcp_received']
pub fn tcp_received(argument voidptr, pcb &C.tcp_pcb, p &C.pbuf, error_ Err_t) Err_t {
	unsafe {
		socket := &Vinix_socket(argument)

		if usize(socket) == 0 {
			if p {
				C.pbuf_free(p)
			}
			return Err_t(Err_enum_t.err_ok)
		}
		if i32(error_) != Err_enum_t.err_ok {
			socket.error = linux_error(error_)
		}
		if usize(p) == 0 {
			socket.peer_closed = 1
			if u32(pcb.state) == u32(Tcp_state.time_wait) || u32(pcb.state) == u32(Tcp_state.closing) {
				detach_tcp(socket, pcb)
			}
			return Err_t(Err_enum_t.err_ok)
		}
		if socket.read_shutdown {
			C.tcp_recved(pcb, p.tot_len)
			C.pbuf_free(p)
			return Err_t(Err_enum_t.err_ok)
		}
		terminal := i32(u32(pcb.state) == u32(Tcp_state.time_wait) || u32(pcb.state) == u32(Tcp_state.closing))
		if !queue_packet(socket, p, &pcb.remote_ip, pcb.remote_port, terminal) {
			if terminal {
				// No metadata memory remains for the final payload. Report the
				//             *failure instead of retaining a PCB that will expire silently.
				//             *This callback owns p only when accepting it or returning ABRT;
				//             *C.tcp_input will not free it again after ERR_ABRT.
				//

				detach_tcp(socket, pcb)
				socket.connected = 0
				socket.peer_closed = 1
				socket.error = 12
				// ENOMEM

				C.pbuf_free(p)
				C.tcp_abort(pcb)
				return Err_t(Err_enum_t.err_abrt)
			}
			// Keeping lwIP's ownership by refusing the packet applies TCP
			//         *backpressure instead of silently losing stream bytes.

			return Err_t(Err_enum_t.err_mem)
		}
		return Err_t(Err_enum_t.err_ok)
	}
}

@[export: 'vinix_net_core_tcp_sent_data']
pub fn tcp_sent_data(argument voidptr, pcb &C.tcp_pcb, length u16) Err_t {
	unsafe {
		socket := &Vinix_socket(argument)

		if socket {
			socket.send_queued = if u32(length) >= socket.send_queued {
				u32(0)
			} else {
				socket.send_queued - u32(length)
			}
		}
		return Err_t(Err_enum_t.err_ok)
	}
}

pub fn tcp_connected(argument voidptr, pcb &C.tcp_pcb, error_ Err_t) Err_t {
	unsafe {
		socket := &Vinix_socket(argument)

		if usize(socket) == 0 {
			return Err_t(Err_enum_t.err_ok)
		}
		socket.connecting = 0
		if i32(error_) == Err_enum_t.err_ok {
			socket.connected = 1
		} else {
			socket.error = linux_error(error_)
		}
		return Err_t(Err_enum_t.err_ok)
	}
}

pub fn tcp_failed(argument voidptr, error_ Err_t) {
	unsafe {
		socket := &Vinix_socket(argument)
		if usize(socket) == 0 {
			return
		}
		socket.tcp = nil
		socket.connecting = 0
		socket.connected = 0
		socket.peer_closed = 1
		socket.error = linux_error(error_)
	}
}

pub fn install_tcp_callbacks(socket &Vinix_socket) {
	unsafe {
		C.tcp_arg(socket.tcp, voidptr(socket))
		C.tcp_recv(socket.tcp, tcp_received)
		C.tcp_sent(socket.tcp, fn (__c2v_cb_arg_0 voidptr, __c2v_cb_arg_1 &C.tcp_pcb, __c2v_cb_arg_2 U16_t) Err_t {
			return tcp_sent_data(__c2v_cb_arg_0, __c2v_cb_arg_1, u16(__c2v_cb_arg_2))
		})
		C.tcp_err(socket.tcp, tcp_failed)
	}
}

@[export: 'vinix_net_core_accept_callback']
pub fn accept_callback(argument voidptr, pcb &C.tcp_pcb, error_ Err_t) Err_t {
	unsafe {
		listener := &Vinix_socket(argument)
		child := &Vinix_socket(0)
		if (usize(listener) == 0) || i32(error_) != Err_enum_t.err_ok {
			if pcb {
				C.tcp_abort(pcb)
			}
			return Err_t(Err_enum_t.err_abrt)
		}
		child = &Vinix_socket(C.mem_calloc(Mem_size_t(1), Mem_size_t(sizeof(Vinix_socket))))
		if usize(child) == 0 {
			C.tcp_abort(pcb)
			return Err_t(Err_enum_t.err_abrt)
		}
		child.family = listener.family
		child.v6only = listener.v6only
		child.bound = 1
		child.hops4 = listener.hops4
		child.hops6 = listener.hops6
		pcb.ttl = u8((if (usize((&pcb.remote_ip)) != usize((voidptr(0)))) && (i32((*(&pcb.remote_ip)).@type) == Lwip_ip_addr_type.ipaddr_type_v6) {
			child.hops6
		} else {
			child.hops4
		}))
		child.@type = vinix_net_stream
		child.protocol = 6
		child.connected = 1
		child.tcp = pcb
		child.reuseaddr = (u32(pcb.so_options) & 4) != u32(0)
		child.keepalive = listener.keepalive
		if child.keepalive {
			pcb.so_options = U8_t((u32(pcb.so_options) | 8))
		} else {
			pcb.so_options = U8_t((u32(pcb.so_options) & ~8))
		}
		child.keep_idle = listener.keep_idle
		child.keep_interval = listener.keep_interval
		child.keep_count = listener.keep_count
		pcb.keep_idle = child.keep_idle
		pcb.keep_intvl = child.keep_interval
		pcb.keep_cnt = child.keep_count
		child.send_limit = listener.send_limit
		child.receive_limit = listener.receive_limit
		child.abort_on_close = listener.abort_on_close
		// A connection takes TCP_NODELAY from the socket it was accepted on.

		if listener.nodelay {
			for {
				pcb.flags = Tcpflags_t((u32(pcb.flags) | 64))
				// while()
				break
			}
		}
		install_tcp_callbacks(child)
		if listener.accept_tail {
			listener.accept_tail.accept_next = child
		} else {
			listener.accept_head = child
		}
		listener.accept_tail = child
		return Err_t(Err_enum_t.err_ok)
	}
}

@[export: 'vinix_net_core_udp_received']
pub fn udp_received(argument voidptr, pcb &C.udp_pcb, p &C.pbuf, address &C.ip_addr, port u16) {
	unsafe {
		socket := &Vinix_socket(argument)

		mut __c2v_condition_0 := false
		mut __c2v_condition_1 := false
		__c2v_condition_1 = (usize(socket) == 0)
		__c2v_condition_0 = __c2v_condition_1
		if !__c2v_condition_0 {
			mut __c2v_condition_2 := false
			__c2v_condition_2 = socket.read_shutdown
			__c2v_condition_0 = __c2v_condition_2
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_3 := false
			__c2v_condition_3 = ((if (usize((&C.ip_data.current_iphdr_dest)) != usize((voidptr(0)))) && (i32((*(&C.ip_data.current_iphdr_dest)).@type) == Lwip_ip_addr_type.ipaddr_type_v6) {
				((u64(C.ip_data.current_iphdr_dest.u_addr.ip6.addr[0]) & (((u64(4278190080) & u64(U32_t(255))) << 24) | ((u64(4278190080) & u64(U32_t(65280))) << 8) | ((u64(4278190080) & u64(U32_t(16711680))) >> 8) | ((u64(4278190080) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4278190080) & u64(U32_t(255))) << 24) | ((u64(4278190080) & u64(U32_t(65280))) << 8) | ((u64(4278190080) & u64(U32_t(16711680))) >> 8) | ((u64(4278190080) & u64(U32_t(u64(4278190080)))) >> 24)))
			} else {
				((u64(C.ip_data.current_iphdr_dest.u_addr.ip4.addr) & (((u64(4026531840) & u64(U32_t(255))) << 24) | ((u64(4026531840) & u64(U32_t(65280))) << 8) | ((u64(4026531840) & u64(U32_t(16711680))) >> 8) | ((u64(4026531840) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(3758096384) & u64(U32_t(255))) << 24) | ((u64(3758096384) & u64(U32_t(65280))) << 8) | ((u64(3758096384) & u64(U32_t(16711680))) >> 8) | ((u64(3758096384) & u64(U32_t(u64(4278190080)))) >> 24)))
			}) && !has_membership(socket, (&C.ip_data.current_iphdr_dest), C.ip_data.current_input_netif))
			__c2v_condition_0 = __c2v_condition_3
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_4 := false
			__c2v_condition_4 = !queue_packet(socket, p, address, port, 0)
			__c2v_condition_0 = __c2v_condition_4
		}
		if __c2v_condition_0 {
			C.pbuf_free(p)
		}
	}
}

// IP output already enqueues the optional multicast loop copy. The native
// *loopif output enqueues again, which delivers duplicates and ignores LOOP=0.

pub fn loop_output4(interface_ &C.netif, p &C.pbuf, destination &C.ip4_addr) Err_t {
	unsafe {
		return Err_t(if (u64(destination.addr) & (((u64(4026531840) & u64(U32_t(255))) << 24) | ((u64(4026531840) & u64(U32_t(65280))) << 8) | ((u64(4026531840) & u64(U32_t(16711680))) >> 8) | ((u64(4026531840) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(3758096384) & u64(U32_t(255))) << 24) | ((u64(3758096384) & u64(U32_t(65280))) << 8) | ((u64(3758096384) & u64(U32_t(16711680))) >> 8) | ((u64(3758096384) & u64(U32_t(u64(4278190080)))) >> 24)) {
			Err_enum_t.err_ok
		} else {
			i32(C.netif_loop_output(interface_, p))
		})
	}
}

pub fn loop_output6(interface_ &C.netif, p &C.pbuf, destination &C.ip6_addr) Err_t {
	unsafe {
		return Err_t(if (u64(destination.addr[0]) & (((u64(4278190080) & u64(U32_t(255))) << 24) | ((u64(4278190080) & u64(U32_t(65280))) << 8) | ((u64(4278190080) & u64(U32_t(16711680))) >> 8) | ((u64(4278190080) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4278190080) & u64(U32_t(255))) << 24) | ((u64(4278190080) & u64(U32_t(65280))) << 8) | ((u64(4278190080) & u64(U32_t(16711680))) >> 8) | ((u64(4278190080) & u64(U32_t(u64(4278190080)))) >> 24)) {
			Err_enum_t.err_ok
		} else {
			i32(C.netif_loop_output(interface_, p))
		})
	}
}

@[export: 'vinix_net_init']
pub fn vinix_net_init() {
	unsafe {
		if net_stack_initialised {
			return
		}
		C.lwip_init()
		// lwIP tags its loop interface for IGMP but leaves MLD to Ethernet
		//     *ports. Local IPv6 multicast still needs the same managed group state.

		interface_ := &C.netif(0)
		for interface_ = C.netif_list; usize(interface_) != usize((voidptr(0))); interface_ = interface_.next {
			if ((&C.ip4_addr((&interface_.ip_addr.u_addr.ip4))).addr & (((u32(4278190080) & U32_t(255)) << 24) | ((u32(4278190080) & U32_t(65280)) << 8) | ((u32(4278190080) & U32_t(16711680)) >> 8) | ((u32(4278190080) & U32_t(u64(4278190080))) >> 24))) == (((((U32_t(127)) << 24) & U32_t(255)) << 24) | ((((U32_t(127)) << 24) & U32_t(65280)) << 8) | ((((U32_t(127)) << 24) & U32_t(16711680)) >> 8) | ((((U32_t(127)) << 24) & U32_t(u64(4278190080))) >> 24)) {
				// C.netif_init starts loop IGMP before C.igmp_init assigns its
				//             *all-hosts address. Recreate this boot-only native group before
				//             *sockets can borrow it, now that the protocol is initialized.

				C.igmp_stop(interface_)
				if i32(C.igmp_start(interface_)) != Err_enum_t.err_ok {
					vinix_lwip_assert(c'loop IGMP initialization', c'kernel/netcore/core.v', 1213)
				}
				interface_.flags |= 64
				C.vinix_lwip_set_output4(interface_, loop_output4)
				C.vinix_lwip_set_output6(interface_, loop_output6)
			}
		}
		net_stack_initialised = 1
		C.printf(c'net: lwIP 2.2.1, IPv4/IPv6 TCP/UDP loopback ready\n')
	}
}

pub fn driver_output(frame voidptr, length usize) i32 {
	unsafe {
		send := driver_send(net_active_driver)
		return if send { send(voidptr(frame), u64(length)) } else { -1 }
	}
}

pub fn link_output(netif &C.netif, p &C.pbuf) Err_t {
	unsafe {
		frame := [1522]u8{}
		copied := u16(0)

		if u64(p.tot_len) > sizeof([1522]u8) {
			return Err_t(Err_enum_t.err_buf)
		}
		copied = C.pbuf_copy_partial(p, voidptr(&frame[0]), p.tot_len, U16_t(0))
		if i32(copied) != i32(p.tot_len) || driver_output(voidptr(&frame[0]), usize(copied)) < 0 {
			return Err_t(Err_enum_t.err_if)
		}
		return Err_t(Err_enum_t.err_ok)
	}
}

// Every datagram leaves the machine with an ID from ip_randomid() in place of
// *lwIP's, which counts up by one: anyone who saw two of them knew how much the
// *machine had sent in between. The fragments of a datagram share its ID, and
// *ip4_frag() sends them in order, one after another, the first at offset 0.

pub fn output_ipv4(netif &C.netif, p &C.pbuf, destination &C.ip4_addr) Err_t {
	unsafe {
		header := &C.ip_hdr(p.payload)
		header_length := u16(0)
		if i32(p.len) >= 20 && (i32(header._v_hl) >> 4) == 4 {
			header_length = u16((U8_t(((i32(header._v_hl) & 15) * 4))))
			if i32(header_length) >= 20 && i32(p.len) >= i32(header_length) {
				if (u32(C.lwip_htons(header._offset)) & 8191) == u32(0) {
					net_fragment_id = C.vinix_ip_randomid()
				}
				header._id = net_fragment_id
				header._chksum = U16_t(0)
				header._chksum = C.inet_chksum(voidptr(header), header_length)
			}
		}
		return C.etharp_output(netif, p, destination)
	}
}

pub fn physical_init(netif &C.netif) Err_t {
	unsafe {
		netif.name[0] = i8(`e`)
		netif.name[1] = i8(`n`)
		netif.hwaddr_len = U8_t(6)
		C.memcpy(netif.hwaddr, voidptr(&net_active_mac[0]), usize(6))
		netif.mtu = U16_t(1500)
		netif.flags = U8_t(2 | 8 | 16 | 32 | 64)
		C.vinix_lwip_set_output4(netif, output_ipv4)
		netif.output_ip6 = C.ethip6_output
		netif.flags |= 64
		netif.linkoutput = link_output
		return Err_t(Err_enum_t.err_ok)
	}
}

@[export: 'vinix_net_attach']
pub fn vinix_net_attach(mac &u8, driver i32) i32 {
	unsafe {
		zero := C.ip4_addr{}
		if !net_stack_initialised {
			vinix_net_init()
		}
		if is_null(driver_send(driver)) {
			return -22
		}
		if net_link_attached {
			vinix_net_detach()
		}
		net_active_driver = driver
		C.memcpy(voidptr(&net_active_mac[0]), voidptr(mac), usize(6))
		zero.addr = U32_t(0)
		C.memset(voidptr(&net_physical_netif), 0, sizeof(net_physical_netif))
		if is_null(C.netif_add(&net_physical_netif, &zero, &zero, &zero, voidptr((voidptr(0))), physical_init, C.netif_input)) {
			net_active_driver = driver_none
			return -12
		}
		C.netif_create_ip6_linklocal_address(&net_physical_netif, U8_t(1))
		net_link_epoch++
		C.netif_set_default(&net_physical_netif)
		C.netif_create_ip6_linklocal_address(&net_physical_netif, U8_t(1))
		for {
			if true {
				net_physical_netif.ip6_autoconfig_enabled = U8_t(1)
			}
			// while()
			break
		}
		C.netif_set_link_up(&net_physical_netif)
		C.netif_set_up(&net_physical_netif)
		net_link_attached = 1
		if i32(C.dhcp_start(&net_physical_netif)) != Err_enum_t.err_ok {
			vinix_net_detach()
			return -12
		}
		C.printf(c'net: attached %c%c%u, DHCP started\n', i32(net_physical_netif.name[0]), i32(net_physical_netif.name[1]), i32(net_physical_netif.num))
		return 0
	}
}

@[export: 'vinix_net_detach']
pub fn vinix_net_detach() {
	unsafe {
		if !net_link_attached {
			return
		}
		C.dhcp_release_and_stop(&net_physical_netif)
		C.netif_set_down(&net_physical_netif)
		C.netif_set_link_down(&net_physical_netif)
		C.netif_remove(&net_physical_netif)
		net_link_attached = 0
		net_active_driver = driver_none
	}
}

@[export: 'vinix_net_input']
pub fn vinix_net_input(frame voidptr, length usize) i32 {
	unsafe {
		p := &C.pbuf(0)
		error_ := Err_t(0)
		if !net_link_attached || (usize(frame) == 0) || length < usize(14) || length > usize(65535) {
			return -22
		}
		p = C.pbuf_alloc(i32(Pbuf_layer.pbuf_raw_tx), u16(length), i32(Pbuf_type.pbuf_pool))
		if usize(p) == 0 {
			return -12
		}
		if i32(C.pbuf_take(p, voidptr(frame), u16(length))) != Err_enum_t.err_ok {
			C.pbuf_free(p)
			return -12
		}
		error_ = net_physical_netif.input(p, &net_physical_netif)
		if i32(error_) != Err_enum_t.err_ok {
			C.pbuf_free(p)
			return -linux_error(error_)
		}
		return 0
	}
}

@[export: 'vinix_net_poll']
pub fn vinix_net_poll(now_ms u32) {
	unsafe {
		if !net_stack_initialised {
			return
		}
		// lwIP wants milliseconds that start near zero and only go up. Vinix's
		//     *monotonic clock is seeded from the platform's idea of elapsed time and is
		//     *already a few weeks along at boot, so feeding it in raw put every timer
		//     *C.lwip_init() had scheduled -- at a sys_now() of 0 -- more than 2^31 ms in
		//     *the past, which its wraparound-safe comparison reads as far in the
		//     *future. No cyclic timer ever fired: DHCP sent its DISCOVER and REQUEST
		//     *from the receive path, then sat in CHECKING for ever because the address
		//     *conflict check is timer-driven, and the machine never got a lease.
		//     *     *Anchor the clock at the first sample instead.

		if !net_clock_anchored {
			net_clock_anchor_ms = now_ms
			net_clock_anchored = 1
		}
		net_clock_ms = now_ms - net_clock_anchor_ms
		C.sys_check_timeouts()
		C.netif_poll_all()
	}
}

@[export: 'vinix_net_config']
pub fn vinix_net_config(address &u32, netmask &u32, gateway &u32, dns &u32) i32 {
	unsafe {
		index := u32(0)
		if !net_link_attached || !C.dhcp_supplied_address(&net_physical_netif) {
			return 0
		}
		if address {
			*address = (&C.ip4_addr((&net_physical_netif.ip_addr.u_addr.ip4))).addr
		}
		if netmask {
			*netmask = (&C.ip4_addr((&net_physical_netif.netmask.u_addr.ip4))).addr
		}
		if gateway {
			*gateway = (&C.ip4_addr((&net_physical_netif.gw.u_addr.ip4))).addr
		}
		if dns {
			for index = u32(0); index < u32(3); index++ {
				server := &C.ip_addr(C.dns_getserver(u8(index)))
				dns[index] = if (usize(server) == usize((voidptr(0)))) || (i32(server.@type) == Lwip_ip_addr_type.ipaddr_type_v4) {
					server.u_addr.ip4.addr
				} else {
					U32_t(0)
				}
			}
		}
		return 1
	}
}

@[export: 'vinix_net_link']
pub fn vinix_net_link(mac &u8, mtu &u32) i32 {
	unsafe {
		if !net_link_attached {
			return 0
		}
		C.memcpy(voidptr(mac), net_physical_netif.hwaddr, usize(6))
		*mtu = u32(net_physical_netif.mtu)
		return 1
	}
}

@[export: 'vinix_socket_new']
pub fn vinix_socket_new(@type i32, protocol i32) &Vinix_socket {
	unsafe {
		socket := &Vinix_socket(0)
		if !net_stack_initialised {
			vinix_net_init()
		}
		if (@type == vinix_net_stream && protocol != 0 && protocol != 6) || (@type == vinix_net_dgram && protocol != 0 && protocol != 17) {
			return nil
		}
		socket = &Vinix_socket(C.mem_calloc(Mem_size_t(1), Mem_size_t(sizeof(Vinix_socket))))
		if usize(socket) == 0 {
			return nil
		}
		socket.family = 2
		socket.hops6 = 64
		socket.hops4 = socket.hops6
		socket.multicast_hops6 = 1
		socket.multicast_hops4 = socket.multicast_hops6
		socket.multicast_loop6 = 1
		socket.multicast_loop4 = socket.multicast_loop6
		socket.@type = @type
		socket.protocol = if protocol {
			protocol
		} else {
			(if @type == vinix_net_stream { 6 } else { 17 })
		}
		socket.send_limit = u32(if @type == vinix_net_stream { (16 * 1460) } else { 212992 })
		socket.receive_limit = u32(if @type == vinix_net_stream {
			(16 * 1460) + 4096
		} else {
			212992
		})
		socket.keep_idle = u32(7200000)
		socket.keep_interval = u32(75000)
		socket.keep_count = 9
		if @type == vinix_net_stream {
			socket.tcp = C.tcp_new_ip_type(U8_t(Lwip_ip_addr_type.ipaddr_type_v4))
			if usize(socket.tcp) == 0 {
				C.mem_free(voidptr(socket))
				return nil
			}
			install_tcp_callbacks(socket)
		} else if @type == vinix_net_dgram {
			socket.udp = C.udp_new_ip_type(U8_t(Lwip_ip_addr_type.ipaddr_type_v4))
			if usize(socket.udp) == 0 {
				C.mem_free(voidptr(socket))
				return nil
			}
			socket.udp.flags |= 8
			C.vinix_lwip_udp_recv(socket.udp, fn (__c2v_cb_arg_0 voidptr, __c2v_cb_arg_1 &C.udp_pcb, __c2v_cb_arg_2 &C.pbuf, __c2v_cb_arg_3 &C.ip_addr, __c2v_cb_arg_4 U16_t) {
				udp_received(__c2v_cb_arg_0, __c2v_cb_arg_1, __c2v_cb_arg_2, __c2v_cb_arg_3, u16(__c2v_cb_arg_4))
			}, voidptr(socket))
		} else {
			C.mem_free(voidptr(socket))
			return nil
		}
		return socket
	}
}

@[export: 'vinix_socket_free']
pub fn vinix_socket_free(socket &Vinix_socket) {
	unsafe {
		if usize(socket) == 0 {
			return
		}
		release_memberships(socket)
		free_packets(socket)
		for socket.accept_head {
			child := socket.accept_head
			socket.accept_head = child.accept_next
			child.accept_next = nil
			vinix_socket_free(child)
		}
		if !(usize(socket.tcp) == 0) && u32(socket.tcp.state) == u32(Tcp_state.listen) {
			// A listening pcb is lwIP's smaller tcp_pcb_listen. It has no data
			// callbacks, and lwIP asserts if asked to clear them. Closing one
			// cannot fail.
			C.tcp_arg(socket.tcp, voidptr((voidptr(0))))
			C.tcp_accept(socket.tcp, (voidptr(0)))
			C.tcp_close(socket.tcp)
			socket.tcp = nil
		} else if socket.tcp {
			C.tcp_arg(socket.tcp, voidptr((voidptr(0))))
			C.tcp_recv(socket.tcp, (voidptr(0)))
			C.tcp_sent(socket.tcp, (voidptr(0)))
			C.tcp_err(socket.tcp, (voidptr(0)))
			if socket.abort_on_close || i32(C.tcp_close(socket.tcp)) != Err_enum_t.err_ok {
				C.tcp_abort(socket.tcp)
			}
			socket.tcp = nil
		}
		if socket.udp {
			C.vinix_lwip_udp_recv(socket.udp, (voidptr(0)), voidptr((voidptr(0))))
			C.udp_remove(socket.udp)
			socket.udp = nil
		}
		C.mem_free(voidptr(socket))
	}
}

pub fn ipv4(address u32) C.ip_addr {
	unsafe {
		result := C.ip_addr{}
		for {
			result.@type = U8_t(Lwip_ip_addr_type.ipaddr_type_v4)
			// while()
			break
		}
		result.u_addr.ip4.addr = address
		return result
	}
}

// The IPv4 ABI remains available to procfs and existing consumers.

pub fn tcp_port_taken(port u16, context voidptr) i32 {
	unsafe {
		i := i32(0)
		pcb := &C.tcp_pcb(0)

		for i = 0; i < 4; i++ {
			for pcb = *(&&&C.tcp_pcb(C.vinix_lwip_tcp_lists()))[i]; usize(pcb) != usize((voidptr(0))); pcb = pcb.next {
				if i32(pcb.local_port) == i32(port) {
					return 1
				}
			}
		}
		return 0
	}
}

pub fn udp_port_taken(port u16, context voidptr) i32 {
	unsafe {
		pcb := &C.udp_pcb(0)

		for pcb = C.udp_pcbs; usize(pcb) != usize((voidptr(0))); pcb = pcb.next {
			if i32(pcb.local_port) == i32(port) {
				return 1
			}
		}
		return 0
	}
}

// Bind an unbound socket to an ephemeral port picked at random, where lwIP
// *would have taken the one after the last it gave out. Every way a socket can
// *be given a port without naming one comes through here: bind() to port 0,
// *and connect(), listen() and sendto() on a socket not yet bound. 99 is
// *EADDRNOTAVAIL, Linux's answer when the range is used up.

pub fn bind_ephemeral(socket &Vinix_socket, address &C.ip_addr) i32 {
	unsafe {
		stream := i32(socket.@type == vinix_net_stream)
		port := C.vinix_pick_port(u16(49152), u16(65535), if stream {
			tcp_port_taken
		} else {
			udp_port_taken
		}, voidptr((voidptr(0))))
		if !port {
			return 99
		}
		return linux_error(Err_t(if stream {
			i32(C.tcp_bind(socket.tcp, address, port))
		} else {
			i32(C.udp_bind(socket.udp, address, port))
		}))
	}
}

pub fn bind_ip(socket &Vinix_socket, address &C.ip_addr, port u16) i32 {
	unsafe {
		ip := C.ip_addr{}
		error_ := Err_t(0)
		if usize(socket) == 0 {
			return 88
		}
		if socket.bound {
			return 22
		}
		for {
			for {
				ip.@type = address.@type
				// while()
				break
			}
			if i32(address.@type) == Lwip_ip_addr_type.ipaddr_type_v6 {
				for {
					(&ip.u_addr.ip6).addr[0] = (&address.u_addr.ip6).addr[0]
					(&ip.u_addr.ip6).addr[1] = (&address.u_addr.ip6).addr[1]
					(&ip.u_addr.ip6).addr[2] = (&address.u_addr.ip6).addr[2]
					(&ip.u_addr.ip6).addr[3] = (&address.u_addr.ip6).addr[3]
					(*(&ip.u_addr.ip6)).zone = (*(&address.u_addr.ip6)).zone
					// while()
					break
				}
			} else {
				(&ip.u_addr.ip4).addr = (&address.u_addr.ip4).addr
				for {
					ip.u_addr.ip6.addr[3] = U32_t(0)
					ip.u_addr.ip6.addr[2] = U32_t(0)
					ip.u_addr.ip6.addr[1] = U32_t(0)
					ip.u_addr.ip6.zone = U8_t(0)
					// while()
					break
				}
			}
			// while()
			break
		}
		ip_pcb := if socket.@type == vinix_net_stream {
			&C.ip_pcb(voidptr(socket.tcp))
		} else {
			&C.ip_pcb(voidptr(socket.udp))
		}
		if ip_pcb {
			ip_pcb.ttl = u8((if (usize((&ip)) != usize((voidptr(0)))) && (i32((*(&ip)).@type) == Lwip_ip_addr_type.ipaddr_type_v6) {
				socket.hops6
			} else {
				socket.hops4
			}))
		}
		if socket.@type == vinix_net_stream && (usize(socket.tcp) == 0) {
			return if socket.error { socket.error } else { 107 }
		}
		if i32(port) == 0 {
			result := bind_ephemeral(socket, &ip)
			if !result {
				socket.bound = 1
			}
			return result
		}
		if socket.@type == vinix_net_stream {
			error_ = C.tcp_bind(socket.tcp, &ip, C.lwip_htons(port))
		} else {
			error_ = C.udp_bind(socket.udp, &ip, C.lwip_htons(port))
		}
		if i32(error_) == Err_enum_t.err_ok {
			socket.bound = 1
		}
		return linux_error(error_)
	}
}

pub fn connect_ip(socket &Vinix_socket, address &C.ip_addr, port u16) i32 {
	unsafe {
		ip := C.ip_addr{}
		error_ := Err_t(0)
		if usize(socket) == 0 {
			return 88
		}
		for {
			for {
				ip.@type = address.@type
				// while()
				break
			}
			if i32(address.@type) == Lwip_ip_addr_type.ipaddr_type_v6 {
				for {
					(&ip.u_addr.ip6).addr[0] = (&address.u_addr.ip6).addr[0]
					(&ip.u_addr.ip6).addr[1] = (&address.u_addr.ip6).addr[1]
					(&ip.u_addr.ip6).addr[2] = (&address.u_addr.ip6).addr[2]
					(&ip.u_addr.ip6).addr[3] = (&address.u_addr.ip6).addr[3]
					(*(&ip.u_addr.ip6)).zone = (*(&address.u_addr.ip6)).zone
					// while()
					break
				}
			} else {
				(&ip.u_addr.ip4).addr = (&address.u_addr.ip4).addr
				for {
					ip.u_addr.ip6.addr[3] = U32_t(0)
					ip.u_addr.ip6.addr[2] = U32_t(0)
					ip.u_addr.ip6.addr[1] = U32_t(0)
					ip.u_addr.ip6.zone = U8_t(0)
					// while()
					break
				}
			}
			// while()
			break
		}
		ip_pcb := socket_ip_pcb(socket)
		if ip_pcb {
			ip_pcb.ttl = u8((if (usize((&ip)) != usize((voidptr(0)))) && (i32((*(&ip)).@type) == Lwip_ip_addr_type.ipaddr_type_v6) {
				socket.hops6
			} else {
				socket.hops4
			}))
		}
		if socket.@type == vinix_net_stream {
			if usize(socket.tcp) == 0 {
				return if socket.error { socket.error } else { 107 }
			}
			if socket.connected {
				return 106
			}
			if socket.connecting {
				return 114
			}
			if i32(socket.tcp.local_port) == 0 {
				bound := bind_ephemeral(socket, &socket.tcp.local_ip)
				if bound {
					return bound
				}
			}
			socket.connecting = 1
			error_ = C.tcp_connect(socket.tcp, &ip, C.lwip_htons(port), tcp_connected)
			if i32(error_) != Err_enum_t.err_ok {
				socket.connecting = 0
				return linux_error(error_)
			}
			for {
				for {
					socket.last_local_address.@type = socket.tcp.local_ip.@type
					// while()
					break
				}
				if i32(socket.tcp.local_ip.@type) == Lwip_ip_addr_type.ipaddr_type_v6 {
					for {
						(&socket.last_local_address.u_addr.ip6).addr[0] = (&socket.tcp.local_ip.u_addr.ip6).addr[0]
						(&socket.last_local_address.u_addr.ip6).addr[1] = (&socket.tcp.local_ip.u_addr.ip6).addr[1]
						(&socket.last_local_address.u_addr.ip6).addr[2] = (&socket.tcp.local_ip.u_addr.ip6).addr[2]
						(&socket.last_local_address.u_addr.ip6).addr[3] = (&socket.tcp.local_ip.u_addr.ip6).addr[3]
						(*(&socket.last_local_address.u_addr.ip6)).zone = (*(&socket.tcp.local_ip.u_addr.ip6)).zone
						// while()
						break
					}
				} else {
					(&socket.last_local_address.u_addr.ip4).addr = (&socket.tcp.local_ip.u_addr.ip4).addr
					for {
						socket.last_local_address.u_addr.ip6.addr[3] = U32_t(0)
						socket.last_local_address.u_addr.ip6.addr[2] = U32_t(0)
						socket.last_local_address.u_addr.ip6.addr[1] = U32_t(0)
						socket.last_local_address.u_addr.ip6.zone = U8_t(0)
						// while()
						break
					}
				}
				// while()
				break
			}
			socket.last_local_port = C.lwip_htons(socket.tcp.local_port)
			// NO_SYS loopback queues packets until C.netif_poll_all().  A busy
			//         *nonblocking client may never let the scheduler reach its idle
			//         *poller, so complete the in-kernel handshake synchronously.

			C.netif_poll_all()
			if socket.error {
				return socket.error
			}
			if socket.connected {
				return 0
			}
			return 115
		}
		if i32(socket.udp.local_port) == 0 {
			bound := bind_ephemeral(socket, &socket.udp.local_ip)
			if bound {
				return bound
			}
		}
		error_ = C.udp_connect(socket.udp, &ip, C.lwip_htons(port))
		if i32(error_) == Err_enum_t.err_ok {
			socket.connected = 1
		}
		return linux_error(error_)
	}
}

@[export: 'vinix_socket_listen']
pub fn vinix_socket_listen(socket &Vinix_socket, backlog i32) i32 {
	unsafe {
		listener := &C.tcp_pcb(0)
		listen_error := &i8(C.vinix_stack_alloc(sizeof(i8)))
		*listen_error = i8(0)
		if (usize(socket) == 0) || (usize(socket.tcp) == 0) || socket.connected || socket.connecting {
			return 95
		}
		if backlog < 0 {
			return 22
		}
		if backlog > 255 {
			backlog = 255
		}
		if i32(socket.tcp.local_port) == 0 {
			bound := bind_ephemeral(socket, &socket.tcp.local_ip)
			if bound {
				return bound
			}
		}
		listener = C.tcp_listen_with_backlog_and_err(socket.tcp, u8(backlog), listen_error)
		if usize(listener) == 0 {
			return linux_error(*listen_error)
		}
		socket.tcp = listener
		socket.listening = 1
		C.tcp_arg(socket.tcp, voidptr(socket))
		C.tcp_accept(socket.tcp, accept_callback)
		return 0
	}
}

@[export: 'vinix_socket_accept']
pub fn vinix_socket_accept(socket &Vinix_socket) &Vinix_socket {
	unsafe {
		child := &Vinix_socket(0)
		if (usize(socket) == 0) || !socket.listening || (usize(socket.accept_head) == 0) {
			return nil
		}
		child = socket.accept_head
		socket.accept_head = child.accept_next
		if usize(socket.accept_head) == 0 {
			socket.accept_tail = nil
		}
		child.accept_next = nil
		C.tcp_backlog_accepted(socket.tcp)
		return child
	}
}

pub fn send_ip(socket &Vinix_socket, data voidptr, length usize, address &C.ip_addr, port u16, has_address i32) i32 {
	unsafe {
		error_ := Err_t(0)
		if (usize(socket) == 0) || ((usize(data) == 0) && length) {
			return -22
		}
		if socket.write_shutdown {
			return -32
		}
		if socket.@type == vinix_net_stream {
			amount := u16(0)
			if usize(socket.tcp) == 0 {
				return -(if socket.error { socket.error } else { 107 })
			}
			if !socket.connected {
				return -107
			}
			if has_address {
				return -106
			}
			if length == usize(0) {
				return 0
			}
			amount = socket.tcp.snd_buf
			if socket.send_queued >= socket.send_limit {
				return -11
			}
			if u32(amount) > socket.send_limit - socket.send_queued {
				amount = u16((socket.send_limit - socket.send_queued))
			}
			if usize(amount) > length {
				amount = u16(length)
			}
			if !amount {
				return -11
			}
			error_ = C.tcp_write(socket.tcp, voidptr(data), amount, U8_t(1))
			if i32(error_) != Err_enum_t.err_ok {
				return -linux_error(error_)
			}
			socket.send_queued += u32(amount)
			// C.tcp_write accepted these bytes. Output failure leaves them queued
			//         *for retransmission; reporting failure would let callers duplicate
			//         *the same bytes on retry.

			C.tcp_output(socket.tcp)
			C.netif_poll_all()
			return i32(amount)
		} else {
			p := &C.pbuf(0)
			if !has_address && !socket.connected {
				return -89
			}
			destination := if has_address { address } else { &socket.udp.remote_ip }
			ipv6 := i32(((usize(destination) != usize((voidptr(0)))) && (i32(destination.@type) == Lwip_ip_addr_type.ipaddr_type_v6)))
			multicast_interface_2 := interface_index(if ipv6 {
				socket.multicast_if6
			} else {
				socket.multicast_if4
			})
			socket.udp.mcast_ifindex = U8_t((if multicast_interface_2 {
				i32((U8_t((i32(multicast_interface_2.num) + 1))))
			} else {
				0
			}))
			multicast_address := C.ip4_addr{
				addr: socket.multicast_addr4
			}

			socket.udp.mcast_ip4.addr = (&multicast_address).addr
			socket.udp.ttl = u8((if ipv6 { socket.hops6 } else { socket.hops4 }))
			socket.udp.mcast_ttl = u8((if ipv6 {
				socket.multicast_hops6
			} else {
				socket.multicast_hops4
			}))
			if if ipv6 { socket.multicast_loop6 } else { socket.multicast_loop4 } {
				socket.udp.flags |= 8
			} else {
				socket.udp.flags &= i32(u8(~8))
			}
			if length > usize(65507) || length > usize(socket.send_limit) {
				return -90
			}
			if i32(socket.udp.local_port) == 0 {
				bound := bind_ephemeral(socket, &socket.udp.local_ip)
				if bound {
					return -bound
				}
			}
			p = C.pbuf_alloc(i32(Pbuf_layer.pbuf_transport), u16(length), i32(Pbuf_type.pbuf_ram))
			if usize(p) == 0 {
				return -12
			}
			if length && i32(C.pbuf_take(p, voidptr(data), u16(length))) != Err_enum_t.err_ok {
				C.pbuf_free(p)
				return -12
			}
			if has_address {
				error_ = C.udp_sendto(socket.udp, p, address, C.lwip_htons(port))
			} else {
				error_ = C.udp_send(socket.udp, p)
			}
			C.pbuf_free(p)
			if i32(error_) != Err_enum_t.err_ok {
				return -linux_error(error_)
			}
			// Deliver loopback datagrams before returning.  External packets do
			//         *not use a loop queue, so polling here is a cheap no-op for them.

			C.netif_poll_all()
			return i32(length)
		}
	}
}

pub fn recv_ip(socket &Vinix_socket, data voidptr, length usize, address &C.ip_addr, port &u16) i32 {
	unsafe {
		packet := &Packet(0)
		available := u16(0)
		amount := u16(0)
		if (usize(socket) == 0) || ((usize(data) == 0) && length) {
			return -22
		}
		if socket.read_shutdown {
			return 0
		}
		packet = socket.rx_head
		if usize(packet) == 0 {
			if socket.@type == vinix_net_stream && socket.peer_closed && !socket.error {
				return 0
			}
			if socket.@type == vinix_net_stream && !socket.connected {
				return -(if socket.error { socket.error } else { 107 })
			}
			return -11
		}
		available = u16((i32(packet.p.tot_len) - i32(packet.offset)))
		amount = u16(if usize(available) < length { i32(available) } else { i32(u16(length)) })
		if amount {
			C.pbuf_copy_partial(packet.p, voidptr(data), amount, packet.offset)
		}
		if address {
			for {
				for {
					address.@type = packet.address.@type
					// while()
					break
				}
				if i32(packet.address.@type) == Lwip_ip_addr_type.ipaddr_type_v6 {
					for {
						(&address.u_addr.ip6).addr[0] = (&packet.address.u_addr.ip6).addr[0]
						(&address.u_addr.ip6).addr[1] = (&packet.address.u_addr.ip6).addr[1]
						(&address.u_addr.ip6).addr[2] = (&packet.address.u_addr.ip6).addr[2]
						(&address.u_addr.ip6).addr[3] = (&packet.address.u_addr.ip6).addr[3]
						(*(&address.u_addr.ip6)).zone = (*(&packet.address.u_addr.ip6)).zone
						// while()
						break
					}
				} else {
					(&address.u_addr.ip4).addr = (&packet.address.u_addr.ip4).addr
					for {
						address.u_addr.ip6.addr[3] = U32_t(0)
						address.u_addr.ip6.addr[2] = U32_t(0)
						address.u_addr.ip6.addr[1] = U32_t(0)
						address.u_addr.ip6.zone = U8_t(0)
						// while()
						break
					}
				}
				// while()
				break
			}
		}
		if port {
			*port = C.lwip_htons(packet.port)
		}
		if socket.@type == vinix_net_stream {
			packet.offset = u16((i32(packet.offset) + i32(amount)))
			if socket.tcp {
				C.tcp_recved(socket.tcp, amount)
			}
			if i32(packet.offset) == i32(packet.p.tot_len) {
				socket.receive_queued -= packet.charge
				socket.rx_head = packet.next
				if usize(socket.rx_head) == 0 {
					socket.rx_tail = nil
				}
				free_packet(packet)
			}
		} else {
			// recvfrom consumes one datagram, including a truncated tail.

			socket.receive_queued -= packet.charge
			socket.rx_head = packet.next
			if usize(socket.rx_head) == 0 {
				socket.rx_tail = nil
			}
			free_packet(packet)
		}
		return i32(amount)
	}
}

@[export: 'vinix_socket_shutdown']
pub fn vinix_socket_shutdown(socket &Vinix_socket, how i32) i32 {
	unsafe {
		error_ := Err_t(0)
		if (usize(socket) == 0) || how < 0 || how > 2 {
			return 22
		}
		if how == 0 || how == 2 {
			socket.read_shutdown = 1
			free_packets(socket)
		}
		if how == 1 || how == 2 {
			socket.write_shutdown = 1
		}
		if socket.@type == vinix_net_stream {
			if usize(socket.tcp) == 0 {
				return if socket.connected { 0 } else { 107 }
			}
			if socket.write_shutdown && (socket.read_shutdown || socket.peer_closed) && u32(socket.tcp.state) != u32(Tcp_state.listen) {
				pcb := socket.tcp
				connecting := socket.connecting
				// Even ERR_MEM while enqueueing FIN is converted by lwIP into
				//             *ERR_OK plus TF_CLOSEPEND. Detach before calling: a successful
				//             *full shutdown may free pcb immediately, or from a later timer.
				//             *After peer EOF, write shutdown also completes the protocol;
				//             *keep queued receive bytes by leaving its receive side open.
				//

				detach_tcp(socket, pcb)
				error_ = C.tcp_shutdown(pcb, socket.read_shutdown, 1)
				if i32(error_) != Err_enum_t.err_ok {
					socket.tcp = pcb
					socket.connecting = connecting
					install_tcp_callbacks(socket)
				}
				return linux_error(error_)
			}
			error_ = C.tcp_shutdown(socket.tcp, how == 0 || how == 2, how == 1 || how == 2)
			return linux_error(error_)
		}
		if how == 1 || how == 2 {
			C.udp_disconnect(socket.udp)
			socket.connected = 0
		}
		return 0
	}
}

@[export: 'vinix_socket_local']
pub fn vinix_socket_local(socket &Vinix_socket, address &u32, port &u16) i32 {
	unsafe {
		if usize(socket) == 0 {
			return 88
		}
		if socket.@type == vinix_net_stream {
			if address {
				*address = if socket.tcp {
					socket.tcp.local_ip.u_addr.ip4.addr
				} else {
					socket.last_local_address.u_addr.ip4.addr
				}
			}
			if port {
				*port = u16(if socket.tcp {
					i32(C.lwip_htons(socket.tcp.local_port))
				} else {
					i32(socket.last_local_port)
				})
			}
		} else {
			if address {
				*address = socket.udp.local_ip.u_addr.ip4.addr
			}
			if port {
				*port = C.lwip_htons(socket.udp.local_port)
			}
		}
		return 0
	}
}

@[export: 'vinix_socket_peer']
pub fn vinix_socket_peer(socket &Vinix_socket, address &u32, port &u16) i32 {
	unsafe {
		if (usize(socket) == 0) || !socket.connected {
			return 107
		}
		if socket.@type == vinix_net_stream {
			if address {
				*address = if socket.tcp {
					socket.tcp.remote_ip.u_addr.ip4.addr
				} else {
					socket.last_remote_address.u_addr.ip4.addr
				}
			}
			if port {
				*port = u16(if socket.tcp {
					i32(C.lwip_htons(socket.tcp.remote_port))
				} else {
					i32(socket.last_remote_port)
				})
			}
		} else {
			if address {
				*address = socket.udp.remote_ip.u_addr.ip4.addr
			}
			if port {
				*port = C.lwip_htons(socket.udp.remote_port)
			}
		}
		return 0
	}
}

@[export: 'vinix_socket_ready']
pub fn vinix_socket_ready(socket &Vinix_socket) i32 {
	unsafe {
		ready := i32(0)
		if usize(socket) == 0 {
			return vinix_net_error
		}
		if if socket.listening {
			usize(socket.accept_head) != usize((voidptr(0)))
		} else {
			(usize(socket.rx_head) != usize((voidptr(0))) || socket.peer_closed || socket.read_shutdown)
		} {
			ready |= vinix_net_readable
		}
		if !socket.write_shutdown && ((!(usize(socket.tcp) == 0) && socket.connected && i32(socket.tcp.snd_buf) > 0 && socket.send_queued < socket.send_limit) || !(usize(socket.udp) == 0)) {
			ready |= vinix_net_writable
		}
		if socket.error {
			ready |= vinix_net_error
		}
		if socket.peer_closed {
			ready |= vinix_net_hangup
		}
		return ready
	}
}

@[export: 'vinix_socket_error']
pub fn vinix_socket_error(socket &Vinix_socket, clear i32) i32 {
	unsafe {
		error_ := i32(0)
		if usize(socket) == 0 {
			return 88
		}
		error_ = socket.error
		if clear {
			socket.error = 0
		}
		return error_
	}
}

@[export: 'vinix_socket_available']
pub fn vinix_socket_available(socket &Vinix_socket) i32 {
	unsafe {
		packet := &Packet(0)
		total := u32(0)
		if usize(socket) == 0 {
			return 0
		}
		for packet = socket.rx_head; packet; packet = packet.next {
			total += u32(i32(packet.p.tot_len) - i32(packet.offset))
			if socket.udp {
				break
			}
		}
		return if total > 2147483647 { 2147483647 } else { i32(total) }
	}
}

pub fn socket_ip_pcb(socket &Vinix_socket) &C.ip_pcb {
	unsafe {
		if socket.tcp {
			return &C.ip_pcb(voidptr(socket.tcp))
		}
		return &C.ip_pcb(voidptr(socket.udp))
	}
}

@[export: 'vinix_socket_set_option']
pub fn vinix_socket_set_option(socket &Vinix_socket, level i32, option i32, value i32) i32 {
	unsafe {
		pcb := &C.ip_pcb(0)
		if usize(socket) == 0 {
			return 88
		}
		pcb = socket_ip_pcb(socket)
		if level == 41 || (level == 0 && (option == 2 || option == 33 || option == 34)) {
			return family_set_option(socket, level, option, value)
		}
		if level == 1 {
			// SOL_SOCKET

			match option {
				2, 15 {
					// SO_REUSEPORT: lwIP shares address-reuse semantics.

					socket.reuseaddr = value != 0
					if pcb {
						if value {
							pcb.so_options = U8_t((u32(pcb.so_options) | 4))
						} else {
							pcb.so_options = U8_t((u32(pcb.so_options) & ~4))
						}
					}
					return 0
				}
				6 {
					// SO_BROADCAST

					socket.broadcast = value != 0
					if pcb {
						if value {
							pcb.so_options = U8_t((u32(pcb.so_options) | 32))
						} else {
							pcb.so_options = U8_t((u32(pcb.so_options) & ~32))
						}
					}
					return 0
				}
				7, 8 {
					// SO_RCVBUF

					if value < 0 {
						return 22
					}
					if value > 2 * 1024 * 1024 {
						value = 2 * 1024 * 1024
					}
					value = if value < 2048 { 4096 } else { value * 2 }
					if option == 7 {
						socket.send_limit = u32(value)
					} else {
						socket.receive_limit = u32(value)
					}
					return 0
				}
				9 {
					// SO_KEEPALIVE

					socket.keepalive = value != 0
					if pcb {
						if value {
							pcb.so_options = U8_t((u32(pcb.so_options) | 8))
						} else {
							pcb.so_options = U8_t((u32(pcb.so_options) & ~8))
						}
					}
					return 0
				}
				else {
					return 92
				}
			}
		}
		if level == 41 && socket.family == 10 {
			if usize(pcb) == 0 {
				return 107
			}
			if option == 26 {
				// IPV6_V6ONLY, before binding or connecting.

				if value != 0 && value != 1 {
					return 22
				}
				if socket.bound || socket.connected || socket.connecting || socket.listening || (!(usize(socket.tcp) == 0) && i32(socket.tcp.local_port)) || (!(usize(socket.udp) == 0) && i32(socket.udp.local_port)) {
					return 22
				}
				socket.v6only = value
				for {
					if value {
						for {
							pcb.local_ip.u_addr.ip6.addr[0] = U32_t(0)
							pcb.local_ip.u_addr.ip6.addr[1] = U32_t(0)
							pcb.local_ip.u_addr.ip6.addr[2] = U32_t(0)
							pcb.local_ip.u_addr.ip6.addr[3] = U32_t(0)
							pcb.local_ip.u_addr.ip6.zone = U8_t(0)
							// while()
							break
						}
						for {
							if usize((&pcb.local_ip)) != usize((voidptr(0))) {
								for {
									(&pcb.local_ip).@type = U8_t(Lwip_ip_addr_type.ipaddr_type_v6)
									// while()
									break
								}
							}
							// while()
							break
						}
					} else {
						pcb.local_ip.u_addr.ip4.addr = (U32_t(0))
						for {
							if usize((&pcb.local_ip)) != usize((voidptr(0))) {
								for {
									(&pcb.local_ip).@type = U8_t(Lwip_ip_addr_type.ipaddr_type_v4)
									// while()
									break
								}
							}
							// while()
							break
						}
						for {
							pcb.local_ip.u_addr.ip6.addr[3] = U32_t(0)
							pcb.local_ip.u_addr.ip6.addr[2] = U32_t(0)
							pcb.local_ip.u_addr.ip6.addr[1] = U32_t(0)
							pcb.local_ip.u_addr.ip6.zone = U8_t(0)
							// while()
							break
						}
					}
					// while()
					break
				}
				if !value {
					for {
						if usize((&pcb.local_ip)) != usize((voidptr(0))) {
							for {
								(&pcb.local_ip).@type = U8_t(Lwip_ip_addr_type.ipaddr_type_any)
								// while()
								break
							}
						}
						// while()
						break
					}
				}
				return 0
			}
			if option == 16 {
				// IPV6_UNICAST_HOPS

				if value < -1 || value > 255 {
					return 22
				}
				pcb.ttl = U8_t(if value == -1 { 64 } else { i32(u8(value)) })
				return 0
			}
			return 92
		}
		if level == 0 {
			// IPPROTO_IP

			if usize(pcb) == 0 {
				return 107
			}
			if value < 0 || value > 255 {
				return 22
			}
			match option {
				1 {
					// IP_TOS

					pcb.tos = u8(value)
					return 0
				}
				2 {
					// IP_TTL

					if value == 0 {
						return 22
					}
					pcb.ttl = u8(value)
					return 0
				}
				else {
					return 92
				}
			}
		}
		if level == 6 {
			// IPPROTO_TCP

			if socket.@type != vinix_net_stream {
				return 92
			}
			match option {
				4, 5, 6 {
					// TCP_KEEPCNT

					if value < 1 || value > (if option == 6 { 127 } else { 32767 }) {
						return 22
					}
					if option == 4 {
						socket.keep_idle = u32(value) * u32(1000)
					} else if option == 5 {
						socket.keep_interval = u32(value) * u32(1000)
					} else {
						socket.keep_count = u32(value)
					}
					if !(usize(socket.tcp) == 0) && u32(socket.tcp.state) != u32(Tcp_state.listen) {
						socket.tcp.keep_idle = socket.keep_idle
						socket.tcp.keep_intvl = socket.keep_interval
						socket.tcp.keep_cnt = socket.keep_count
						socket.tcp.keep_cnt_sent = U8_t(0)
					}
					return 0
				}
				1 {
					// TCP_NODELAY

					if usize(socket.tcp) == 0 {
						return 92
					}
					// A listening pcb is lwIP's smaller tcp_pcb_listen, which has no
					//             *flags: its accept callback lies where they would be, and
					//             *setting TF_NODELAY there turned the callback into a pointer
					//             *to nowhere, which the next connection to finish its handshake
					//             *called. Varnish sets it on its listening socket.

					socket.nodelay = value != 0
					if u32(socket.tcp.state) == u32(Tcp_state.listen) {
						return 0
					}
					if value {
						for {
							socket.tcp.flags = Tcpflags_t((u32(socket.tcp.flags) | 64))
							// while()
							break
						}
					} else {
						for {
							socket.tcp.flags = Tcpflags_t((i32(socket.tcp.flags) & i32(Tcpflags_t((~64 & 65535)))))
							// while()
							break
						}
					}
					return 0
				}
				else {
					return 92
				}
			}
		}
		return 92
	}
}

@[export: 'vinix_socket_get_option']
pub fn vinix_socket_get_option(socket &Vinix_socket, level i32, option i32, value &i32) i32 {
	unsafe {
		pcb := &C.ip_pcb(0)
		if (usize(socket) == 0) || (usize(value) == 0) {
			return 22
		}
		pcb = socket_ip_pcb(socket)
		if level == 41 || (level == 0 && (option == 2 || option == 33 || option == 34 || option == 32)) {
			return family_get_option(socket, level, option, value)
		}
		if level == 1 {
			// SOL_SOCKET

			match option {
				2, 15 {
					*value = socket.reuseaddr
					return 0
				}
				6 {
					*value = socket.broadcast
					return 0
				}
				7 {
					*value = i32(socket.send_limit)
					return 0
				}
				8 {
					*value = i32(socket.receive_limit)
					return 0
				}
				9 {
					*value = socket.keepalive
					return 0
				}
				else {
					return 92
				}
			}
		}
		if level == 41 && socket.family == 10 {
			if option == 26 {
				*value = socket.v6only
				return 0
			}
			if option == 16 && !(usize(pcb) == 0) {
				*value = i32(pcb.ttl)
				return 0
			}
			return 92
		}
		if level == 0 {
			// IPPROTO_IP

			if usize(pcb) == 0 {
				return 107
			}
			match option {
				1 {
					*value = i32(pcb.tos)
					return 0
				}
				2 {
					*value = i32(pcb.ttl)
					return 0
				}
				else {
					return 92
				}
			}
		}
		if level == 6 {
			// IPPROTO_TCP

			if socket.@type != vinix_net_stream {
				return 92
			}
			match option {
				4 {
					*value = i32((socket.keep_idle / u32(1000)))
					return 0
				}
				5 {
					*value = i32((socket.keep_interval / u32(1000)))
					return 0
				}
				6 {
					*value = i32(socket.keep_count)
					return 0
				}
				1 {
					if usize(socket.tcp) == 0 {
						return 92
					}
					if u32(socket.tcp.state) == u32(Tcp_state.listen) {
						*value = socket.nodelay
						return 0
					}
					*value = if (u32(socket.tcp.flags) & 64) != u32(0) { 1 } else { 0 }
					return 0
				}
				else {
					return 92
				}
			}
		}
		return 92
	}
}

// The V descriptor remains registered while close waits for acknowledgments.
// *Abort is also used after a linger timeout, before freeing callbacks.

@[export: 'vinix_socket_pending']
pub fn vinix_socket_pending(socket &Vinix_socket) i32 {
	unsafe {
		return if !(usize(socket) == 0) && !(usize(socket.tcp) == 0) && !socket.listening {
			i32(socket.send_queued)
		} else {
			0
		}
	}
}

@[export: 'vinix_socket_abort_close']
pub fn vinix_socket_abort_close(socket &Vinix_socket) {
	unsafe {
		if socket {
			socket.abort_on_close = 1
		}
	}
}

// Endpoint and membership calls share the existing lwIP lock.

// Linux exposes lo=1, eth0=2. lwIP's native index increments on hotplug,
// *so translate only at the API boundary; zones keep the native index.

pub fn linux_interface_index(interface_ &C.netif) u32 {
	unsafe {
		if usize(interface_) == 0 {
			return u32(0)
		}
		if usize(interface_) == usize(&net_physical_netif) {
			return u32(2)
		}
		return u32(if ((&C.ip4_addr((&interface_.ip_addr.u_addr.ip4))).addr & (((u32(4278190080) & U32_t(255)) << 24) | ((u32(4278190080) & U32_t(65280)) << 8) | ((u32(4278190080) & U32_t(16711680)) >> 8) | ((u32(4278190080) & U32_t(u64(4278190080))) >> 24))) == (((((U32_t(127)) << 24) & U32_t(255)) << 24) | ((((U32_t(127)) << 24) & U32_t(65280)) << 8) | ((((U32_t(127)) << 24) & U32_t(16711680)) >> 8) | ((((U32_t(127)) << 24) & U32_t(u64(4278190080))) >> 24)) {
			1
		} else {
			0
		})
	}
}

@[export: 'vinix_net_core_interface_index']
pub fn interface_index(index u32) &C.netif {
	unsafe {
		if index == u32(2) {
			return if net_link_attached { &net_physical_netif } else { &C.netif(nil) }
		}
		if index != u32(1) {
			return nil
		}
		interface_ := &C.netif(0)
		for interface_ = C.netif_list; usize(interface_) != usize((voidptr(0))); interface_ = interface_.next {
			if linux_interface_index(interface_) == u32(1) {
				return interface_
			}
		}
		return nil
	}
}

pub fn interface_epoch(interface_ &C.netif) u64 {
	unsafe {
		return if usize(interface_) == usize(&net_physical_netif) { net_link_epoch } else { u64(1) }
	}
}

pub fn multicast_interface(index u32, address u32) &C.netif {
	unsafe {
		if index {
			return interface_index(index)
		}
		if address {
			interface_ := &C.netif(0)
			for interface_ = C.netif_list; usize(interface_) != usize((voidptr(0))); interface_ = interface_.next {
				if (&C.ip4_addr((&interface_.ip_addr.u_addr.ip4))).addr == address {
					return interface_
				}
			}
			return nil
		}
		return C.netif_default
	}
}

@[export: 'vinix_net_core_endpoint_ip']
pub fn endpoint_ip(socket &Vinix_socket, endpoint &C.vinix_net_endpoint, ip &C.ip_addr) i32 {
	unsafe {
		if (usize(socket) == 0) || (usize(endpoint) == 0) {
			return 22
		}
		C.memset(voidptr(ip), 0, sizeof(C.ip_addr))
		if i32(endpoint.family) == 2 {
			if socket.family != 2 && socket.v6only {
				return 97
			}
			*ip = ipv4(endpoint.words[0])
			return 0
		}
		if i32(endpoint.family) != 10 || socket.family != 10 {
			return 97
		}
		for {
			ip.@type = U8_t(Lwip_ip_addr_type.ipaddr_type_v6)
			// while()
			break
		}
		C.memcpy(ip.u_addr.ip6.addr, endpoint.words, usize(16))
		if (ip.u_addr.ip6.addr[0] == U32_t(0))
			&& (ip.u_addr.ip6.addr[1] == U32_t(0))
			&& (u64(ip.u_addr.ip6.addr[2]) == (((65535 & u64(U32_t(255))) << 24) | ((65535 & u64(U32_t(65280))) << 8) | ((65535 & u64(U32_t(16711680))) >> 8) | ((65535 & u64(U32_t(u64(4278190080)))) >> 24))) {
			if socket.v6only {
				return 101
			}
			*ip = ipv4(endpoint.words[3])
			return 0
		}
		if endpoint.scope {
			interface_ := interface_index(endpoint.scope)
			if (usize(interface_) == 0) || !(if u32(interface_.flags) & 1 {
				i32(U8_t(1))
			} else {
				i32(U8_t(0))
			}) {
				return 19
			}
			ip.u_addr.ip6.zone = U8_t((if ((u64(ip.u_addr.ip6.addr[0]) & (((u64(4290772992) & u64(U32_t(255))) << 24) | ((u64(4290772992) & u64(U32_t(65280))) << 8) | ((u64(4290772992) & u64(U32_t(16711680))) >> 8) | ((u64(4290772992) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4269801472) & u64(U32_t(255))) << 24) | ((u64(4269801472) & u64(U32_t(65280))) << 8) | ((u64(4269801472) & u64(U32_t(16711680))) >> 8) | ((u64(4269801472) & u64(U32_t(u64(4278190080)))) >> 24))) || ((Lwip_ipv6_scope_type.ip6_unknown != Lwip_ipv6_scope_type.ip6_unicast) && (((u64(ip.u_addr.ip6.addr[0]) & (((u64(4287561728) & u64(U32_t(255))) << 24) | ((u64(4287561728) & u64(U32_t(65280))) << 8) | ((u64(4287561728) & u64(U32_t(16711680))) >> 8) | ((u64(4287561728) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4278255616) & u64(U32_t(255))) << 24) | ((u64(4278255616) & u64(U32_t(65280))) << 8) | ((u64(4278255616) & u64(U32_t(16711680))) >> 8) | ((u64(4278255616) & u64(U32_t(u64(4278190080)))) >> 24))) || ((u64(ip.u_addr.ip6.addr[0]) & (((u64(4287561728) & u64(U32_t(255))) << 24) | ((u64(4287561728) & u64(U32_t(65280))) << 8) | ((u64(4287561728) & u64(U32_t(16711680))) >> 8) | ((u64(4287561728) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4278321152) & u64(U32_t(255))) << 24) | ((u64(4278321152) & u64(U32_t(65280))) << 8) | ((u64(4278321152) & u64(U32_t(16711680))) >> 8) | ((u64(4278321152) & u64(U32_t(u64(4278190080)))) >> 24))))) {
				i32((U8_t((i32(interface_.num) + 1))))
			} else {
				0
			}))
		} else if !(i32(ip.u_addr.ip6.zone) != 0) && (((u64(ip.u_addr.ip6.addr[0]) & (((u64(4290772992) & u64(U32_t(255))) << 24) | ((u64(4290772992) & u64(U32_t(65280))) << 8) | ((u64(4290772992) & u64(U32_t(16711680))) >> 8) | ((u64(4290772992) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4269801472) & u64(U32_t(255))) << 24) | ((u64(4269801472) & u64(U32_t(65280))) << 8) | ((u64(4269801472) & u64(U32_t(16711680))) >> 8) | ((u64(4269801472) & u64(U32_t(u64(4278190080)))) >> 24))) || ((Lwip_ipv6_scope_type.ip6_unknown != Lwip_ipv6_scope_type.ip6_unicast) && (((u64(ip.u_addr.ip6.addr[0]) & (((u64(4287561728) & u64(U32_t(255))) << 24) | ((u64(4287561728) & u64(U32_t(65280))) << 8) | ((u64(4287561728) & u64(U32_t(16711680))) >> 8) | ((u64(4287561728) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4278255616) & u64(U32_t(255))) << 24) | ((u64(4278255616) & u64(U32_t(65280))) << 8) | ((u64(4278255616) & u64(U32_t(16711680))) >> 8) | ((u64(4278255616) & u64(U32_t(u64(4278190080)))) >> 24))) || ((u64(ip.u_addr.ip6.addr[0]) & (((u64(4287561728) & u64(U32_t(255))) << 24) | ((u64(4287561728) & u64(U32_t(65280))) << 8) | ((u64(4287561728) & u64(U32_t(16711680))) >> 8) | ((u64(4287561728) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4278321152) & u64(U32_t(255))) << 24) | ((u64(4278321152) & u64(U32_t(65280))) << 8) | ((u64(4278321152) & u64(U32_t(16711680))) >> 8) | ((u64(4278321152) & u64(U32_t(u64(4278190080)))) >> 24)))))) {
			index := socket.multicast_if6
			local := if socket.udp {
				&socket.udp.local_ip
			} else {
				if socket.tcp { &socket.tcp.local_ip } else { &C.ip_addr(nil) }
			}
			if !index && !(usize(local) == 0) && ((usize(local) != usize((voidptr(0)))) && (i32(local.@type) == Lwip_ip_addr_type.ipaddr_type_v6)) {
				index = linux_interface_index(C.netif_get_by_index(local.u_addr.ip6.zone))
			}
			interface_ := interface_index(index)
			if usize(interface_) == 0 {
				return 22
			}
			ip.u_addr.ip6.zone = U8_t((if ((u64(ip.u_addr.ip6.addr[0]) & (((u64(4290772992) & u64(U32_t(255))) << 24) | ((u64(4290772992) & u64(U32_t(65280))) << 8) | ((u64(4290772992) & u64(U32_t(16711680))) >> 8) | ((u64(4290772992) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4269801472) & u64(U32_t(255))) << 24) | ((u64(4269801472) & u64(U32_t(65280))) << 8) | ((u64(4269801472) & u64(U32_t(16711680))) >> 8) | ((u64(4269801472) & u64(U32_t(u64(4278190080)))) >> 24))) || ((Lwip_ipv6_scope_type.ip6_unknown != Lwip_ipv6_scope_type.ip6_unicast) && (((u64(ip.u_addr.ip6.addr[0]) & (((u64(4287561728) & u64(U32_t(255))) << 24) | ((u64(4287561728) & u64(U32_t(65280))) << 8) | ((u64(4287561728) & u64(U32_t(16711680))) >> 8) | ((u64(4287561728) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4278255616) & u64(U32_t(255))) << 24) | ((u64(4278255616) & u64(U32_t(65280))) << 8) | ((u64(4278255616) & u64(U32_t(16711680))) >> 8) | ((u64(4278255616) & u64(U32_t(u64(4278190080)))) >> 24))) || ((u64(ip.u_addr.ip6.addr[0]) & (((u64(4287561728) & u64(U32_t(255))) << 24) | ((u64(4287561728) & u64(U32_t(65280))) << 8) | ((u64(4287561728) & u64(U32_t(16711680))) >> 8) | ((u64(4287561728) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4278321152) & u64(U32_t(255))) << 24) | ((u64(4278321152) & u64(U32_t(65280))) << 8) | ((u64(4278321152) & u64(U32_t(16711680))) >> 8) | ((u64(4278321152) & u64(U32_t(u64(4278190080)))) >> 24))))) {
				i32((U8_t((i32(interface_.num) + 1))))
			} else {
				0
			}))
		}
		return 0
	}
}

pub fn endpoint_from_ip(family i32, ip &C.ip_addr, port u16, endpoint &C.vinix_net_endpoint) {
	unsafe {
		C.memset(voidptr(endpoint), 0, sizeof(C.vinix_net_endpoint))
		endpoint.family = u16(family)
		endpoint.port = port
		if (usize(ip) != usize((voidptr(0)))) && (i32(ip.@type) == Lwip_ip_addr_type.ipaddr_type_v6) {
			C.memcpy(endpoint.words, ip.u_addr.ip6.addr, usize(16))
			endpoint.scope = linux_interface_index(C.netif_get_by_index(ip.u_addr.ip6.zone))
		} else if !(i32(ip.@type) == Lwip_ip_addr_type.ipaddr_type_any) {
			if family == 10 {
				endpoint.words[2] = (((U32_t(65535) & U32_t(255)) << 24) | ((U32_t(65535) & U32_t(65280)) << 8) | ((U32_t(65535) & U32_t(16711680)) >> 8) | ((U32_t(65535) & U32_t(u64(4278190080))) >> 24))
				endpoint.words[3] = ip.u_addr.ip4.addr
			} else {
				endpoint.words[0] = ip.u_addr.ip4.addr
			}
		}
	}
}

@[export: 'vinix_socket_new_family']
pub fn vinix_socket_new_family(@type i32, protocol i32, family i32) &Vinix_socket {
	unsafe {
		if family != 2 && family != 10 {
			return nil
		}
		socket := vinix_socket_new(@type, protocol)
		if usize(socket) == 0 {
			return nil
		}
		socket.family = family
		if family == 10 {
			pcb := socket_ip_pcb(socket)
			for {
				pcb.local_ip.@type = U8_t(Lwip_ip_addr_type.ipaddr_type_any)
				// while()
				break
			}
			for {
				pcb.remote_ip.@type = U8_t(Lwip_ip_addr_type.ipaddr_type_any)
				// while()
				break
			}
		}
		return socket
	}
}

@[export: 'vinix_socket_bind_endpoint']
pub fn vinix_socket_bind_endpoint(socket &Vinix_socket, endpoint &C.vinix_net_endpoint) i32 {
	unsafe {
		ip := C.ip_addr{}
		error_ := endpoint_ip(socket, endpoint, &ip)
		if error_ {
			return error_
		}
		mut __c2v_condition_5 := false
		mut __c2v_condition_6 := false
		__c2v_condition_6 = ((usize((&ip)) != usize((voidptr(0)))) && (i32((*(&ip)).@type) == Lwip_ip_addr_type.ipaddr_type_v6))
		if __c2v_condition_6 {
			__c2v_condition_6 = !((usize((&ip.u_addr.ip6)) == usize((voidptr(0)))) || (((&ip.u_addr.ip6).addr[0] == U32_t(0)) && ((&ip.u_addr.ip6).addr[1] == U32_t(0)) && ((&ip.u_addr.ip6).addr[2] == U32_t(0)) && ((&ip.u_addr.ip6).addr[3] == U32_t(0))))
		}
		if __c2v_condition_6 {
			__c2v_condition_6 = !((u64(ip.u_addr.ip6.addr[0]) & (((u64(4278190080) & u64(U32_t(255))) << 24) | ((u64(4278190080) & u64(U32_t(65280))) << 8) | ((u64(4278190080) & u64(U32_t(16711680))) >> 8) | ((u64(4278190080) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4278190080) & u64(U32_t(255))) << 24) | ((u64(4278190080) & u64(U32_t(65280))) << 8) | ((u64(4278190080) & u64(U32_t(16711680))) >> 8) | ((u64(4278190080) & u64(U32_t(u64(4278190080)))) >> 24)))
		}
		__c2v_condition_5 = __c2v_condition_6
		if __c2v_condition_5 {
			interface_ := &C.netif(0)
			found := i32(0)
			for interface_ = C.netif_list; usize(interface_) != usize((voidptr(0))); interface_ = interface_.next {
				if endpoint.scope && linux_interface_index(interface_) != endpoint.scope {
					continue
				}
				for slot := i32(0); slot < 6; slot++ {
					mut __c2v_condition_7 := false
					mut __c2v_condition_8 := false
					__c2v_condition_8 = (i32(interface_.ip6_addr_state[slot]) & 16)
					if __c2v_condition_8 {
						__c2v_condition_8 = ((((&C.ip6_addr((&interface_.ip6_addr[slot].u_addr.ip6))).addr[0] == ip.u_addr.ip6.addr[0]) && ((&C.ip6_addr((&interface_.ip6_addr[slot].u_addr.ip6))).addr[1] == ip.u_addr.ip6.addr[1]) && ((&C.ip6_addr((&interface_.ip6_addr[slot].u_addr.ip6))).addr[2] == ip.u_addr.ip6.addr[2]) && ((&C.ip6_addr((&interface_.ip6_addr[slot].u_addr.ip6))).addr[3] == ip.u_addr.ip6.addr[3])) && (i32((&C.ip6_addr((&interface_.ip6_addr[slot].u_addr.ip6))).zone) == i32(ip.u_addr.ip6.zone)))
					}
					__c2v_condition_7 = __c2v_condition_8
					if __c2v_condition_7 {
						found = 1
					}
				}
			}
			if !found {
				return 99
			}
		}
		mut __c2v_condition_9 := false
		mut __c2v_condition_10 := false
		__c2v_condition_10 = socket.family == 10
		if __c2v_condition_10 {
			__c2v_condition_10 = !socket.v6only
		}
		if __c2v_condition_10 {
			__c2v_condition_10 = ((usize((&ip)) != usize((voidptr(0)))) && (i32((*(&ip)).@type) == Lwip_ip_addr_type.ipaddr_type_v6))
		}
		if __c2v_condition_10 {
			__c2v_condition_10 = ((usize((&ip.u_addr.ip6)) == usize((voidptr(0)))) || (((&ip.u_addr.ip6).addr[0] == U32_t(0)) && ((&ip.u_addr.ip6).addr[1] == U32_t(0)) && ((&ip.u_addr.ip6).addr[2] == U32_t(0)) && ((&ip.u_addr.ip6).addr[3] == U32_t(0))))
		}
		__c2v_condition_9 = __c2v_condition_10
		if __c2v_condition_9 {
			for {
				ip.@type = U8_t(Lwip_ip_addr_type.ipaddr_type_any)
				// while()
				break
			}
		}
		return bind_ip(socket, &ip, endpoint.port)
	}
}

@[export: 'vinix_socket_connect_endpoint']
pub fn vinix_socket_connect_endpoint(socket &Vinix_socket, endpoint &C.vinix_net_endpoint) i32 {
	unsafe {
		ip := C.ip_addr{}
		error_ := endpoint_ip(socket, endpoint, &ip)
		if error_ {
			return error_
		}
		return connect_ip(socket, &ip, endpoint.port)
	}
}

@[export: 'vinix_socket_send_endpoint']
pub fn vinix_socket_send_endpoint(socket &Vinix_socket, data voidptr, length usize, endpoint &C.vinix_net_endpoint, has_address i32) i32 {
	unsafe {
		ip := C.ip_addr{}
		if has_address {
			error_ := endpoint_ip(socket, endpoint, &ip)
			if error_ {
				return -error_
			}
		}
		return send_ip(socket, voidptr(data), length, if has_address {
			&ip
		} else {
			&C.ip_addr(nil)
		}, u16(if has_address { i32(endpoint.port) } else { 0 }), has_address)
	}
}

@[export: 'vinix_socket_recv_endpoint']
pub fn vinix_socket_recv_endpoint(socket &Vinix_socket, data voidptr, length usize, endpoint &C.vinix_net_endpoint) i32 {
	unsafe {
		ip := C.ip_addr{}
		port := u16(0)
		C.memset(voidptr(&ip), 0, sizeof(ip))
		result := recv_ip(socket, voidptr(data), length, &ip, &port)
		if result >= 0 && !(usize(endpoint) == 0) {
			endpoint_from_ip(socket.family, &ip, port, endpoint)
		}
		return result
	}
}

@[export: 'vinix_socket_name_endpoint']
pub fn vinix_socket_name_endpoint(socket &Vinix_socket, endpoint &C.vinix_net_endpoint, peer i32) i32 {
	unsafe {
		if (usize(socket) == 0) || (usize(endpoint) == 0) {
			return 22
		}
		if peer && !socket.connected {
			return 107
		}
		ip := &C.ip_addr(0)
		port := u16(0)
		if socket.@type == vinix_net_stream {
			ip = if socket.tcp {
				(if peer { &socket.tcp.remote_ip } else { &socket.tcp.local_ip })
			} else {
				(if peer { &socket.last_remote_address } else { &socket.last_local_address })
			}
			port = u16(if socket.tcp {
				i32(C.lwip_htons(U16_t(if peer {
					i32(socket.tcp.remote_port)
				} else {
					i32(socket.tcp.local_port)
				})))
			} else {
				(if peer { i32(socket.last_remote_port) } else { i32(socket.last_local_port) })
			})
		} else {
			ip = if peer { &socket.udp.remote_ip } else { &socket.udp.local_ip }
			port = C.lwip_htons(U16_t(if peer {
				i32(socket.udp.remote_port)
			} else {
				i32(socket.udp.local_port)
			}))
		}
		endpoint_from_ip(socket.family, ip, port, endpoint)
		return 0
	}
}

// Preserve the original IPv4 bridge ABI used by existing production/tests.

@[export: 'vinix_socket_bind']
pub fn vinix_socket_bind(socket &Vinix_socket, address u32, port u16) i32 {
	unsafe {
		ip := ipv4(address)
		return bind_ip(socket, &ip, port)
	}
}

@[export: 'vinix_socket_connect']
pub fn vinix_socket_connect(socket &Vinix_socket, address u32, port u16) i32 {
	unsafe {
		ip := ipv4(address)
		return connect_ip(socket, &ip, port)
	}
}

@[export: 'vinix_socket_send']
pub fn vinix_socket_send(socket &Vinix_socket, data voidptr, length usize, address u32, port u16, has_address i32) i32 {
	unsafe {
		ip := ipv4(address)
		return send_ip(socket, voidptr(data), length, &ip, port, has_address)
	}
}

@[export: 'vinix_socket_recv']
pub fn vinix_socket_recv(socket &Vinix_socket, data voidptr, length usize, address &u32, port &u16) i32 {
	unsafe {
		ip := C.ip_addr{}
		result := recv_ip(socket, voidptr(data), length, if address {
			&ip
		} else {
			&C.ip_addr(nil)
		}, port)
		if result >= 0 && !(usize(address) == 0) {
			*address = ip.u_addr.ip4.addr
		}
		return result
	}
}

pub fn live_membership(member &Membership, interface_ &C.netif) i32 {
	unsafe {
		return i32(i32(member.used) && !(usize(interface_) == 0) && linux_interface_index(interface_) == u32(member.ifindex) && interface_epoch(interface_) == member.epoch)
	}
}

pub fn has_membership(socket &Vinix_socket, group &C.ip_addr, interface_ &C.netif) i32 {
	unsafe {
		for i := i32(0); i < 16; i++ {
			member := &socket.memberships[0] + i
			mut __c2v_condition_11 := false
			mut __c2v_condition_12 := false
			__c2v_condition_12 = live_membership(member, interface_)
			if __c2v_condition_12 {
				__c2v_condition_12 = (if i32(member.group.@type) != i32(group.@type) {
					0
				} else {
					(if i32((*(&member.group)).@type) == Lwip_ip_addr_type.ipaddr_type_v6 {
						(((member.group.u_addr.ip6.addr[0] == group.u_addr.ip6.addr[0]) && (member.group.u_addr.ip6.addr[1] == group.u_addr.ip6.addr[1]) && (member.group.u_addr.ip6.addr[2] == group.u_addr.ip6.addr[2]) && (member.group.u_addr.ip6.addr[3] == group.u_addr.ip6.addr[3])) && (i32(member.group.u_addr.ip6.zone) == i32(group.u_addr.ip6.zone)))
					} else {
						(member.group.u_addr.ip4.addr == group.u_addr.ip4.addr)
					})
				})
			}
			__c2v_condition_11 = __c2v_condition_12
			if __c2v_condition_11 {
				return 1
			}
		}
		return 0
	}
}

pub fn automatic_allhosts(group &C.ip_addr) i32 {
	unsafe {
		return i32(((usize(group) == usize((voidptr(0)))) || (i32(group.@type) == Lwip_ip_addr_type.ipaddr_type_v4)) && group.u_addr.ip4.addr == (((u32(3758096385) & U32_t(255)) << 24) | ((u32(3758096385) & U32_t(65280)) << 8) | ((u32(3758096385) & U32_t(16711680)) >> 8) | ((u32(3758096385) & U32_t(u64(4278190080))) >> 24)))
	}
}

pub fn leave_membership(member &Membership, interface_ &C.netif) Err_t {
	unsafe {
		// IGMP owns the permanent 224.0.0.1 group until C.netif_remove. Its native
		//     *join/leave API excludes this address; socket policy records borrow it.

		if automatic_allhosts(&member.group) {
			return Err_t(Err_enum_t.err_ok)
		}
		return Err_t(if (usize((&member.group)) != usize((voidptr(0)))) && (i32((*(&member.group)).@type) == Lwip_ip_addr_type.ipaddr_type_v6) {
			i32(C.mld6_leavegroup_netif(interface_, (&member.group.u_addr.ip6)))
		} else {
			i32(C.igmp_leavegroup_netif(interface_, (&member.group.u_addr.ip4)))
		})
	}
}

pub fn release_memberships(socket &Vinix_socket) {
	unsafe {
		for i := i32(0); i < 16; i++ {
			member := &socket.memberships[0] + i
			interface_ := interface_index(u32(member.ifindex))
			if live_membership(member, interface_) {
				leave_membership(member, interface_)
			}
			member.used = u8(0)
		}
	}
}

@[export: 'vinix_socket_membership']
pub fn vinix_socket_membership(socket &Vinix_socket, endpoint &C.vinix_net_endpoint, interface_address u32, join i32) i32 {
	unsafe {
		if (usize(socket) == 0) || (usize(endpoint) == 0) || (i32(endpoint.family) != 2 && i32(endpoint.family) != 10) {
			return 22
		}
		if i32(endpoint.family) == 10 && socket.family != 10 {
			return 92
		}
		group := C.ip_addr{}
		C.memset(voidptr(&group), 0, sizeof(group))
		for {
			group.@type = U8_t((if i32(endpoint.family) == 10 {
				Lwip_ip_addr_type.ipaddr_type_v6
			} else {
				Lwip_ip_addr_type.ipaddr_type_v4
			}))
			// while()
			break
		}
		if i32(endpoint.family) == 10 {
			C.memcpy(group.u_addr.ip6.addr, endpoint.words, usize(16))
		} else {
			group.u_addr.ip4.addr = endpoint.words[0]
		}
		if !(if (usize((&group)) != usize((voidptr(0))))
			&& (i32((*(&group)).@type) == Lwip_ip_addr_type.ipaddr_type_v6) {
			((u64(group.u_addr.ip6.addr[0]) & (((u64(4278190080) & u64(U32_t(255))) << 24) | ((u64(4278190080) & u64(U32_t(65280))) << 8) | ((u64(4278190080) & u64(U32_t(16711680))) >> 8) | ((u64(4278190080) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4278190080) & u64(U32_t(255))) << 24) | ((u64(4278190080) & u64(U32_t(65280))) << 8) | ((u64(4278190080) & u64(U32_t(16711680))) >> 8) | ((u64(4278190080) & u64(U32_t(u64(4278190080)))) >> 24)))
		} else {
			((u64(group.u_addr.ip4.addr) & (((u64(4026531840) & u64(U32_t(255))) << 24) | ((u64(4026531840) & u64(U32_t(65280))) << 8) | ((u64(4026531840) & u64(U32_t(16711680))) >> 8) | ((u64(4026531840) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(3758096384) & u64(U32_t(255))) << 24) | ((u64(3758096384) & u64(U32_t(65280))) << 8) | ((u64(3758096384) & u64(U32_t(16711680))) >> 8) | ((u64(3758096384) & u64(U32_t(u64(4278190080)))) >> 24)))
		}) {
			return 22
		}
		index := endpoint.scope
		interface_ := &C.netif(nil)
		if !join && !index && !interface_address {
			for i := i32(0); i < 16; i++ {
				member := &socket.memberships[0] + i
				candidate := interface_index(u32(member.ifindex))
				if live_membership(member, candidate) {
					comparable := group
					if (usize((&comparable)) != usize((voidptr(0)))) && (i32((*(&comparable)).@type) == Lwip_ip_addr_type.ipaddr_type_v6) {
						comparable.u_addr.ip6.zone = U8_t((if ((u64(comparable.u_addr.ip6.addr[0]) & (((u64(4290772992) & u64(U32_t(255))) << 24) | ((u64(4290772992) & u64(U32_t(65280))) << 8) | ((u64(4290772992) & u64(U32_t(16711680))) >> 8) | ((u64(4290772992) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4269801472) & u64(U32_t(255))) << 24) | ((u64(4269801472) & u64(U32_t(65280))) << 8) | ((u64(4269801472) & u64(U32_t(16711680))) >> 8) | ((u64(4269801472) & u64(U32_t(u64(4278190080)))) >> 24))) || ((Lwip_ipv6_scope_type.ip6_multicast != Lwip_ipv6_scope_type.ip6_unicast) && (((u64(comparable.u_addr.ip6.addr[0]) & (((u64(4287561728) & u64(U32_t(255))) << 24) | ((u64(4287561728) & u64(U32_t(65280))) << 8) | ((u64(4287561728) & u64(U32_t(16711680))) >> 8) | ((u64(4287561728) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4278255616) & u64(U32_t(255))) << 24) | ((u64(4278255616) & u64(U32_t(65280))) << 8) | ((u64(4278255616) & u64(U32_t(16711680))) >> 8) | ((u64(4278255616) & u64(U32_t(u64(4278190080)))) >> 24))) || ((u64(comparable.u_addr.ip6.addr[0]) & (((u64(4287561728) & u64(U32_t(255))) << 24) | ((u64(4287561728) & u64(U32_t(65280))) << 8) | ((u64(4287561728) & u64(U32_t(16711680))) >> 8) | ((u64(4287561728) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4278321152) & u64(U32_t(255))) << 24) | ((u64(4278321152) & u64(U32_t(65280))) << 8) | ((u64(4278321152) & u64(U32_t(16711680))) >> 8) | ((u64(4278321152) & u64(U32_t(u64(4278190080)))) >> 24))))) {
							i32((U8_t((i32(candidate.num) + 1))))
						} else {
							0
						}))
					}
					if if i32(member.group.@type) != i32(comparable.@type) {
						0
					} else {
						(if i32((*(&member.group)).@type) == Lwip_ip_addr_type.ipaddr_type_v6 {
							(((member.group.u_addr.ip6.addr[0] == comparable.u_addr.ip6.addr[0])
								&& (member.group.u_addr.ip6.addr[1] == comparable.u_addr.ip6.addr[1])
								&& (member.group.u_addr.ip6.addr[2] == comparable.u_addr.ip6.addr[2])
								&& (member.group.u_addr.ip6.addr[3] == comparable.u_addr.ip6.addr[3]))
								&& (i32(member.group.u_addr.ip6.zone) == i32(comparable.u_addr.ip6.zone)))
						} else {
							(member.group.u_addr.ip4.addr == comparable.u_addr.ip4.addr)
						})
					} {
						interface_ = candidate
						break
					}
				}
			}
			if usize(interface_) == 0 {
				return 99
			}
		} else {
			if !index && !interface_address {
				index = if i32(endpoint.family) == 10 {
					socket.multicast_if6
				} else {
					socket.multicast_if4
				}
			}
			interface_ = multicast_interface(index, interface_address)
		}
		if (usize(interface_) == 0) || !(if u32(interface_.flags) & 1 {
			i32(U8_t(1))
		} else {
			i32(U8_t(0))
		}) {
			return 19
		}
		if (usize((&group)) != usize((voidptr(0)))) && (i32((*(&group)).@type) == Lwip_ip_addr_type.ipaddr_type_v6) {
			group.u_addr.ip6.zone = U8_t((if ((u64(group.u_addr.ip6.addr[0]) & (((u64(4290772992) & u64(U32_t(255))) << 24) | ((u64(4290772992) & u64(U32_t(65280))) << 8) | ((u64(4290772992) & u64(U32_t(16711680))) >> 8) | ((u64(4290772992) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4269801472) & u64(U32_t(255))) << 24) | ((u64(4269801472) & u64(U32_t(65280))) << 8) | ((u64(4269801472) & u64(U32_t(16711680))) >> 8) | ((u64(4269801472) & u64(U32_t(u64(4278190080)))) >> 24))) || ((Lwip_ipv6_scope_type.ip6_multicast != Lwip_ipv6_scope_type.ip6_unicast) && (((u64(group.u_addr.ip6.addr[0]) & (((u64(4287561728) & u64(U32_t(255))) << 24) | ((u64(4287561728) & u64(U32_t(65280))) << 8) | ((u64(4287561728) & u64(U32_t(16711680))) >> 8) | ((u64(4287561728) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4278255616) & u64(U32_t(255))) << 24) | ((u64(4278255616) & u64(U32_t(65280))) << 8) | ((u64(4278255616) & u64(U32_t(16711680))) >> 8) | ((u64(4278255616) & u64(U32_t(u64(4278190080)))) >> 24))) || ((u64(group.u_addr.ip6.addr[0]) & (((u64(4287561728) & u64(U32_t(255))) << 24) | ((u64(4287561728) & u64(U32_t(65280))) << 8) | ((u64(4287561728) & u64(U32_t(16711680))) >> 8) | ((u64(4287561728) & u64(U32_t(u64(4278190080)))) >> 24))) == (((u64(4278321152) & u64(U32_t(255))) << 24) | ((u64(4278321152) & u64(U32_t(65280))) << 8) | ((u64(4278321152) & u64(U32_t(16711680))) >> 8) | ((u64(4278321152) & u64(U32_t(u64(4278190080)))) >> 24))))) {
				i32((U8_t((i32(interface_.num) + 1))))
			} else {
				0
			}))
		}
		available := i32(-1)
		for i := i32(0); i < 16; i++ {
			member := &socket.memberships[0] + i
			if !live_membership(member, interface_index(u32(member.ifindex))) {
				member.used = u8(0)
				if available < 0 {
					available = i
				}
				continue
			}
			mut __c2v_condition_13 := false
			mut __c2v_condition_14 := false
			__c2v_condition_14 = u32(member.ifindex) != linux_interface_index(interface_)
			__c2v_condition_13 = __c2v_condition_14
			if !__c2v_condition_13 {
				mut __c2v_condition_15 := false
				__c2v_condition_15 = !(if i32(member.group.@type) != i32(group.@type) {
					0
				} else {
					(if i32((*(&member.group)).@type) == Lwip_ip_addr_type.ipaddr_type_v6 {
						(((member.group.u_addr.ip6.addr[0] == group.u_addr.ip6.addr[0]) && (member.group.u_addr.ip6.addr[1] == group.u_addr.ip6.addr[1]) && (member.group.u_addr.ip6.addr[2] == group.u_addr.ip6.addr[2]) && (member.group.u_addr.ip6.addr[3] == group.u_addr.ip6.addr[3])) && (i32(member.group.u_addr.ip6.zone) == i32(group.u_addr.ip6.zone)))
					} else {
						(member.group.u_addr.ip4.addr == group.u_addr.ip4.addr)
					})
				})
				__c2v_condition_13 = __c2v_condition_15
			}
			if __c2v_condition_13 {
				continue
			}
			if join {
				return 98
			}
			error_ := leave_membership(member, interface_)
			if i32(error_) != Err_enum_t.err_ok {
				return linux_error(error_)
			}
			member.used = u8(0)
			return 0
		}
		if !join {
			return 99
		}
		if available < 0 {
			return 105
		}
		// Native group use is u8_t and also includes other protocol owners.
		//     *Reject saturation before lwIP increments and wraps the shared count.

		if (usize((&group)) != usize((voidptr(0)))) && (i32((*(&group)).@type) == Lwip_ip_addr_type.ipaddr_type_v6) {
			existing := C.mld6_lookfor_group(interface_, (&group.u_addr.ip6))
			if !(usize(existing) == 0) && i32(existing.use) == 255 {
				return 105
			}
		} else {
			existing := C.igmp_lookfor_group(interface_, (&group.u_addr.ip4))
			if !automatic_allhosts(&group) && !(usize(existing) == 0) && i32(existing.use) == 255 {
				return 105
			}
		}
		error_ := Err_t(0)
		if automatic_allhosts(&group) {
			if is_null(C.igmp_lookfor_group(interface_, (&group.u_addr.ip4))) {
				return 12
			}
			error_ = Err_t(Err_enum_t.err_ok)
		} else {
			error_ = Err_t(if (usize((&group)) != usize((voidptr(0)))) && (i32((*(&group)).@type) == Lwip_ip_addr_type.ipaddr_type_v6) {
				i32(C.mld6_joingroup_netif(interface_, (&group.u_addr.ip6)))
			} else {
				i32(C.igmp_joingroup_netif(interface_, (&group.u_addr.ip4)))
			})
		}
		if i32(error_) != Err_enum_t.err_ok {
			return linux_error(error_)
		}
		member := &socket.memberships[0] + available
		for {
			for {
				member.group.@type = group.@type
				// while()
				break
			}
			if i32(group.@type) == Lwip_ip_addr_type.ipaddr_type_v6 {
				for {
					(&member.group.u_addr.ip6).addr[0] = (&group.u_addr.ip6).addr[0]
					(&member.group.u_addr.ip6).addr[1] = (&group.u_addr.ip6).addr[1]
					(&member.group.u_addr.ip6).addr[2] = (&group.u_addr.ip6).addr[2]
					(&member.group.u_addr.ip6).addr[3] = (&group.u_addr.ip6).addr[3]
					(*(&member.group.u_addr.ip6)).zone = (*(&group.u_addr.ip6)).zone
					// while()
					break
				}
			} else {
				(&member.group.u_addr.ip4).addr = (&group.u_addr.ip4).addr
				for {
					member.group.u_addr.ip6.addr[3] = U32_t(0)
					member.group.u_addr.ip6.addr[2] = U32_t(0)
					member.group.u_addr.ip6.addr[1] = U32_t(0)
					member.group.u_addr.ip6.zone = U8_t(0)
					// while()
					break
				}
			}
			// while()
			break
		}
		member.ifindex = u8(linux_interface_index(interface_))
		member.epoch = interface_epoch(interface_)
		member.used = u8(1)
		return 0
	}
}

@[export: 'vinix_socket_multicast_interface']
pub fn vinix_socket_multicast_interface(socket &Vinix_socket, family i32, index u32, interface_address u32) i32 {
	unsafe {
		if (usize(socket) == 0) || (usize(socket.udp) == 0) {
			return 92
		}
		if family == 10 && socket.family != 10 {
			return 92
		}
		interface_ := if index || interface_address {
			multicast_interface(index, interface_address)
		} else {
			&C.netif(nil)
		}
		if (index || interface_address) && (usize(interface_) == 0) {
			return 19
		}
		if family == 10 {
			socket.multicast_if6 = if interface_ {
				linux_interface_index(interface_)
			} else {
				u32(0)
			}
		} else {
			socket.multicast_if4 = if interface_ {
				linux_interface_index(interface_)
			} else {
				u32(0)
			}
			socket.multicast_addr4 = interface_address
		}
		return 0
	}
}

@[export: 'vinix_net_ipv6_address']
pub fn vinix_net_ipv6_address(index u32, slot u32, endpoint &C.vinix_net_endpoint, state &u32, valid_life &u32, preferred_life &u32) i32 {
	unsafe {
		interface_ := interface_index(index)
		if (usize(interface_) == 0) || slot >= u32(6) {
			return 0
		}
		ip := C.ip_addr{}
		for {
			ip.@type = U8_t(Lwip_ip_addr_type.ipaddr_type_v6)
			// while()
			break
		}
		for {
			(&ip.u_addr.ip6).addr[0] = (&C.ip6_addr((&interface_.ip6_addr[slot].u_addr.ip6))).addr[0]
			(&ip.u_addr.ip6).addr[1] = (&C.ip6_addr((&interface_.ip6_addr[slot].u_addr.ip6))).addr[1]
			(&ip.u_addr.ip6).addr[2] = (&C.ip6_addr((&interface_.ip6_addr[slot].u_addr.ip6))).addr[2]
			(&ip.u_addr.ip6).addr[3] = (&C.ip6_addr((&interface_.ip6_addr[slot].u_addr.ip6))).addr[3]
			(*(&ip.u_addr.ip6)).zone = (*(&C.ip6_addr((&interface_.ip6_addr[slot].u_addr.ip6)))).zone
			// while()
			break
		}
		endpoint_from_ip(10, &ip, u16(0), endpoint)
		if state {
			*state = u32(interface_.ip6_addr_state[slot])
		}
		if valid_life {
			*valid_life = (if usize(interface_) != usize((voidptr(0))) {
				interface_.ip6_addr_valid_life[slot]
			} else {
				U32_t(0)
			})
		}
		if preferred_life {
			*preferred_life = (if usize(interface_) != usize((voidptr(0))) {
				interface_.ip6_addr_pref_life[slot]
			} else {
				U32_t(0)
			})
		}
		return 1
	}
}

pub fn family_set_option(socket &Vinix_socket, level i32, option i32, value i32) i32 {
	unsafe {
		pcb := socket_ip_pcb(socket)
		if level == 0 {
			if option == 2 {
				if value < -1 || value == 0 || value > 255 {
					return 22
				}
				if value == -1 {
					value = 64
				}
				socket.hops4 = value
				if !(usize(pcb) == 0) && !((usize((&pcb.remote_ip)) != usize((voidptr(0)))) && (i32((*(&pcb.remote_ip)).@type) == Lwip_ip_addr_type.ipaddr_type_v6)) {
					pcb.ttl = u8(value)
				}
				return 0
			}
			if usize(socket.udp) == 0 {
				return 92
			}
			if value < 0 || value > 255 {
				return 22
			}
			if option == 33 {
				socket.multicast_hops4 = value
			} else if option == 34 {
				socket.multicast_loop4 = value != 0
			} else {
				return 92
			}
			return 0
		}
		if socket.family != 10 {
			return 92
		}
		if option == 26 {
			// IPV6_V6ONLY: the family is settled before binding.

			if value != 0 && value != 1 {
				return 22
			}
			if (usize(pcb) == 0) || socket.connected || socket.connecting || socket.listening || (if socket.tcp {
				i32(socket.tcp.local_port)
			} else {
				i32(socket.udp.local_port)
			}) {
				return 22
			}
			socket.v6only = value
			for {
				pcb.local_ip.@type = U8_t((if value {
					Lwip_ip_addr_type.ipaddr_type_v6
				} else {
					Lwip_ip_addr_type.ipaddr_type_any
				}))
				// while()
				break
			}
			for {
				pcb.remote_ip.@type = U8_t((if value {
					Lwip_ip_addr_type.ipaddr_type_v6
				} else {
					Lwip_ip_addr_type.ipaddr_type_any
				}))
				// while()
				break
			}
			return 0
		}
		if option == 16 {
			// IPV6_UNICAST_HOPS

			if value < -1 || value > 255 {
				return 22
			}
			socket.hops6 = if value == -1 { 64 } else { value }
			if !(usize(pcb) == 0) && ((usize((&pcb.remote_ip)) != usize((voidptr(0)))) && (i32((*(&pcb.remote_ip)).@type) == Lwip_ip_addr_type.ipaddr_type_v6)) {
				pcb.ttl = u8(socket.hops6)
			}
			return 0
		}
		if usize(socket.udp) == 0 {
			return 92
		}
		if option == 17 {
			// IPV6_MULTICAST_IF

			if value < 0 {
				return 19
			}
			return vinix_socket_multicast_interface(socket, 10, u32(value), u32(0))
		}
		if option == 18 {
			// IPV6_MULTICAST_HOPS

			if value < -1 || value > 255 {
				return 22
			}
			socket.multicast_hops6 = if value == -1 { 1 } else { value }
			return 0
		}
		if option == 19 {
			// IPV6_MULTICAST_LOOP

			if value != 0 && value != 1 {
				return 22
			}
			socket.multicast_loop6 = value
			return 0
		}
		return 92
	}
}

pub fn family_get_option(socket &Vinix_socket, level i32, option i32, value &i32) i32 {
	unsafe {
		if level == 0 {
			if option == 2 {
				*value = socket.hops4
				return 0
			}
			if usize(socket.udp) == 0 {
				return 92
			}
			if option == 32 {
				*value = i32(socket.multicast_addr4)
			} else if option == 33 {
				*value = socket.multicast_hops4
			} else if option == 34 {
				*value = socket.multicast_loop4
			} else {
				return 92
			}
			return 0
		}
		if socket.family != 10 {
			return 92
		}
		if option == 24 {
			// IPV6_MTU: connected path's discovered MTU.

			pcb := socket_ip_pcb(socket)
			if !socket.connected || (usize(pcb) == 0) || !((usize((&pcb.remote_ip)) != usize((voidptr(0)))) && (i32((*(&pcb.remote_ip)).@type) == Lwip_ip_addr_type.ipaddr_type_v6)) {
				return 107
			}
			interface_ := C.ip6_route((&pcb.local_ip.u_addr.ip6), (&pcb.remote_ip.u_addr.ip6))
			if usize(interface_) == 0 {
				return 101
			}
			*value = i32(C.nd6_get_destination_mtu((&pcb.remote_ip.u_addr.ip6), interface_))
			return 0
		}
		if option == 26 {
			*value = socket.v6only
			return 0
		}
		if option == 16 {
			*value = socket.hops6
			return 0
		}
		if usize(socket.udp) == 0 {
			return 92
		}
		if option == 17 {
			*value = i32(socket.multicast_if6)
		} else if option == 18 {
			*value = socket.multicast_hops6
		} else if option == 19 {
			*value = socket.multicast_loop6
		} else {
			return 92
		}
		return 0
	}
}

// Family/managed multicast policy stays beside the raw lwIP bridge.

@[export: 'vinix_net_core_physical']
pub fn physical() voidptr {
	unsafe { return &net_physical_netif
	 }
}

@[export: 'vinix_net_core_epoch']
pub fn epoch() u64 { return net_link_epoch }

fn is_null(p voidptr) bool { return usize(p) == 0 }

@[export: 'vinix_net_core_mac']
pub fn fixture_mac() voidptr { unsafe { return &net_active_mac[0] } }

@[export: 'vinix_net_core_accept_fn']
pub fn fixture_accept_fn() Tcp_accept_fn { return accept_callback }
