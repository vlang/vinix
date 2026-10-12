// SPDX-License-Identifier: ISC
@[has_globals]
module main

import os
import time
import term.termios

#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <signal.h>

fn C.open(&char, int, ...int) int
fn C.close(int) int
fn C.ioctl(int, u64, ...voidptr) int
fn C.read(int, voidptr, usize) isize
fn C.isatty(int) int
fn C.perror(&char)
fn C.signal(int, fn (int)) voidptr
fn C.atexit(fn ()) int

__global (
	saved_terminal   termios.Termios
	terminal_changed bool
)

fn restore_terminal() {
	if terminal_changed {
		termios.tcsetattr(0, C.TCSANOW, mut saved_terminal)
		terminal_changed = false
	}
}

fn interrupted(_ int) {
	restore_terminal()
	exit(130)
}

struct SecretByte {
mut:
	volatile value u8
}

@[noinline]
fn wipe(data voidptr, length u64) {
	for i in u64(0) .. length {
		unsafe { (&SecretByte(u64(data) + i)).value = 0 }
	}
}

fn word(data &u8, offset int) u32 {
	unsafe {
		return u32(data[offset]) | u32(data[offset + 1]) << 8 | u32(data[offset + 2]) << 16 | u32(data[offset + 3]) << 24
	}
}

fn set_word(data &u8, offset int, value u32) {
	for i in 0 .. 4 {
		unsafe { data[offset + i] = u8(value >> (8 * i)) }
	}
}

fn checked(fd int, request usize, data voidptr) {
	if C.ioctl(fd, u64(request), data) < 0 {
		C.perror(c'wifi-ctl')
		exit(1)
	}
}

fn status(fd int) u32 {
	mut data := [256]u8{}
	checked(fd, 0x5700, unsafe { &data[0] })
	states := ['idle', 'starting', 'creating peer', 'authenticating', 'associating', 'configuring',
		'WPA2 handshake', 'connected', 'failed']
	state := word(unsafe { &data[0] }, 176)
	label := if state < u32(states.len) { states[state] } else { 'unknown' }
	println('QCA9377: ${label}; radio=${word(unsafe { &data[0] }, 160)}, startup stage=${word(unsafe { &data[0] }, 12)}, driver error=${i32(word(unsafe { &data[0] }, 4))}, scan error=${i32(word(unsafe { &data[0] }, 172))}, connection error=${i32(word(unsafe { &data[0] }, 200))}')
	println('TX queued/completed=${word(unsafe { &data[0] }, 184)}/${word(unsafe { &data[0] }, 188)}, RX received/dropped=${word(unsafe { &data[0] }, 192)}/${word(unsafe { &data[0] }, 196)}')
	return state
}

fn networks(fd int, scan bool) {
	if scan { checked(fd, 0x5706, unsafe { nil }) }
	mut data := [1552]u8{}
	for _ in 0 .. 260 {
		checked(fd, 0x5707, unsafe { &data[0] })
		if word(unsafe { &data[0] }, 8) == 0 { break }
		time.sleep(100 * time.millisecond)
	}
	error := i32(word(unsafe { &data[0] }, 12))
	if error != 0 || word(unsafe { &data[0] }, 8) != 0 {
		eprintln('Scan failed: ${error}; inspect /proc/bootlog')
		exit(1)
	}
	count := word(unsafe { &data[0] }, 4)
	if word(unsafe { &data[0] }, 0) != 1 || count > 32 {
		eprintln('Invalid network response')
		exit(1)
	}
	for i in u32(0) .. count {
		offset := int(16 + i * 48)
		length := int(data[offset])
		if length > 32 { continue }
		// Escape control bytes supplied by APs before printing to a terminal.
		mut name := ''
		for j in 0 .. length {
			b := data[offset + 16 + j]
			name += if b >= 32 && b < 127 { b.ascii_str() } else { '?' }
		}
		channel := u16(data[offset + 2]) | u16(data[offset + 3]) << 8
		rssi := i16(u16(data[offset + 4]) | u16(data[offset + 5]) << 8)
		println('${channel:2}  ${rssi:4} dBm  ${if data[offset + 1] == 1 {
			'secured'
		} else {
			'open   '
		}}  ${name}')
	}
}

