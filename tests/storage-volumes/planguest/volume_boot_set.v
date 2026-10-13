// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn boot_set_prepare() {
	boot_copy(c'/root/boot-data.pass', c'/etc/vinix/boot-volumes.d/data.pass')
	boot_copy(c'/root/boot-data.sealed', c'/etc/vinix/boot-volumes.d/data.vcrypt')
	directory := C.open(c'/etc/vinix/boot-volumes.d', C.O_RDONLY | C.O_DIRECTORY)
	check(directory >= 0 && C.fsync(directory) == 0 && C.close(directory) == 0, c'persist named encrypted boot configuration')
}

fn boot_set_disable() {
	check(C.unlink(c'/etc/vinix/boot-volumes.d/data.vcrypt') == 0 && C.unlink(c'/etc/vinix/boot-volumes.d/data.pass') == 0, c'disable named encrypted boot configuration')
	directory := C.open(c'/etc/vinix/boot-volumes.d', C.O_RDONLY | C.O_DIRECTORY)
	check(directory >= 0 && C.fsync(directory) == 0 && C.close(directory) == 0, c'persist named boot disable')
}

fn boot_set_view(parent &char) {
	unsafe {
		info := status(c'/dev/mapper/vinix61')
		check(info.flags & 64 != 0 && info.flags & 1 != 0 && info.bytes == 4096
			&& info.start == 15794176 && info.disk_id == status(parent).disk_id, c'named boot mapping preserves independent disk, extent and readonly mode')
		fd := C.open(c'/dev/mapper/vinix61', C.O_RDONLY); check(fd >= 0, c'open named encrypted boot view')
		crypt_data(fd, 0, 0x52)
		check(C.open(c'/dev/mapper/vinix61', C.O_RDWR) < 0 && C.errno == C.EROFS, c'named readonly boot mapping cannot escalate')
		check(C.close(fd) == 0, c'close named encrypted boot view')
		simple(c'remove', c'/dev/mapper/vinix61', nil, 0)
	}
}

@[direct_array_access]
fn boot_set_fixture(parent &char) {
	unsafe {
		check(C.mkdir(c'/etc/vinix/boot-volumes.d', 0o700) == 0, c'create private encrypted boot set directory')
		mut key := [64]u8{init: u8(index * 17 + 11)}
		defer { unsafe { for i in 0 .. 64 { (&BootByte(&key[0]))[i].value = 0 } } }
		mut password := [u8(0), u8(0xfe), 10, 0xe2, 0x82, 0xac, 13, 0x40, 42, 0x17, 0xff]!
		defer { unsafe { for i in 0 .. 11 { (&BootByte(&password[0]))[i].value = 0 } } }
		credential := C.open(c'/root/boot-data.pass', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(credential >= 0 && C.write(credential, &password[0], 11) == 11 && C.fsync(credential) == 0 && C.close(credential) == 0, c'independent binary boot credential fixture')
		fd := C.open(c'/root/boot-data.key', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(fd >= 0 && C.write(fd, &key[0], 64) == 64 && C.fsync(fd) == 0 && C.close(fd) == 0, c'private independent boot volume key fixture')
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'open-crypt'), parent, &char(c'61'), &char(c'15794176'), &char(c'4096'), &char(c'/root/boot-data.key'), &char(nil)]!
		run_utility(&args[0], 0)
		data := C.open(c'/dev/mapper/vinix61', C.O_RDWR); mut bytes := [512]u8{init: 0x52}
		check(data >= 0 && C.pwrite(data, &bytes[0], 512, 0) == 512 && C.fsync(data) == 0 && C.close(data) == 0, c'persist independently encrypted boot data')
		simple(c'remove', c'/dev/mapper/vinix61', nil, 0)
		seal := [&char(c'/usr/sbin/vinix-volume'), &char(c'seal-volume'), parent, &char(c'61'), &char(c'15794176'), &char(c'4096'),
			&char(c'/root/boot-data.key'), &char(c'/root/boot-data.pass'), &char(c'/root/boot-data.sealed'), &char(c'ro'), &char(nil)]!
		run_utility(&seal[0], 0)
		check(C.unlink(c'/root/boot-data.key') == 0, c'remove independent raw key before all boot set unlocks')
	}
}

