// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn volume_seal_tool(parent &char, config &char, readonly bool, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'seal-volume'), parent, &char(c'60'), &char(c'15728640'), &char(c'4096'),
			&char(c'/root/crypt.key'), &char(c'/root/crypt.pass'), config, if readonly { &char(c'ro') } else { &char(nil) }, &char(nil)]!
		run_utility(&args[0], expected)
	}
}

fn volume_seal_open_tool(parent &char, config &char, password &char, readonly bool, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'open-volume'), parent, config, password, if readonly { &char(c'ro') } else { &char(nil) }, &char(nil)]!
		run_utility(&args[0], expected)
	}
}

fn volume_seal_key_tool(config &char, password &char, output &char, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'unseal-volume-key'), config, password, output, &char(nil)]!
		run_utility(&args[0], expected)
	}
}

fn volume_seal_view(parent &char, config &char, force_readonly bool, expected_readonly bool) {
	unsafe {
		volume_seal_open_tool(parent, config, c'/root/crypt.pass', force_readonly, 0)
		info := status(c'/dev/mapper/vinix60')
		check(info.flags & 64 != 0 && (info.flags & 1 != 0) == expected_readonly && info.start == 15728640 && info.bytes == 4096 && info.sector == 512, c'authenticated mapping geometry and mode')
		fd := C.open(c'/dev/mapper/vinix60', if expected_readonly { C.O_RDONLY } else { C.O_RDWR })
		check(fd >= 0, c'open configured volume')
		if expected_readonly { check(C.open(c'/dev/mapper/vinix60', C.O_RDWR) < 0 && C.errno == C.EROFS, c'saved readonly cannot escalate') }
		else { mut data := [512]u8{init: 0x73}; check(C.pwrite(fd, &data[0], 512, 0) == 512, c'configured writable data') }
		crypt_data(fd, 0, 0x73); check(C.close(fd) == 0, c'close configured volume')
		simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
	}
}

@[direct_array_access]
fn planned_volume_seal(parent &char, wrong &char) {
	unsafe {
		volume_seal_tool(parent, c'/root/volume.sealed', false, 0)
		volume_seal_tool(parent, c'/root/volume-ro.sealed', true, 0)
		mut original := [320]u8{}; mut again := [320]u8{}
		fd := C.open(c'/root/volume.sealed', C.O_RDONLY); mut info := C.stat{}
		check(fd >= 0 && C.fstat(fd, &info) == 0 && info.st_size == 320 && info.st_mode & 0o777 == 0o600
			&& C.read(fd, &original[0], 320) == 320 && C.close(fd) == 0, c'private authenticated configuration')
		volume_seal_tool(parent, c'/root/volume.sealed', false, 1)
		verify := C.open(c'/root/volume.sealed', C.O_RDONLY)
		check(verify >= 0 && C.read(verify, &again[0], 320) == 320 && C.close(verify) == 0 && C.memcmp(&original[0], &again[0], 320) == 0, c'configuration no replacement')
		// A still-valid slot/mode change must fail its authentication tag.
		again = original; again[144] ^= 1
		bad := C.open(c'/root/volume-bad.sealed', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(bad >= 0 && C.write(bad, &again[0], 320) == 320 && C.close(bad) == 0, c'configuration tamper fixture')
		volume_seal_open_tool(parent, c'/root/volume-bad.sealed', c'/root/crypt.pass', false, 1); missing(c'/dev/mapper/vinix60')
		volume_seal_open_tool(parent, c'/root/volume.sealed', c'/root/wrong.pass', false, 1); missing(c'/dev/mapper/vinix60')
		volume_seal_key_tool(c'/root/volume.sealed', c'/root/wrong.pass', c'/root/no-volume-key', 1)
		check(C.open(c'/root/no-volume-key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'bad credentials never recover a key')
		check(C.unlink(c'/root/crypt.key') == 0, c'delete raw key before configured unlock')
		volume_seal_open_tool(wrong, c'/root/volume.sealed', c'/root/crypt.pass', true, 1); missing(c'/dev/mapper/vinix60')
		volume_seal_open_tool(c'/root/volume.sealed', c'/root/volume.sealed', c'/root/crypt.pass', true, 1); missing(c'/dev/mapper/vinix60')
		volume_seal_view(parent, c'/root/volume.sealed', false, false)
		volume_seal_view(parent, c'/root/volume.sealed', true, true)
		volume_seal_view(parent, c'/root/volume-ro.sealed', false, true)
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'configured unlock creates no raw keyfile')
		volume_seal_key_tool(c'/root/volume.sealed', c'/root/crypt.pass', c'/root/crypt.key', 0); recovery_check(c'/root/crypt.key')
		C.printf(c'PLAN VOLUME SEAL PASSED: authenticated identity/geometry/mode, tamper and wrong-disk refusal, same ciphertext, keyless RW/RO unlock and explicit private recovery\n')
	}
}

fn volume_seal_cycles(parent &char, count int) {
	unsafe {
		for _ in 0 .. count {
			volume_seal_tool(parent, c'/root/cycle-volume.sealed', false, 0)
			volume_seal_view(parent, c'/root/cycle-volume.sealed', true, true)
			volume_seal_key_tool(c'/root/cycle-volume.sealed', c'/root/crypt.pass', c'/root/cycle-volume.key', 0)
			recovery_check(c'/root/cycle-volume.key')
			check(C.unlink(c'/root/cycle-volume.key') == 0 && C.unlink(c'/root/cycle-volume.sealed') == 0, c'configuration cycle cleanup')
		}
		C.sleep(13); C.printf(c'PLAN VOLUME SEAL CYCLES count=%d\n', count)
	}
}

@[direct_array_access]
fn volume_seal_retention(parent &char) {
	volume_seal_cycles(parent, 4)
	mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	volume_seal_cycles(parent, 4); heap_snapshot(mut after)
	C.printf(c'PLAN VOLUME SEAL LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'configuration large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN VOLUME SEAL RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'configuration slab retention')
	}
}

fn volume_seal_reordered_boot(parent &char, wrong &char) {
	unsafe {
		check(C.unlink(c'/root/crypt.key') == 0, c'delete raw key before configuration boot unlock')
		volume_seal_open_tool(wrong, c'/root/volume.sealed', c'/root/crypt.pass', true, 1); missing(c'/dev/mapper/vinix60')
		volume_seal_view(parent, c'/root/volume.sealed', true, true)
		volume_seal_view(parent, c'/root/volume-ro.sealed', false, true)
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'configuration boot unlock creates no raw key')
		volume_seal_key_tool(c'/root/volume.sealed', c'/root/crypt.pass', c'/root/crypt.key', 0); recovery_check(c'/root/crypt.key')
		C.printf(c'PLAN VOLUME SEAL REORDERED BOOT PRESERVED\n')
	}
}