fn join(fd int, ssid string, open bool) {
	if ssid.len == 0 || ssid.len > 32 {
		eprintln('SSID must contain 1-32 bytes')
		exit(1)
	}
	mut data := [104]u8{}
	defer {
		wipe(unsafe { &data[0] }, 104)
		restore_terminal()
	}
	set_word(unsafe { &data[0] }, 0, u32(ssid.len))
	for i in 0 .. ssid.len { data[8 + i] = ssid[i] }
	if !open {
		if C.isatty(0) != 0 {
			if termios.tcgetattr(0, mut saved_terminal) != 0 {
				eprintln('Cannot read terminal settings')
				exit(1)
			}
			mut hidden := saved_terminal
			hidden.c_lflag &= termios.invert(termios.flag(int(C.ECHO)))
			if termios.tcsetattr(0, C.TCSANOW, mut hidden) != 0 {
				eprintln('Cannot hide password')
				exit(1)
			}
			terminal_changed = true
			print('WPA2 passphrase: ')
			flush_stdout()
		}
		mut length := 0
		for {
			mut byte := u8(0)
			if C.read(0, unsafe { &byte }, 1) != 1 || byte == 10 || byte == 13 { break }
			if length >= 63 {
				wipe(unsafe { &data[0] }, 104)
				restore_terminal()
				eprintln('Passphrase exceeds 63 bytes')
				exit(1)
			}
			data[40 + length] = byte
			length++
		}
		restore_terminal()
		if C.isatty(0) != 0 { println('') }
		if length < 8 {
			eprintln('Passphrase must contain 8-63 bytes')
			exit(1)
		}
		set_word(unsafe { &data[0] }, 4, u32(length))
	}
	checked(fd, 0x5703, unsafe { &data[0] })
	wipe(unsafe { &data[0] }, 104)
	for _ in 0 .. 160 {
		mut state := [256]u8{}
		checked(fd, 0x5700, unsafe { &state[0] })
		s := word(unsafe { &state[0] }, 176)
		if s == 7 {
			println('Connected; DHCP requested. Check ip addr.')
			return
		}
		if s == 8 {
			_ = status(fd)
			exit(1)
		}
		time.sleep(100 * time.millisecond)
	}
	eprintln('Connection timed out; inspect /proc/bootlog')
	exit(1)
}

fn main() {
	if os.args.len < 2 {
		println('Usage: wifi-ctl status | boot | on | off | scan | networks | join SSID | join-open SSID')
		return
	}
	C.atexit(restore_terminal)
	C.signal(C.SIGINT, interrupted)
	C.signal(C.SIGTERM, interrupted)
	fd := C.open(c'/dev/wlan0', 2)
	if fd < 0 {
		C.perror(c'/dev/wlan0')
		exit(1)
	}
	defer { C.close(fd) }
	match os.args[1] {
		'status' { _ = status(fd) }
		'boot' {
			checked(fd, 0x5702, unsafe { nil })
			_ = status(fd)
		}
		'on', 'off' {
			mut radio := u32(if os.args[1] == 'on' { 1 } else { 0 })
			checked(fd, 0x5705, unsafe { &radio })
		}
		'scan', 'networks' { networks(fd, os.args[1] == 'scan') }
		'join', 'join-open' {
			if os.args.len != 3 {
				eprintln('Expected one SSID; passphrases are read from the terminal or stdin')
				exit(1)
			}
			join(fd, os.args[2], os.args[1] == 'join-open')
		}
		else {
			eprintln('Unknown command')
			exit(1)
		}
	}
}
