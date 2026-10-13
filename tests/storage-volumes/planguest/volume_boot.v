// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

struct BootByte { mut: volatile value u8 }

@[direct_array_access]
fn boot_copy(source &char, destination &char) {
	mut bytes := [1024]u8{}
	defer { unsafe { for i in 0 .. 1024 { (&BootByte(&bytes[0]))[i].value = 0 } } }
	input := C.open(source, C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC); mut info := C.stat{}
	check(input >= 0 && C.fstat(input, unsafe { &info }) == 0 && info.st_size > 0 && info.st_size <= 1024, c'bounded boot input fixture')
	check(C.read(input, &bytes[0], usize(info.st_size)) == info.st_size && C.close(input) == 0, c'read boot input fixture')
	output := C.open(destination, C.O_WRONLY | C.O_CREAT | C.O_TRUNC | C.O_NOFOLLOW | C.O_CLOEXEC, u32(0o600))
	check(output >= 0 && C.write(output, &bytes[0], usize(info.st_size)) == info.st_size
		&& C.fsync(output) == 0 && C.close(output) == 0, c'persist private boot input fixture')
}

fn boot_volume_prepare(config &char) {
	boot_copy(c'/root/next.pass', c'/etc/vinix/boot-volume.pass')
	boot_copy(config, c'/etc/vinix/boot-volume.vcrypt')
	directory := C.open(c'/etc/vinix', C.O_RDONLY | C.O_DIRECTORY)
	check(directory >= 0 && C.fsync(directory) == 0 && C.close(directory) == 0, c'persist boot unlock configuration directory')
}

fn boot_unlock_tool(expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'boot-unlock'), &char(nil)]!
		run_utility(&args[0], expected)
	}
}

fn boot_volume_view(parent &char, length u64, readonly bool) {
	unsafe {
		info := status(c'/dev/mapper/vinix60')
		check(info.flags & 64 != 0 && (info.flags & 1 != 0) == readonly && info.bytes == length
			&& info.start == 15728640 && info.disk_id == status(parent).disk_id, c'boot encrypted mapping retains authenticated geometry and mode')
		fd := C.open(c'/dev/mapper/vinix60', if readonly { C.O_RDONLY } else { C.O_RDWR }); check(fd >= 0, c'open boot encrypted view')
		crypt_data(fd, 0, 0x73); crypt_data(fd, 4096, 0xa6)
		if length == 12288 { crypt_data(fd, 8192, 0xc2) }
		if readonly { check(C.open(c'/dev/mapper/vinix60', C.O_RDWR) < 0 && C.errno == C.EROFS, c'boot readonly mode cannot escalate') }
		else { mut bytes := [512]u8{init: 0x73}; check(C.pwrite(fd, &bytes[0], 512, 0) == 512 && C.fsync(fd) == 0, c'boot writable data preserves ciphertext') }
		check(C.close(fd) == 0, c'close boot encrypted view')
		simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
	}
}

fn boot_volume_disable() {
	check(C.unlink(c'/etc/vinix/boot-volume.vcrypt') == 0 && C.unlink(c'/etc/vinix/boot-volume.pass') == 0, c'disable opt-in encrypted boot')
	directory := C.open(c'/etc/vinix', C.O_RDONLY | C.O_DIRECTORY)
	check(directory >= 0 && C.fsync(directory) == 0 && C.close(directory) == 0, c'persist encrypted boot disable')
}

fn volume_boot_cycles(parent &char, count int) {
	for _ in 0 .. count {
		boot_volume_prepare(c'/root/volume-grown-ro.sealed')
		boot_unlock_tool(0); boot_volume_view(parent, 8192, true); boot_volume_disable()
	}
	C.sleep(13); C.printf(c'PLAN VOLUME BOOT CYCLES count=%d\n', count)
}

@[direct_array_access]
fn volume_boot_retention(parent &char) {
	volume_boot_cycles(parent, 4)
	mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	volume_boot_cycles(parent, 4); heap_snapshot(mut after)
	C.printf(c'PLAN VOLUME BOOT LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'encrypted boot large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN VOLUME BOOT RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'encrypted boot slab retention')
	}
}

