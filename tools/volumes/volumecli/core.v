// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

#include <volume.h>

fn C.open(&char, i32, ...voidptr) i32
fn C.close(i32) i32
fn C.ioctl(i32, u64, ...voidptr) i32
fn C.printf(&char, ...voidptr) i32
fn C.perror(&char)
fn C.strcmp(&char, &char) i32

struct Request {
mut:
	version u32 = 1
	slot    u32
	offset  u64
	length  u64
	flags   u64
}

struct Status {
mut:
	version     u64
	bytes       u64
	sector      u64
	flags       u64
	reads       u64
	writes      u64
	read_bytes  u64
	write_bytes u64
	flushes     u64
	errors      u64
	last_error  u64
	disk_id     u64
	start       u64
	slot        u64
	generation  u64
	reserved    u64
}

fn decimal(text &char) ?u64 {
	mut value := u64(0)
	mut length := 0
	unsafe {
		for text[length] != 0 {
			if text[length] < `0` || text[length] > `9` { return none }
			digit := u64(u8(text[length]) - u8(`0`))
			if value > (u64(-1) - digit) / 10 { return none }
			value = value * 10 + digit
			length++
		}
	}
	if length == 0 { return none }
	return value
}

fn usage() i32 {
	C.printf(c'usage: vinix-volume status DEVICE\n       vinix-volume create DEVICE SLOT OFFSET_BYTES LENGTH_BYTES [ro]\n       vinix-volume grow DEVICE LENGTH_BYTES\n       vinix-volume remove DEVICE\n')
	return 2
}

pub fn run(argc i32, argv &&char) i32 {
	if argc < 3 { return usage() }
	mut request := u64(0)
	mut data := Request{}
	unsafe {
		if C.strcmp(argv[1], c'status') == 0 && argc == 3 {
			request = 0x56560004
		} else if C.strcmp(argv[1], c'remove') == 0 && argc == 3 {
			request = 0x56560003
		} else if C.strcmp(argv[1], c'grow') == 0 && argc == 4 {
			request = 0x56560002
			data.length = decimal(argv[3]) or { return usage() }
		} else if C.strcmp(argv[1], c'create') == 0 && (argc == 6 || argc == 7) {
			request = 0x56560001
			slot := decimal(argv[3]) or { return usage() }
			if slot >= 64 { return usage() }
			data.slot = u32(slot)
			data.offset = decimal(argv[4]) or { return usage() }
			data.length = decimal(argv[5]) or { return usage() }
			if argc == 7 {
				if C.strcmp(argv[6], c'ro') != 0 { return usage() }
				data.flags = 1
			}
		} else {
			return usage()
		}
	}
	flags := i32(if request == 0x56560001 && data.flags == 0 { C.O_RDWR } else { C.O_RDONLY }) | i32(C.O_CLOEXEC)
	fd := unsafe { C.open(argv[2], flags) }
	if fd < 0 {
		C.perror(c'vinix-volume: open')
		return 1
	}
	defer { C.close(fd) }
	if request == 0x56560004 {
		mut result := Status{}
		if C.ioctl(fd, request, &result) != 0 {
			C.perror(c'vinix-volume: status')
			return 1
		}
		if result.version != 1 || result.reserved != 0 {
			C.printf(c'vinix-volume: unsupported status version\n')
			return 1
		}
		C.printf(c'bytes=%lu sector=%lu readonly=%lu offline=%lu flush=%lu\nreads=%lu writes=%lu read_bytes=%lu write_bytes=%lu flushes=%lu\nerrors=%lu last_error=%lu disk=%lu offset=%lu slot=%lu generation=%lu\n',
			result.bytes, result.sector, result.flags & 1, (result.flags >> 1) & 1, (result.flags >> 2) & 1,
			result.reads, result.writes, result.read_bytes, result.write_bytes, result.flushes,
			result.errors, result.last_error, result.disk_id, result.start, result.slot, result.generation)
	} else {
		if C.ioctl(fd, request, &data) != 0 {
			C.perror(c'vinix-volume: change')
			return 1
		}
		if request == 0x56560001 { C.printf(c'/dev/mapper/vinix%u\n', data.slot) }
	}
	return 0
}

$if !volume_library ? {
	@[export: 'main']
	pub fn entry(argc i32, argv &&char) i32 { return run(argc, argv) }
}
