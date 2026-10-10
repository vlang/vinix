// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
//
// smcprobe: what the SMC of the Mac this runs on says about the keys the
// Vinix SMC driver reads -- whether each is there, its four-character type,
// its size, its attribute bits and its bytes now.
//
// It runs under macOS, as an ordinary user, and only reads: through the
// AppleSMC user client it sends the "describe a key" (9), "read a key" (5)
// and "key by number" (8) commands and no other. It has no code that writes
// a key.
//
//	tools/apple-smc/smcprobe            the keys kernel/apple/smc reads
//	tools/apple-smc/smcprobe B0RM TB0T  these keys
//	tools/apple-smc/smcprobe --all      every key the SMC lists
//
// Bytes are printed in the order the SMC holds them. See README.md for what
// to compare the output with.
module main

import os

#flag -framework IOKit
#flag -framework CoreFoundation
#include <IOKit/IOKitLib.h>

fn C.IOServiceMatching(name &char) voidptr
fn C.IOServiceGetMatchingService(port u32, matching voidptr) u32
fn C.IOServiceOpen(service u32, task u32, kind u32, connection &u32) i32
fn C.IOServiceClose(connection u32) i32
fn C.IOObjectRelease(object u32) i32
fn C.IOConnectCallStructMethod(connection u32, selector u32, input voidptr, input_size usize, output voidptr, output_size &usize) i32
fn C.mach_task_self() u32

// The user client's one structure, by the offsets of the fields used: the
// key at 0, a key's size, type and attributes at 28, 32 and 36, the result
// at 40, the command at 42, a number at 44 and the value's bytes at 48.
const param_size = 80
const selector_keys = u32(2)
const command_read = u8(5)
const command_by_number = u8(8)
const command_describe = u8(9)

// The keys the driver looks for, in the order of its own tables
// (kernel/apple/smc/core/supply.v), and the two the device nodes are made of.
const driver_keys = ['BUIC', 'BRSC', 'B0AV', 'B0AC', 'B0AP', 'B0RM', 'B0FC', 'B0DC', 'B0CT', 'B0TE',
	'B0TF', 'BITV', 'BSFC', 'BCF0', 'BMDN', 'BMSN', 'CH0R', 'CHCE', 'CHCC', 'CHNC', 'CHSC', 'CHIS',
	'CHWA', 'AC-i', 'TH0x', 'TB0T', 'TCHP', 'TW0P', 'FNum', 'F0Ac', 'F0Mn', 'F0Mx', 'F1Ac', 'F1Mn',
	'F1Mx']

fn put32(mut buffer []u8, at int, value u32) {
	buffer[at] = u8(value)
	buffer[at + 1] = u8(value >> 8)
	buffer[at + 2] = u8(value >> 16)
	buffer[at + 3] = u8(value >> 24)
}

fn get32(buffer []u8, at int) u32 {
	return u32(buffer[at]) | (u32(buffer[at + 1]) << 8) | (u32(buffer[at + 2]) << 16) | (u32(buffer[at + 3]) << 24)
}

fn call(connection u32, input []u8) ?[]u8 {
	mut output := []u8{len: param_size}
	mut size := usize(param_size)
	if C.IOConnectCallStructMethod(connection, selector_keys, input.data, usize(param_size), output.data,
		&size) != 0 {
		return none
	}
	return output
}

fn fourcc(value u32) string {
	mut text := []u8{len: 4}
	for i in 0 .. 4 {
		c := u8(value >> (24 - 8 * i))
		text[i] = if c >= 32 && c < 127 { c } else { `?` }
	}
	return text.bytestr()
}

fn code(name string) u32 {
	return (u32(name[0]) << 24) | (u32(name[1]) << 16) | (u32(name[2]) << 8) | u32(name[3])
}

struct Info {
	size  u32
	kind  u32
	flags u8
}

fn describe(connection u32, key u32) ?Info {
	mut input := []u8{len: param_size}
	put32(mut input, 0, key)
	input[42] = command_describe
	output := call(connection, input)?
	if output[40] != 0 {
		return none
	}
	return Info{
		size:  get32(output, 28)
		kind:  get32(output, 32)
		flags: output[36]
	}
}

fn read_key(connection u32, key u32, size u32) ?[]u8 {
	mut input := []u8{len: param_size}
	put32(mut input, 0, key)
	put32(mut input, 28, size)
	input[42] = command_read
	output := call(connection, input)?
	if output[40] != 0 {
		return none
	}
	count := if size > 32 { 32 } else { int(size) }
	return output[48..48 + count].clone()
}

fn key_numbered(connection u32, number u32) ?u32 {
	mut input := []u8{len: param_size}
	input[42] = command_by_number
	put32(mut input, 44, number)
	output := call(connection, input)?
	if output[40] != 0 {
		return none
	}
	return get32(output, 0)
}

fn show(connection u32, key u32) {
	info := describe(connection, key) or {
		println('${fourcc(key)}  absent')
		return
	}
	mut line := '${fourcc(key)}  type "${fourcc(info.kind)}" size ${info.size} flags 0x${info.flags.hex()}'
	if info.flags & 0x80 != 0 {
		if value := read_key(connection, key, info.size) {
			line += '  ' + value.hex()
		} else {
			line += '  (read refused)'
		}
	}
	println(line)
}

fn main() {
	service := C.IOServiceGetMatchingService(0, C.IOServiceMatching(c'AppleSMC'))
	if service == 0 {
		eprintln('smcprobe: this machine has no AppleSMC service')
		exit(1)
	}
	mut connection := u32(0)
	if C.IOServiceOpen(service, C.mach_task_self(), 0, &connection) != 0 {
		eprintln('smcprobe: the AppleSMC user client would not open')
		exit(1)
	}
	C.IOObjectRelease(service)
	defer {
		C.IOServiceClose(connection)
	}
	wanted := os.args[1..]
	if wanted.len == 1 && wanted[0] == '--all' {
		count_bytes := read_key(connection, code('#KEY'), 4) or {
			eprintln('smcprobe: #KEY, the number of keys, could not be read')
			exit(1)
		}
		// The one number the SMC holds highest byte first.
		count := (u32(count_bytes[0]) << 24) | (u32(count_bytes[1]) << 16) | (u32(count_bytes[2]) << 8) | u32(count_bytes[3])
		println('# ${count} keys')
		for number in u32(0) .. count {
			key := key_numbered(connection, number) or { continue }
			show(connection, key)
		}
		return
	}
	names := if wanted.len == 0 { driver_keys } else { wanted }
	for name in names {
		if name.len != 4 {
			eprintln('smcprobe: "${name}" is not a key: keys are four characters')
			exit(2)
		}
		show(connection, code(name))
	}
}