@[direct_array_access]
fn volume_boot_reboot_probe(parent &char) {
	fd := C.open(c'/etc/vinix/boot-volume.vcrypt', C.O_RDONLY | C.O_NOFOLLOW)
	if fd < 0 { check(C.errno == C.ENOENT, c'disabled boot configuration'); return }
	mut bytes := [320]u8{}
	check(C.read(fd, &bytes[0], 320) == 320 && C.close(fd) == 0, c'read saved boot metadata')
	mut capacity := u64(0); mut length := u64(0)
	for i in 0 .. 8 { capacity |= u64(bytes[80 + i]) << (8 * i); length |= u64(bytes[136 + i]) << (8 * i) }
	if capacity != status(parent).bytes {
		missing(c'/dev/mapper/vinix60'); C.printf(c'PLAN VOLUME BOOT CHANGED CAPACITY REFUSED\n'); return
	}
	boot_volume_view(parent, length, true)
	C.printf(c'PLAN VOLUME BOOT INIT RESTORED: bytes=%ld, readonly=1, original ciphertext preserved\n', length)
}

fn planned_volume_boot(parent &char) {
	unsafe {
		check(C.unlink(c'/root/crypt.key') == 0, c'delete raw key before boot unlock qualification')
		boot_copy(c'/root/crypt.pass', c'/etc/vinix/boot-volume.pass')
		boot_unlock_tool(1); missing(c'/dev/mapper/vinix60')
		boot_volume_prepare(c'/root/volume-grown.sealed')
		check(C.chmod(c'/etc/vinix/boot-volume.pass', 0o644) == 0, c'untrusted boot credential')
		boot_unlock_tool(1); missing(c'/dev/mapper/vinix60'); check(C.chmod(c'/etc/vinix/boot-volume.pass', 0o600) == 0, c'restore private boot credential')
		check(C.rename(c'/etc/vinix/boot-volume.pass', c'/etc/vinix/saved-boot.pass') == 0
			&& C.symlink(c'/etc/vinix/saved-boot.pass', c'/etc/vinix/boot-volume.pass') == 0, c'symlink boot credential fixture')
		boot_unlock_tool(1); missing(c'/dev/mapper/vinix60')
		check(C.unlink(c'/etc/vinix/boot-volume.pass') == 0 && C.rename(c'/etc/vinix/saved-boot.pass', c'/etc/vinix/boot-volume.pass') == 0, c'restore pinned boot credential fixture')
		boot_unlock_tool(0); before := status(c'/dev/mapper/vinix60')
		boot_unlock_tool(1); check(status(c'/dev/mapper/vinix60').generation == before.generation, c'occupied boot slot preserves its live mapping')
		boot_volume_view(parent, 8192, false)
		boot_volume_prepare(c'/root/volume-grown-ro.sealed'); boot_unlock_tool(0); boot_volume_view(parent, 8192, true)
		bad := C.open(c'/etc/vinix/boot-volume.vcrypt', C.O_RDWR | C.O_NOFOLLOW); mut tag := u8(0)
		check(bad >= 0 && C.pread(bad, &tag, 1, 288) == 1, c'read boot authentication tag'); tag ^= 1
		check(C.pwrite(bad, &tag, 1, 288) == 1 && C.fsync(bad) == 0 && C.close(bad) == 0, c'tampered boot configuration fixture')
		boot_unlock_tool(1); missing(c'/dev/mapper/vinix60')
		boot_volume_disable(); boot_unlock_tool(0); missing(c'/dev/mapper/vinix60')
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'boot unlock produces no raw key')
		volume_seal_key_tool(c'/root/volume-grown.sealed', c'/root/next.pass', c'/root/crypt.key', 0); recovery_check(c'/root/crypt.key')
		boot_volume_prepare(c'/root/volume-grown-ro.sealed')
		C.printf(c'PLAN VOLUME BOOT PASSED: root private pinned inputs, wrong credentials/tampering/symlinks/permissions/occupied slots refused, keyless RW/RO unlock and opt-in disable\n')
	}
}
