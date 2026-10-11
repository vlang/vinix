// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What the scenarios run as an account. Each probe tries one thing and
// prints what happened in a line the scenario can compare: `ok ...` or
// `errno <number>`.
module main

import os

#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/un.h>

fn C.getgroups(count int, list &u32) int
fn C.getcwd(buffer &char, size usize) &char
fn C.socket(domain int, kind int, protocol int) int
fn C.connect(fd int, address voidptr, length u32) int

struct C.sockaddr_un {
mut:
	sun_family u16
	sun_path   [108]char
}

fn status_field(name string) string {
	for line in read_text('/proc/self/status').split_into_lines() {
		if line.starts_with(name + ':') {
			return line.all_after(':').trim_space()
		}
	}
	return '?'
}

fn probe_ids() int {
	mut groups := []u32{len: 64}
	count := C.getgroups(64, unsafe { &groups[0] })
	mut list := []string{}
	for i in 0 .. count {
		list << groups[i].str()
	}
	list.sort()
	mut cwd := []u8{len: 256}
	C.getcwd(&char(cwd.data), 256)
	println('uid=${C.getuid()} euid=${C.geteuid()} gid=${C.getgid()} groups=${list.join(',')} caps=${status_field('CapEff')} permitted=${status_field('CapPrm')} bounding=${status_field('CapBnd')} nnp=${status_field('NoNewPrivs')} home=${os.getenv('HOME')} runtime=${os.getenv('XDG_RUNTIME_DIR')} user=${os.getenv('USER')} cwd=${unsafe { cstring_to_vstring(&char(cwd.data)) }} active=${read_text('/run/vinix/session/active').trim_space()}')
	return 0
}

fn report(result int) int {
	if result >= 0 {
		println('ok ${result}')
		return 0
	}
	println('errno ${C.errno}')
	return 1
}

fn probe_read(path string) int {
	fd := C.open(&char(path.str), C.O_RDONLY)
	if fd < 0 {
		return report(-1)
	}
	mut buffer := []u8{len: 256}
	got := int(C.read(fd, buffer.data, 256))
	C.close(fd)
	return report(got)
}

fn probe_write(path string) int {
	fd := C.open(&char(path.str), C.O_WRONLY | C.O_CREAT | C.O_APPEND, 0o644)
	if fd < 0 {
		return report(-1)
	}
	put := int(C.write(fd, c'x', 1))
	C.close(fd)
	return report(put)
}

fn probe_list(path string) int {
	entries := os.ls(path) or {
		println('errno ${C.errno}')
		return 1
	}
	println('ok ${entries.len}')
	return 0
}

// Connect to the service and send bytes that are not a request.
fn probe_garbage(kind string) int {
	path := '/run/vinix/auth.sock'
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	mut address := C.sockaddr_un{}
	address.sun_family = u16(C.AF_UNIX)
	unsafe { vmemcpy(&address.sun_path[0], path.str, path.len) }
	if C.connect(fd, voidptr(&address), u32(sizeof(C.sockaddr_un))) != 0 {
		return report(-1)
	}
	mut data := []u8{}
	match kind {
		'noise' {
			for i in 0 .. 5000 {
				data << u8(i * 31 + 7)
			}
		}
		'huge-count' {
			data = [u8(0x56), 0x41, 0x55, 0x54, 1, 0, 5, 0, 0xff, 0xff, 0xff, 0x7f]
		}
		'huge-field' {
			data = [u8(0x56), 0x41, 0x55, 0x54, 1, 0, 5, 0, 1, 0, 0, 0, 0xff, 0xff, 0xff, 0x7f]
		}
		'half' {
			data = [u8(0x56), 0x41, 0x55, 0x54, 1, 0]
		}
		else {}
	}
	C.write(fd, data.data, usize(data.len))
	if kind == 'hold' {
		// Say nothing, stay connected a while, and leave.
		C.usleep(4_000_000)
		C.close(fd)
		println('ok held')
		return 0
	}
	mut reply := []u8{len: 64}
	got := int(C.read(fd, reply.data, 64))
	C.close(fd)
	println('ok ${got}')
	return 0
}

fn run_probe(what []string) int {
	if what.len == 0 {
		return 2
	}
	match what[0] {
		'ids' {
			return probe_ids()
		}
		'read' {
			return probe_read(what[1])
		}
		'write' {
			return probe_write(what[1])
		}
		'list' {
			return probe_list(what[1])
		}
		'say' {
			println('${what[1]} as uid=${C.geteuid()}')
			return 0
		}
		'who' {
			println('asked by ${os.getenv('VINIX_AUTH_USER')} (${os.getenv('VINIX_AUTH_UID')}) as uid=${C.geteuid()} path=${os.getenv('PATH')} home=${os.getenv('HOME')}')
			return 0
		}
		'input' {
			mut buffer := []u8{len: 256}
			got := int(C.read(0, buffer.data, 256))
			println('input=${buffer[..if got > 0 { got } else { 0 }].bytestr()}')
			return 0
		}
		'sleep' {
			C.usleep(u32(what[1].int()) * 1_000_000)
			return 0
		}
		'garbage' {
			return probe_garbage(what[1])
		}
		'sweep' {
			return probe_sweep(what[1..])
		}
		else {
			return 2
		}
	}
}
