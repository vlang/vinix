// SPDX-License-Identifier: GPL-2.0-or-later
module audiopcm

import os

pub struct Client {
mut:
	fd int = -1
}

pub fn connect() !Client {
	mut capability := environment()!
	defer { capability.close() }
	id := os.getenv('VINIX_APP_ID')
	defer { unsafe { id.free() } }
	return connect_capability(capability, id)
}

fn endpoint_connection(capability Capability, uid u32) !int {
	if !capability.valid_binding() || !exact_endpoint(capability, uid) { return error('application has no admitted audio output') }
	location := address(capability.path)!
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return error('cannot create audio connection') }
	mut accepted := false
	defer { if !accepted { C.close(fd) } }
	nonblocking(fd)!
	if C.vinix_pcm_connect(fd, &location, u32(sizeof(C.vinix_pcm_address))) != 0 {
		if C.errno !in [C.EINPROGRESS, C.EAGAIN] { return error('audio worker unavailable') }
		ready(fd, 4, -1, 5000)!
		mut failure := i32(0)
		mut length := u32(sizeof(i32))
		if C.getsockopt(fd, C.SOL_SOCKET, C.SO_ERROR, &failure, &length) != 0 || failure != 0 { return error('audio worker unavailable') }
	}
	identity := peer(fd)!
	if identity.uid != uid { return error('audio worker belongs to another account') }
	$if linux { if identity.pid != capability.worker { return error('audio worker identity changed') } }
	if !exact_endpoint(capability, uid) { return error('audio endpoint changed during connection') }
	accepted = true
	return fd
}

pub fn connect_capability(capability Capability, id string) !Client {
	if id.len == 0 || id.len > 128 { return error('application has no admitted audio output') }
	fd := endpoint_connection(capability, u32(C.geteuid()))!
	mut accepted := false
	defer { if !accepted { C.close(fd) } }
	write_exact(fd, c'VPCM0001', 8, -1)!
	size := u8(id.len)
	write_exact(fd, &size, 1, -1)!
	write_exact(fd, id.str, id.len, -1)!
	mut number := [8]u8{}
	for index in 0 .. 8 { number[index] = u8(capability.generation >> (index * 8)) }
	write_exact(fd, &number[0], 8, -1)!
	write_exact(fd, capability.manifest.str, 64, -1)!
	mut answer := u8(1)
	read_exact(fd, &answer, 1, -1)!
	if answer != 0 { return error('audio output refused') }
	accepted = true
	return Client{ fd: fd }
}

pub fn (mut client Client) write(bytes []u8) ! {
	if client.fd < 0 || bytes.len == 0 || bytes.len > chunk_limit || bytes.len % 4 != 0 { return error('audio requires 1..4096 bytes of S16LE stereo frames') }
	client.frame(bytes.data, bytes.len) or { client.close(); return err }
}

// A zero-length frame drains the hardware queue; it does not close the stream.
pub fn (mut client Client) drain() ! {
	if client.fd < 0 { return error('audio stream is closed') }
	client.frame(unsafe { nil }, 0) or { client.close(); return err }
}

fn (mut client Client) frame(bytes voidptr, length int) ! {
	header := [u8(length), u8(length >> 8), u8(length >> 16), u8(length >> 24)]!
	write_exact(client.fd, &header[0], 4, -1)!
	if length > 0 { write_exact(client.fd, bytes, length, -1)! }
	mut answer := u8(1)
	read_exact(client.fd, &answer, 1, -1)!
	if answer != 0 { return error('audio output refused or its seat is inactive') }
}

pub fn (mut client Client) close() {
	if client.fd >= 0 { C.close(client.fd) }
	client = Client{}
}
