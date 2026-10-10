// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

@[direct_array_access]
fn bundle_unchanged(path &char, original &u8, size i64) {
	fd := C.open(path, C.O_RDONLY)
	mut bytes := [6208]u8{}
	check(fd >= 0 && C.read(fd, &bytes[0], 6208) == size && C.close(fd) == 0,
		c'read preserved bundle')
	unsafe {
		for i := i64(0); i < size; i++ {
			check(bytes[i] == original[i], c'failed bundle save preserves previous file')
		}
	}
}

@[direct_array_access]
fn bundle_plans(parent &char, other &char) {
	unsafe {
		tool(c'save-set', c'/root/saved.vset', parent, other, &char(nil), 0)
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut original := [6208]u8{}
		size := C.read(fd, &original[0], 6208)
		check(fd >= 0 && size == 288 && C.close(fd) == 0, c'read saved two-disk bundle')
		// A later device failure and a repeated physical disk preserve the old file.
		tool(c'save-set', c'/root/saved.vset', parent, c'/dev/no-bundle-disk', &char(nil), 1)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		tool(c'save-set', c'/root/saved.vset', parent, parent, &char(nil), 1)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		simple(c'save-set', c'/root/saved.vset', &char(nil), 2)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		remove_set()
		// Bundle and legacy files share one preflight, so duplicate enrollment fails.
		copy_plan(c'/root/saved.vset', c'/etc/vinix/volumes.vset')
		simple(c'boot-restore', &char(nil), &char(nil), 1)
		missing_set()
		check(C.unlink(c'/etc/vinix/volumes.vmap') == 0
			&& C.unlink(c'/etc/vinix/volumes.d/z-data.vmap') == 0,
			c'disable individual plans for bundle boot')
		// Damage the later disk record: neither explicit nor boot restore creates a prefix.
		damaged := C.open(c'/etc/vinix/volumes.vset', C.O_RDWR)
		mut byte := u8(original[272] ^ 1)
		check(damaged >= 0 && C.pwrite(damaged, &byte, 1, 272) == 1 && C.fsync(damaged) == 0
			&& C.close(damaged) == 0, c'corrupt later bundle record')
		simple(c'restore-bundle', c'/etc/vinix/volumes.vset', &char(nil), 1)
		missing_set()
		simple(c'boot-restore', &char(nil), &char(nil), 1)
		missing_set()
		copy_plan(c'/root/saved.vset', c'/etc/vinix/volumes.vset')
		signature(other, 0x1234567a)
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 1)
		missing_set()
		simple(c'boot-restore', &char(nil), &char(nil), 1)
		missing_set()
		signature(other, 0x12345679)
		check(C.chmod(c'/etc/vinix/volumes.vset', 0o622) == 0, c'untrusted bundle mode')
		simple(c'boot-restore', &char(nil), &char(nil), 1)
		missing_set()
		check(C.chmod(c'/etc/vinix/volumes.vset', 0o600) == 0
			&& C.chown(c'/etc/vinix/volumes.vset', 65534, 65534) == 0, c'untrusted bundle owner')
		simple(c'boot-restore', &char(nil), &char(nil), 1)
		missing_set()
		check(C.chown(c'/etc/vinix/volumes.vset', 0, 0) == 0, c'restore bundle owner')
		check(C.rename(c'/etc/vinix/volumes.vset', c'/etc/vinix/.real-bundle') == 0
			&& C.symlink(c'.real-bundle', c'/etc/vinix/volumes.vset') == 0,
			c'bundle symlink fixture')
		simple(c'boot-restore', &char(nil), &char(nil), 1)
		missing_set()
		simple(c'restore-bundle', c'/etc/vinix/volumes.vset', &char(nil), 1)
		missing_set()
		check(C.unlink(c'/etc/vinix/volumes.vset') == 0
			&& C.rename(c'/etc/vinix/.real-bundle', c'/etc/vinix/volumes.vset') == 0,
			c'restore regular bundle')
		tool(c'create', other, c'9', c'3145728', c'4096', 0)
		kept := status(c'/dev/mapper/vinix9').generation
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 1)
		missing(c'/dev/mapper/vinix2')
		missing(c'/dev/mapper/vinix5')
		check(status(c'/dev/mapper/vinix9').generation == kept,
			c'bundle conflict keeps existing generation')
		simple(c'remove', c'/dev/mapper/vinix9', &char(nil), 0)
		tool(c'create', other, c'12', c'1048576', c'4096', 0)
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 1)
		missing_set()
		simple(c'remove', c'/dev/mapper/vinix12', &char(nil), 0)
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 0)
		view_data()
		second_view_data()
		first_generation := status(c'/dev/mapper/vinix2').generation
		second_generation := status(c'/dev/mapper/vinix9').generation
		simple(c'boot-restore', &char(nil), &char(nil), 0)
		check(status(c'/dev/mapper/vinix2').generation == first_generation
			&& status(c'/dev/mapper/vinix9').generation == second_generation,
			c'bundle restore idempotence')
		C.printf(c'PLAN BUNDLE PASSED: atomic save, complete preflight, trust and idempotence\n')
	}
}
