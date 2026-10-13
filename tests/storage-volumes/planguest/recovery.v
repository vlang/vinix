// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn recovery_tool(input &char, recovery &char, output &char, backup bool, expected i32) {
	unsafe {
		arguments := [&char(c'/usr/sbin/vinix-volume'), if backup { &char(c'backup-key') } else { &char(c'recover-key') },
			input, recovery, output, &char(nil)]!
		run_utility(&arguments[0], expected)
	}
}

@[direct_array_access]
fn recovery_check(path &char) {
	unsafe {
		mut info := C.stat{}; fd := C.open(path, C.O_RDONLY | C.O_NOFOLLOW)
		mut key := [65]u8{}
		check(fd >= 0 && C.fstat(fd, &info) == 0 && info.st_size == 64 && info.st_uid == 0
			&& info.st_mode & 0o777 == 0o600 && C.read(fd, &key[0], 65) == 64 && C.close(fd) == 0, c'private exact recovered key')
		for i in 0 .. 64 { check(key[i] == u8(i * 13 + 7), c'recovered exact key bytes') }
	}
}

@[direct_array_access]
fn planned_recovery(parent &char) {
	unsafe {
		mut recovery := [64]u8{}
		for i in 0 .. 64 { recovery[i] = u8(i * 29 + 41) }
		fd := C.open(c'/root/recovery.key', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(fd >= 0 && C.write(fd, &recovery[0], 64) == 64 && C.fsync(fd) == 0 && C.close(fd) == 0, c'recovery key fixture')
		recovery_tool(c'/root/crypt.key', c'/root/crypt.key', c'/root/reused.backup', true, 1)
		recovery_tool(c'/root/crypt.key', c'/root/recovery.key', c'/root/crypt.backup', true, 0)
		recovery_tool(c'/root/crypt.key', c'/root/recovery.key', c'/root/crypt.backup', true, 1)
		recovery_tool(c'/root/crypt.backup', c'/root/crypt.key', c'/root/wrong.key', false, 1)
		check(C.open(c'/root/wrong.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'wrong recovery key never published')
		backup := C.open(c'/root/crypt.backup', C.O_RDONLY); mut original := [160]u8{}
		check(backup >= 0 && C.read(backup, &original[0], 160) == 160 && C.close(backup) == 0, c'canonical recovery envelope')
		mut damaged := original; damaged[65] ^= 1
		bad := C.open(c'/root/corrupt.backup', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(bad >= 0 && C.write(bad, &damaged[0], 160) == 160 && C.close(bad) == 0, c'tampered envelope fixture')
		recovery_tool(c'/root/corrupt.backup', c'/root/recovery.key', c'/root/crypt.key', false, 1)
		recovery_check(c'/root/crypt.key')
		check(C.unlink(c'/root/crypt.key') == 0, c'delete original volume key')
		recovery_tool(c'/root/corrupt.backup', c'/root/recovery.key', c'/root/crypt.key', false, 1)
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'tampering never creates key')
		recovery_tool(c'/root/crypt.backup', c'/root/recovery.key', c'/root/crypt.key', false, 0)
		recovery_check(c'/root/crypt.key')
		crypt_tool(parent, c'/root/crypt.key', true, 0)
		view := C.open(c'/dev/mapper/vinix60', C.O_RDONLY); crypt_data(view, 0, 0x73)
		check(C.close(view) == 0, c'close recovered volume'); simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
		bundle_unchanged(c'/root/crypt.backup', &original[0], 160)
		C.printf(c'PLAN RECOVERY PASSED: authenticated backup, original key deletion, private restore, ciphertext reopen and no replacement\n')
	}
}

fn recovery_cycles(count int) {
	unsafe {
		for _ in 0 .. count {
			recovery_tool(c'/root/crypt.key', c'/root/recovery.key', c'/root/cycle.backup', true, 0)
			recovery_tool(c'/root/cycle.backup', c'/root/recovery.key', c'/root/cycle.key', false, 0)
			recovery_check(c'/root/cycle.key')
			check(C.unlink(c'/root/cycle.key') == 0 && C.unlink(c'/root/cycle.backup') == 0, c'key recovery cycle cleanup')
		}
		C.printf(c'PLAN RECOVERY CYCLES count=%d\n', count)
	}
}

fn recovery_reordered_boot() {
	unsafe {
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'original volume key absent after reboot')
		recovery_tool(c'/root/crypt.backup', c'/root/recovery.key', c'/root/crypt.key', false, 0)
		recovery_check(c'/root/crypt.key')
		C.printf(c'PLAN RECOVERY REORDERED BOOT PRESERVED\n')
	}
}
