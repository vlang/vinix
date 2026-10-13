// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn volume_rewrap_tool(input &char, old &char, next &char, output &char, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'rewrap-volume'), input, old, next, output, &char(nil)]!
		run_utility(&args[0], expected)
	}
}

fn volume_rewrap_read(path &char, output &u8) {
	fd := C.open(path, C.O_RDONLY | C.O_NOFOLLOW); mut info := C.stat{}
	check(fd >= 0 && C.fstat(fd, unsafe { &info }) == 0 && info.st_size == 320 && info.st_mode & 0o777 == 0o600, c'private rewrapped configuration')
	check(C.read(fd, output, 320) == 320 && C.close(fd) == 0, c'read rewrapped configuration')
}

fn volume_rewrap_view(parent &char, config &char, force_readonly bool, expected_readonly bool) {
	unsafe {
		volume_seal_open_tool(parent, config, c'/root/next.pass', force_readonly, 0)
		info := status(c'/dev/mapper/vinix60')
		check(info.flags & 64 != 0 && (info.flags & 1 != 0) == expected_readonly && info.start == 15728640 && info.bytes == 4096 && info.sector == 512, c'rewrapped authenticated mapping geometry and mode')
		fd := C.open(c'/dev/mapper/vinix60', if expected_readonly { C.O_RDONLY } else { C.O_RDWR })
		check(fd >= 0, c'open rewrapped configuration')
		if expected_readonly { check(C.open(c'/dev/mapper/vinix60', C.O_RDWR) < 0 && C.errno == C.EROFS, c'rewrapped saved readonly cannot escalate') }
		else { mut data := [512]u8{init: 0x73}; check(C.pwrite(fd, &data[0], 512, 0) == 512, c'rewrapped writable data') }
		crypt_data(fd, 0, 0x73); check(C.close(fd) == 0, c'close rewrapped configuration')
		simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
	}
}

@[direct_array_access]
fn planned_volume_rewrap(parent &char, wrong &char) {
	unsafe {
		check(C.unlink(c'/root/crypt.key') == 0, c'delete raw key before volume credential changes')
		volume_rewrap_tool(c'/root/volume.sealed', c'/root/wrong.pass', c'/root/missing-next', c'/root/no-volume-rewrap', 1)
		check(C.open(c'/root/no-volume-rewrap', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'bad old credential publishes no configuration')
		for readonly in [false, true]! {
			input := if readonly { &char(c'/root/volume-ro.sealed') } else { &char(c'/root/volume.sealed') }
			output := if readonly { &char(c'/root/volume-ro-next.sealed') } else { &char(c'/root/volume-next.sealed') }
			mut original := [320]u8{}; mut result := [320]u8{}; mut again := [320]u8{}
			volume_rewrap_read(input, &original[0])
			volume_rewrap_tool(input, c'/root/crypt.pass', c'/root/next.pass', output, 0)
			volume_rewrap_read(output, &result[0])
			check(C.memcmp(&original[40], &result[40], 16) != 0 && C.memcmp(&original[56], &result[56], 12) != 0, c'configuration rewrap fresh salt and nonce')
			check(C.memcmp(&original[80], &result[80], 112) == 0, c'configuration rewrap preserves complete authenticated disk and mapping metadata')
			volume_seal_open_tool(parent, output, c'/root/crypt.pass', true, 1); missing(c'/dev/mapper/vinix60')
			volume_seal_open_tool(wrong, output, c'/root/next.pass', true, 1); missing(c'/dev/mapper/vinix60')
			volume_rewrap_view(parent, output, false, readonly)
			volume_rewrap_view(parent, output, true, true)
			volume_seal_view(parent, input, true, true)
			volume_rewrap_tool(input, c'/root/crypt.pass', c'/root/next.pass', output, 1)
			volume_rewrap_read(output, &again[0]); check(C.memcmp(&result[0], &again[0], 320) == 0, c'rewrapped destination preserved')
			volume_rewrap_read(input, &again[0]); check(C.memcmp(&original[0], &again[0], 320) == 0, c'original configuration preserved')
		}
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'volume credential change and unlock create no raw key')
		volume_seal_key_tool(c'/root/volume-next.sealed', c'/root/next.pass', c'/root/crypt.key', 0); recovery_check(c'/root/crypt.key')
		C.printf(c'PLAN VOLUME REWRAP PASSED: authenticated offline credential changes, fresh salt/nonce, exact disk/extent/mode and key, binary credentials, preserved configurations and keyless RW/RO unlock\n')
	}
}

fn volume_rewrap_cycles(parent &char, count int) {
	unsafe {
		for _ in 0 .. count {
			volume_rewrap_tool(c'/root/volume.sealed', c'/root/crypt.pass', c'/root/next.pass', c'/root/cycle-volume-next.sealed', 0)
			volume_rewrap_view(parent, c'/root/cycle-volume-next.sealed', true, true)
			volume_seal_key_tool(c'/root/cycle-volume-next.sealed', c'/root/next.pass', c'/root/cycle-volume-next.key', 0)
			recovery_check(c'/root/cycle-volume-next.key')
			check(C.unlink(c'/root/cycle-volume-next.key') == 0 && C.unlink(c'/root/cycle-volume-next.sealed') == 0, c'configuration rewrap cycle cleanup')
		}
		C.sleep(13); C.printf(c'PLAN VOLUME REWRAP CYCLES count=%d\n', count)
	}
}

@[direct_array_access]
fn volume_rewrap_retention(parent &char) {
	volume_rewrap_cycles(parent, 4)
	mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	volume_rewrap_cycles(parent, 4); heap_snapshot(mut after)
	C.printf(c'PLAN VOLUME REWRAP LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'configuration rewrap large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN VOLUME REWRAP RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'configuration rewrap slab retention')
	}
}

fn volume_rewrap_reordered_boot(parent &char, wrong &char) {
	unsafe {
		check(C.unlink(c'/root/crypt.key') == 0, c'delete raw key before rewrapped configuration boot unlock')
		volume_seal_open_tool(parent, c'/root/volume-next.sealed', c'/root/crypt.pass', true, 1); missing(c'/dev/mapper/vinix60')
		volume_seal_open_tool(wrong, c'/root/volume-next.sealed', c'/root/next.pass', true, 1); missing(c'/dev/mapper/vinix60')
		volume_rewrap_view(parent, c'/root/volume-next.sealed', true, true)
		volume_rewrap_view(parent, c'/root/volume-ro-next.sealed', false, true)
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'rewrapped configuration boot creates no raw key')
		volume_seal_key_tool(c'/root/volume-ro-next.sealed', c'/root/next.pass', c'/root/crypt.key', 0); recovery_check(c'/root/crypt.key')
		C.printf(c'PLAN VOLUME REWRAP REORDERED BOOT PRESERVED\n')
	}
}