fn boot_set_cycles(parent &char, other &char, count int) {
	for _ in 0 .. count {
		boot_volume_prepare(c'/root/volume-grown-ro.sealed'); boot_set_prepare()
		boot_unlock_tool(0); boot_volume_view(parent, 8192, true); boot_set_view(other)
		boot_set_disable(); boot_volume_disable()
	}
	C.sleep(13); C.printf(c'PLAN VOLUME BOOT SET CYCLES count=%d\n', count)
}

@[direct_array_access]
fn boot_set_retention(parent &char, other &char) {
	boot_set_fixture(other)
	boot_set_cycles(parent, other, 4)
	mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	boot_set_cycles(parent, other, 4); heap_snapshot(mut after)
	C.printf(c'PLAN VOLUME BOOT SET LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'encrypted boot set large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN VOLUME BOOT SET RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'encrypted boot set slab retention')
	}
}

@[direct_array_access]
fn boot_set_reboot_probe(parent &char, other &char) {
	fd := C.open(c'/etc/vinix/boot-volumes.d/data.vcrypt', C.O_RDONLY | C.O_NOFOLLOW)
	if fd < 0 { check(C.errno == C.ENOENT, c'disabled named encrypted boot configuration'); return }
	check(C.close(fd) == 0, c'close named boot marker')
	mut bytes := [320]u8{}; volume_rewrap_read(c'/etc/vinix/boot-volume.vcrypt', &bytes[0])
	mut capacity := u64(0); for i in 0 .. 8 { capacity |= u64(bytes[80 + i]) << (8 * i) }
	if capacity != status(parent).bytes {
		missing(c'/dev/mapper/vinix61'); C.printf(c'PLAN VOLUME BOOT SET CHANGED CAPACITY REFUSED\n')
	} else {
		boot_set_view(other); C.printf(c'PLAN VOLUME BOOT SET INIT RESTORED: slot=61, independent key/disk, readonly=1\n')
	}
	if status(parent).bytes == 16777216 || status(parent).bytes == 20971520 { boot_set_disable() }
}

fn planned_boot_set(parent &char, other &char) {
	unsafe {
		boot_set_prepare()
		boot_copy(c'/root/crypt.pass', c'/etc/vinix/boot-volumes.d/data.pass')
		boot_unlock_tool(1); missing(c'/dev/mapper/vinix60'); missing(c'/dev/mapper/vinix61')
		boot_set_prepare(); check(C.chmod(c'/etc/vinix/boot-volumes.d/data.vcrypt', 0o644) == 0, c'untrusted later boot configuration')
		boot_unlock_tool(1); missing(c'/dev/mapper/vinix60'); missing(c'/dev/mapper/vinix61')
		check(C.chmod(c'/etc/vinix/boot-volumes.d/data.vcrypt', 0o600) == 0, c'restore private named configuration')
		boot_unlock_tool(0); boot_volume_view(parent, 8192, true); boot_set_view(other)
		boot_copy(c'/root/volume-grown-ro.sealed', c'/etc/vinix/boot-volumes.d/data.vcrypt')
		boot_copy(c'/root/next.pass', c'/etc/vinix/boot-volumes.d/data.pass')
		simple(c'boot-restore', nil, nil, 1); missing(c'/dev/mapper/vinix60'); missing(c'/dev/mapper/vinix61')
		boot_set_prepare()
		volume_seal_open_tool(other, c'/root/boot-data.sealed', c'/root/boot-data.pass', false, 0)
		before := status(c'/dev/mapper/vinix61')
		boot_unlock_tool(1)
		check(status(c'/dev/mapper/vinix61').generation == before.generation, c'later occupied boot slot preserves its existing mapping')
		boot_volume_view(parent, 8192, true); boot_set_view(other)
		check(C.open(c'/root/boot-data.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'boot set unlock produces no independent raw key')
		C.printf(c'PLAN VOLUME BOOT SET PASSED: all-member authentication and saved conflict preflight, independent keys/disks, pinned physical set, readonly preservation and documented sequential failure\n')
	}
}
