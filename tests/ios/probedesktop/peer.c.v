// SPDX-License-Identifier: GPL-2.0-or-later
// A bounded VAPP v10 peer for diagnostics, without a compositor or input device.
module probedesktop

import encoding.binary
import os
import time

#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <sys/wait.h>
#include <stdio.h>

struct C.pollfd {
mut:
	fd i32
	events i16
	revents i16
}
fn C.pipe(&i32) i32
fn C.close(i32) i32
fn C.fcntl(i32, i32, ...int) i32
fn C.poll(&C.pollfd, usize, i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.fork() i32
fn C.execv(&char, &&char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.kill(i32, i32) i32
fn C.fflush(voidptr) i32

pub struct Config {
pub:
	width int = 1024
	height int = 768
	reply_ms int = 30000
	session_ms int = 10000
}

pub struct Observation {
pub mut:
	handshake bool
	builds int
	polls int
	nodes int
	images int
	closed bool
	forced bool
	wait_status int
	stop string
}

struct Peer {
	request i32
	response i32
	config Config
mut:
	state []u8 = []u8{len: 116}
}

fn transfer(fd i32, mut data []u8, writing bool, deadline i64) ! {
	mut offset := 0
	for offset < data.len {
		left := deadline - time.sys_mono_now()
		if left <= 0 { return error('desktop reply deadline') }
		mut descriptor := C.pollfd{fd: fd, events: i16(if writing { C.POLLOUT } else { C.POLLIN })}
		ready := C.poll(&descriptor, 1, int((left + 999999) / 1000000))
		if ready < 0 && C.errno == C.EINTR { continue }
		if ready < 0 { return os.error_posix() }
		if ready == 0 { continue }
		// POLLHUP can accompany the last readable bytes: read before treating it as EOF.
		pointer := unsafe { voidptr(&data[offset]) }
		count := if writing { C.write(fd, pointer, usize(data.len - offset)) }
			else { C.read(fd, pointer, usize(data.len - offset)) }
		if count < 0 && C.errno in [C.EINTR, C.EAGAIN] { continue }
		if count < 0 { return os.error_posix() }
		if count == 0 { return error('desktop pipe closed') }
		offset += int(count)
	}
}

fn (mut peer Peer) reply(deadline i64) ![]u8 {
	mut header := []u8{len: 128}
	defer { unsafe { header.free() } }
	transfer(peer.response, mut header, false, deadline)!
	if header[..8] != [u8(0x50), 0x50, 0x41, 0x56, 10, 0, 0, 0] {
		return error('invalid desktop reply header')
	}
	length := binary.little_endian_u32_at(header, 124)
	if length > 1024 * 1024 { return error('desktop reply exceeds 1 MiB') }
	if binary.little_endian_u32_at(header, 56) !in [u32(1), 2] {
		return error('invalid desktop state')
	}
	unsafe { vmemcpy(peer.state.data, &header[8], 116) }
	mut payload := []u8{len: int(length)}
	transfer(peer.response, mut payload, false, deadline) or {
		unsafe { payload.free() }
		return err
	}
	return payload
}

fn (mut peer Peer) send(command u8) ![]u8 {
	mut header := []u8{len: 136}
	defer { unsafe { header.free() } }
	binary.little_endian_put_u32(mut header, 0x56415050)
	header[4] = 10
	header[5] = command
	binary.little_endian_put_u32_at(mut header, u32(peer.config.width), 8)
	binary.little_endian_put_u32_at(mut header, u32(peer.config.height), 12)
	unsafe { vmemcpy(&header[16], peer.state.data, 116) }
	deadline := time.sys_mono_now() + i64(peer.config.reply_ms) * 1000000
	transfer(peer.request, mut header, true, deadline)!
	return peer.reply(deadline)
}

struct Tree {
	data []u8
mut:
	offset int
	nodes int
	images int
}

fn (mut tree Tree) number() !u32 {
	if tree.offset + 4 > tree.data.len { return error('short desktop tree length') }
	value := binary.little_endian_u32_at(tree.data, tree.offset)
	tree.offset += 4
	return value
}

fn (mut tree Tree) node(depth int) ! {
	if depth > 32 || tree.offset + 274 > tree.data.len { return error('invalid desktop tree node') }
	if tree.data[tree.offset] > 4 { return error('invalid desktop tree kind') }
	tree.nodes++
	tree.offset += 274
	for field in 0 .. 12 {
		length := u64(tree.number()!)
		if u64(tree.offset) + length > u64(tree.data.len) { return error('short desktop tree string') }
		if field == 4 && length != 0 { tree.images++ }
		tree.offset += int(length)
	}
	if tree.number()! != 0 { return error('unexpected desktop tree menu') }
	count := tree.number()!
	if count > u32(tree.data.len / 274) { return error('invalid desktop tree children') }
	for _ in 0 .. int(count) { tree.node(depth + 1)! }
}

pub fn validate_tree(data []u8) !(int, int) {
	mut tree := Tree{data: data}
	tree.node(0)!
	if tree.offset != data.len { return error('trailing desktop tree bytes') }
	return tree.nodes, tree.images
}

fn (mut peer Peer) build(mut result Observation) ! {
	data := peer.send(1)!
	defer { unsafe { data.free() } }
	nodes, images := validate_tree(data)!
	result.nodes = nodes
	result.images = images
	result.builds++
	println('IOS-PROBE-DESKTOP: tree build=${result.builds} nodes=${nodes} images=${images} bytes=${data.len}')
	C.fflush(unsafe { nil })
}

fn (mut peer Peer) session(mut result Observation) ! {
	hello := peer.reply(time.sys_mono_now() + i64(peer.config.reply_ms) * 1000000)!
	defer { unsafe { hello.free() } }
	if hello.len != 0 { return error('nonempty desktop handshake') }
	result.handshake = true
	println('IOS-PROBE-DESKTOP: handshake version=10')
	C.fflush(unsafe { nil })
	peer.build(mut result)!
	deadline := time.sys_mono_now() + i64(peer.config.session_ms) * 1000000
	for time.sys_mono_now() < deadline {
		time.sleep(100 * time.millisecond)
		data := peer.send(4)!
		valid := data.len == 1 && data[0] <= 1
		dirty := valid && data[0] == 1
		unsafe { data.free() }
		if !valid { return error('invalid desktop poll reply') }
		result.polls++
		if dirty { peer.build(mut result)! }
	}
	bye := peer.send(6)!
	defer { unsafe { bye.free() } }
	if bye.len != 0 { return error('nonempty desktop close reply') }
	result.closed = true
	result.stop = 'session complete'
}

// The caller supplies guest-only cgroup setup. Protocol failures are observations,
// not successful app exits. Always close pipes, bound the exit wait and reap.
pub fn run(path string, args []string, setup fn (string) !, context string, config Config) !Observation {
	if config.width !in 1 .. 8193 || config.height !in 1 .. 8193
		|| config.reply_ms !in 1 .. 60001 || config.session_ms !in 0 .. 60001 {
		return error('invalid desktop probe configuration')
	}
	mut descriptors := [i32(-1), -1, -1, -1]!
	defer { for fd in descriptors { if fd >= 0 { C.close(fd) } } }
	if C.pipe(&descriptors[0]) != 0 || C.pipe(&descriptors[2]) != 0 { return os.error_posix() }
	for index in [1, 2] {
		flags := C.fcntl(descriptors[index], C.F_GETFL)
		if flags < 0 || C.fcntl(descriptors[index], C.F_SETFL, flags | C.O_NONBLOCK) < 0 {
			return os.error_posix()
		}
	}
	mut pointers := []&char{cap: args.len + 2}
	pointers << path.str
	for arg in args { pointers << arg.str }
	pointers << &char(unsafe { nil })
	defer { unsafe { pointers.free() } }
	C.fflush(unsafe { nil })
	child := C.fork()
	if child < 0 { return os.error_posix() }
	if child == 0 {
		C.close(descriptors[1])
		C.close(descriptors[2])
		setup(context) or { eprintln('IOS-NATIVE: FAIL desktop child setup: ' + err.msg()); exit(125) }
		os.setenv('VINIX_REQUEST_FD', descriptors[0].str(), true)
		os.setenv('VINIX_RESPONSE_FD', descriptors[3].str(), true)
		os.setenv('VINIX_IOS_EXIT_ON_CLOSE', '1', true)
		C.execv(path.str, pointers.data)
		exit(127)
	}
	for index in [0, 3] { C.close(descriptors[index]); descriptors[index] = -1 }
	// This diagnostic is single-threaded. Restore the supervisor's signal handler.
	previous := unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	defer { unsafe { C.signal(C.SIGPIPE, previous) } }
	mut peer := Peer{request: descriptors[1], response: descriptors[2], config: config}
	defer { unsafe { peer.state.free() } }
	mut result := Observation{}
	peer.session(mut result) or { result.stop = err.msg() }
	for index in [1, 2] { C.close(descriptors[index]); descriptors[index] = -1 }
	deadline := time.sys_mono_now() + i64(2000000000)
	mut status := i32(0)
	for {
		waited := C.waitpid(child, &status, C.WNOHANG)
		if waited == child { break }
		if waited < 0 && C.errno != C.EINTR { return os.error_posix() }
		if time.sys_mono_now() >= deadline {
			result.forced = true
			C.kill(child, C.SIGKILL)
			for C.waitpid(child, &status, 0) != child {
				if C.errno != C.EINTR { return os.error_posix() }
			}
			break
		}
		time.sleep(10 * time.millisecond)
	}
	result.wait_status = int(status)
	println('IOS-PROBE-DESKTOP: stop=${result.stop} handshake=${result.handshake} builds=${result.builds} polls=${result.polls} closed=${result.closed} supervisor_kill=${result.forced} wait=${result.wait_status}')
	C.fflush(unsafe { nil })
	return result
}
