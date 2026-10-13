// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn sealed_file_tool(input &char, password &char, output &char, seal bool, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), if seal { &char(c'seal-key') } else { &char(c'unseal-key') }, input, password, output, &char(nil)]!
		run_utility(&args[0], expected)
	}
}

fn sealed_open_tool(parent &char, password &char, readonly bool, expected i32) {
	sealed_open_path_tool(parent, c'/root/crypt.sealed', password, readonly, expected)
}

fn sealed_open_path_tool(parent &char, envelope &char, password &char, readonly bool, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'open-sealed'), parent,
			&char(c'60'), &char(c'15728640'), &char(c'4096'), envelope, password,
			if readonly { &char(c'ro') } else { &char(nil) }, &char(nil)]!
		run_utility(&args[0], expected)
	}
}

fn sealed_view(parent &char, readonly bool) {
	unsafe {
		sealed_open_tool(parent, c'/root/crypt.pass', readonly, 0)
		info := status(c'/dev/mapper/vinix60')
		check(info.flags & 64 != 0 && (info.flags & 1 != 0) == readonly, c'sealed encrypted mapping mode')
		fd := C.open(c'/dev/mapper/vinix60', if readonly { C.O_RDONLY } else { C.O_RDWR })
		if readonly { check(C.open(c'/dev/mapper/vinix60', C.O_RDWR) < 0 && C.errno == C.EROFS, c'sealed readonly access') }
		else { mut data := [512]u8{init: 0x73}; check(C.pwrite(fd, &data[0], 512, 0) == 512, c'sealed writable data') }
		crypt_data(fd, 0, 0x73)
		check(fd >= 0 && C.close(fd) == 0, c'close sealed volume'); simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
	}
}

fn planned_sealed(parent &char) {
	unsafe {
		pass := C.open(c'/root/crypt.pass', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(pass >= 0 && C.write(pass, c'Vinix protected-volume fixture passphrase', 41) == 41 && C.fsync(pass) == 0 && C.close(pass) == 0, c'private passphrase fixture')
		wrong := C.open(c'/root/wrong.pass', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(wrong >= 0 && C.write(wrong, c'wrong fixture passphrase', 24) == 24 && C.close(wrong) == 0, c'wrong passphrase fixture')
		sealed_file_tool(c'/root/crypt.key', c'/root/crypt.pass', c'/root/crypt.sealed', true, 0)
		sealed_open_tool(parent, c'/root/wrong.pass', true, 1); missing(c'/dev/mapper/vinix60')
		sealed_file_tool(c'/root/crypt.sealed', c'/root/wrong.pass', c'/root/no-key', false, 1)
		check(C.open(c'/root/no-key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'wrong passphrase never publishes')
		sealed_file_tool(c'/root/crypt.sealed', c'/root/crypt.pass', c'/root/unsealed.key', false, 0)
		recovery_check(c'/root/unsealed.key')
		check(C.unlink(c'/root/crypt.key') == 0, c'remove raw key before direct unlock')
		sealed_view(parent, false); sealed_view(parent, true)
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'direct unlock leaves raw key absent')
		check(C.rename(c'/root/unsealed.key', c'/root/crypt.key') == 0, c'retain restored key for earlier workloads')
		C.printf(c'PLAN SEALED PASSED: salted scrypt, authenticated private unseal, keyless direct RW/RO unlock and wrong-passphrase refusal\n')
	}
}

fn sealed_cycles(parent &char, count int) {
	unsafe {
		for _ in 0 .. count {
			sealed_view(parent, true)
			sealed_file_tool(c'/root/crypt.sealed', c'/root/crypt.pass', c'/root/cycle-unsealed.key', false, 0)
			recovery_check(c'/root/cycle-unsealed.key')
			check(C.unlink(c'/root/cycle-unsealed.key') == 0, c'sealed cycle key cleanup')
		}
		C.sleep(13)
		C.printf(c'PLAN SEALED CYCLES count=%d\n', count)
	}
}

@[direct_array_access]
fn sealed_retention(parent &char) {
	sealed_cycles(parent, 8)
	mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	sealed_cycles(parent, 8)
	heap_snapshot(mut after)
	C.printf(c'PLAN SEALED LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'sealed large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN SEALED RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'sealed slab retention')
	}
}

fn sealed_reordered_boot(parent &char) {
	unsafe {
		check(C.unlink(c'/root/crypt.key') == 0, c'remove recovered raw key before sealed boot unlock')
		sealed_view(parent, true)
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'sealed boot unlock creates no raw key')
		sealed_file_tool(c'/root/crypt.sealed', c'/root/crypt.pass', c'/root/crypt.key', false, 0); recovery_check(c'/root/crypt.key')
		C.printf(c'PLAN SEALED REORDERED BOOT PRESERVED\n')
	}
}
