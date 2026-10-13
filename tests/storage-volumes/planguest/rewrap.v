// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

#include <string.h>
fn C.memcmp(voidptr, voidptr, usize) i32

fn rewrap_tool(input &char, old &char, next &char, output &char, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'rewrap-key'), input, old, next, output, &char(nil)]!
		run_utility(&args[0], expected)
	}
}

fn rewrap_view(parent &char, envelope &char, readonly bool) {
	unsafe {
		sealed_open_path_tool(parent, envelope, c'/root/next.pass', readonly, 0)
		info := status(c'/dev/mapper/vinix60')
		check(info.flags & 64 != 0 && (info.flags & 1 != 0) == readonly, c'rewrapped mapping mode')
		fd := C.open(c'/dev/mapper/vinix60', if readonly { C.O_RDONLY } else { C.O_RDWR })
		check(fd >= 0, c'open rewrapped volume')
		if readonly { check(C.open(c'/dev/mapper/vinix60', C.O_RDWR) < 0 && C.errno == C.EROFS, c'rewrapped readonly access') }
		else { mut data := [512]u8{init: 0x73}; check(C.pwrite(fd, &data[0], 512, 0) == 512, c'rewrapped writable data') }
		crypt_data(fd, 0, 0x73)
		check(C.close(fd) == 0, c'close rewrapped volume')
		simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
	}
}

fn rewrap_read(path &char, output &u8) {
	fd := C.open(path, C.O_RDONLY | C.O_NOFOLLOW)
	mut info := C.stat{}
	check(fd >= 0 && C.fstat(fd, unsafe { &info }) == 0 && info.st_size == 192 && info.st_mode & 0o777 == 0o600, c'private rewrap envelope')
	check(C.read(fd, output, 192) == 192 && C.close(fd) == 0, c'read rewrap envelope')
}

@[direct_array_access]
fn planned_rewrap(parent &char) {
	unsafe {
		password := [u8(0), u8(10), u8(0xe2), u8(0x82), u8(0xac), u8(0xff), u8(13), u8(0x40), u8(0), u8(0x7f), u8(42), u8(0x11)]!
		fd := C.open(c'/root/next.pass', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(fd >= 0 && C.write(fd, &password[0], 12) == 12 && C.fsync(fd) == 0 && C.close(fd) == 0, c'private binary new credential')
		mut original := [192]u8{}; mut result := [192]u8{}; mut again := [192]u8{}
		rewrap_read(c'/root/crypt.sealed', &original[0])
		check(C.unlink(c'/root/crypt.key') == 0, c'remove raw key before credential rewrap')
		rewrap_tool(c'/root/crypt.sealed', c'/root/wrong.pass', c'/root/missing-next', c'/root/no-rewrap', 1)
		check(C.open(c'/root/no-rewrap', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'wrong old credential publishes nothing')
		rewrap_tool(c'/root/crypt.sealed', c'/root/crypt.pass', c'/root/next.pass', c'/root/rewrapped.sealed', 0)
		rewrap_read(c'/root/rewrapped.sealed', &result[0])
		check(C.memcmp(&original[40], &result[40], 16) != 0 && C.memcmp(&original[56], &result[56], 12) != 0, c'rewrap fresh salt and nonce')
		sealed_open_path_tool(parent, c'/root/rewrapped.sealed', c'/root/crypt.pass', true, 1); missing(c'/dev/mapper/vinix60')
		rewrap_view(parent, c'/root/rewrapped.sealed', false); rewrap_view(parent, c'/root/rewrapped.sealed', true)
		sealed_view(parent, true)
		rewrap_tool(c'/root/crypt.sealed', c'/root/crypt.pass', c'/root/next.pass', c'/root/rewrapped.sealed', 1)
		rewrap_read(c'/root/rewrapped.sealed', &again[0]); check(C.memcmp(&result[0], &again[0], 192) == 0, c'rewrap destination preserved')
		rewrap_read(c'/root/crypt.sealed', &again[0]); check(C.memcmp(&original[0], &again[0], 192) == 0, c'rewrap source preserved')
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'rewrap and unlock create no raw key')
		sealed_file_tool(c'/root/rewrapped.sealed', c'/root/next.pass', c'/root/crypt.key', false, 0); recovery_check(c'/root/crypt.key')
		C.printf(c'PLAN REWRAP PASSED: old authentication, fresh salt/nonce, binary new credentials, exact same volume key, no raw keyfile, RW/RO unlock and preserved envelopes\n')
	}
}

fn rewrap_cycles(parent &char, count int) {
	unsafe {
		for _ in 0 .. count {
			rewrap_tool(c'/root/crypt.sealed', c'/root/crypt.pass', c'/root/next.pass', c'/root/cycle-rewrap.sealed', 0)
			rewrap_view(parent, c'/root/cycle-rewrap.sealed', true)
			sealed_file_tool(c'/root/cycle-rewrap.sealed', c'/root/next.pass', c'/root/cycle-rewrap.key', false, 0)
			recovery_check(c'/root/cycle-rewrap.key')
			check(C.unlink(c'/root/cycle-rewrap.key') == 0 && C.unlink(c'/root/cycle-rewrap.sealed') == 0, c'rewrap cycle cleanup')
		}
		C.sleep(13)
		C.printf(c'PLAN REWRAP CYCLES count=%d\n', count)
	}
}

@[direct_array_access]
fn rewrap_retention(parent &char) {
	rewrap_cycles(parent, 4)
	mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	rewrap_cycles(parent, 4)
	heap_snapshot(mut after)
	C.printf(c'PLAN REWRAP LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'rewrap large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN REWRAP RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'rewrap slab retention')
	}
}

fn rewrap_reordered_boot(parent &char) {
	unsafe {
		check(C.unlink(c'/root/crypt.key') == 0, c'delete raw key before rewrapped boot unlock')
		sealed_open_path_tool(parent, c'/root/rewrapped.sealed', c'/root/crypt.pass', true, 1); missing(c'/dev/mapper/vinix60')
		rewrap_view(parent, c'/root/rewrapped.sealed', true)
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'rewrapped boot creates no raw key')
		sealed_file_tool(c'/root/rewrapped.sealed', c'/root/next.pass', c'/root/crypt.key', false, 0); recovery_check(c'/root/crypt.key')
		C.printf(c'PLAN REWRAP REORDERED BOOT PRESERVED\n')
	}
}
