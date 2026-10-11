// SPDX-License-Identifier: GPL-2.0-or-later
module systemhost

import net
import time

fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
fn C.recvfrom(i32, voidptr, usize, i32, voidptr, &u32) i32

pub struct Echo {
pub:
	address string
mut:
	stop       i32
	tcp        &net.TcpListener = unsafe { nil }
	udp        &net.UdpConn     = unsafe { nil }
	tcp_worker thread
	udp_worker thread
}

fn (e &Echo) running() bool {
	return unsafe { C.__atomic_load_n(&e.stop, C.__ATOMIC_RELAXED) } == 0
}

fn tcp_echo(mut e Echo) {
	for e.running() {
		mut connection := e.tcp.accept() or { continue }
		connection.set_read_timeout(100 * time.millisecond)
		connection.set_write_timeout(100 * time.millisecond)
		mut data := []u8{len: 65536}
		for e.running() {
			n := connection.read(mut data) or {
				if err == net.err_timed_out { continue }
				break
			}
			mut sent := 0
			for sent < n && e.running() {
				count := connection.write(data[sent..n]) or {
					if err == net.err_timed_out { continue }
					break
				}
				if count == 0 { break }
				sent += count
			}
			break
		}
		connection.close() or {}
	}
}

fn udp_echo(mut e Echo) {
	for e.running() {
		mut data := []u8{len: 65536}
		e.udp.wait_for_read() or { continue }
		mut peer := net.new_ip6(0, [16]u8{})
		mut size := u32(sizeof(net.Addr))
		// net.UdpConn.read treats a zero-byte datagram as EOF. recvfrom's zero
		// result is a valid empty packet and must be echoed like any other packet.
		n := C.recvfrom(e.udp.sock.handle, data.data, usize(data.len), 0, &peer, &size)
		if n < 0 { continue }
		e.udp.write_to(peer, data[..n]) or {}
	}
}

pub fn start_echo(address string) !&Echo {
	mut tcp := net.listen_tcp(.ip6, address, backlog: 4)!
	tcp.set_accept_timeout(100 * time.millisecond)
	endpoint := tcp.addr()!.str()
	mut udp := net.listen_udp(endpoint) or {
		tcp.close() or {}
		return err
	}
	udp.set_read_timeout(100 * time.millisecond)
	udp.set_write_timeout(100 * time.millisecond)
	mut e := &Echo{ address: endpoint, tcp: tcp, udp: udp }
	e.tcp_worker = spawn tcp_echo(mut e)
	e.udp_worker = spawn udp_echo(mut e)
	return e
}

pub fn (mut e Echo) close() {
	unsafe { C.__atomic_store_n(&e.stop, i32(1), C.__ATOMIC_RELAXED) }
	e.tcp_worker.wait()
	e.udp_worker.wait()
	e.tcp.close() or {}
	e.udp.close() or {}
}
