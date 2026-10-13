// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn recovery_unlock_tool(backup &char, key &char, readonly bool, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'open-recovery-volume-auto'), backup, key, if readonly { &char(c'ro') } else { &char(nil) }, &char(nil)]!
		run_utility(&args[0], expected)
	}
}

fn recovery_unlock_view(parent &char, backup &char, force bool, readonly bool) {
	recovery_unlock_tool(backup, c'/root/recovery.key', force, 0)
	info := status(c'/dev/mapper/vinix60')
	check(info.flags & 64 != 0 && (info.flags & 1 != 0) == readonly && info.bytes == 4096
		&& info.start == 15728640 && info.disk_id == status(parent).disk_id, c'exact recovery unlock identity, extent and mode')
	fd := C.open(c'/dev/mapper/vinix60', if readonly { C.O_RDONLY } else { C.O_RDWR })
	check(fd >= 0, c'open direct recovery view'); crypt_data(fd, 0, 0x73)
	if readonly { check(C.open(c'/dev/mapper/vinix60', C.O_RDWR) < 0 && unsafe { C.errno == C.EROFS }, c'recovery readonly cannot escalate') }
	else {
		mut data := [512]u8{init: 0x73}
		check(C.pwrite(fd, &data[0], 512, 0) == 512 && C.fsync(fd) == 0, c'recovery RW mapping writes encrypted data')
	}
	check(C.close(fd) == 0, c'close direct recovery view')
	unsafe { simple(c'remove', c'/dev/mapper/vinix60', nil, 0) }
}

@[direct_array_access]
fn recovery_unlock_missing_credentials() {
	unsafe {
		for path in [&char(c'/root/crypt.key'), &char(c'/root/crypt.pass'), &char(c'/root/next.pass'),
			&char(c'/root/volume.sealed'), &char(c'/root/volume-ro.sealed'), &char(c'/root/recovered.vcrypt'), &char(c'/root/recovered-ro.vcrypt')]! {
			check(C.open(path, C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'rescue needs no original/new credential, configuration or raw key')
		}
	}
}

fn recovery_unlock_cycles(parent &char, count int) {
	for _ in 0 .. count { recovery_unlock_view(parent, c'/root/volume-ro.vrecover', false, true) }
	C.sleep(13); C.printf(c'PLAN RECOVERY UNLOCK CYCLES count=%d\n', count)
}

@[direct_array_access]
fn recovery_unlock_retention(parent &char) {
	recovery_unlock_cycles(parent, 200)
	mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	recovery_unlock_cycles(parent, 200); heap_snapshot(mut after)
	C.printf(c'PLAN RECOVERY UNLOCK LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'recovery unlock large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN RECOVERY UNLOCK RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'recovery unlock slab retention')
	}
}

@[direct_array_access]
fn recovery_unlock_first(parent &char) {
	unsafe {
		volume_recovery_fixture(parent)
		volume_recovery_tool(c'/root/volume.sealed', c'/root/crypt.pass', c'/root/recovery.key', c'/root/volume.vrecover', true, 0)
		volume_recovery_tool(c'/root/volume-ro.sealed', c'/root/crypt.pass', c'/root/recovery.key', c'/root/volume-ro.vrecover', true, 0)
		check(C.unlink(c'/root/volume.sealed') == 0 && C.unlink(c'/root/volume-ro.sealed') == 0
			&& C.unlink(c'/root/crypt.pass') == 0 && C.unlink(c'/root/next.pass') == 0, c'delete all ordinary recovery credentials and configurations')
		recovery_unlock_missing_credentials()
		mut original := [320]u8{}; mut again := [320]u8{}
		volume_rewrap_read(c'/root/volume.vrecover', &original[0]); again = original; again[288] ^= 1
		bad := C.open(c'/root/bad.vrecover', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(bad >= 0 && C.write(bad, &again[0], 320) == 320 && C.close(bad) == 0, c'tampered direct recovery fixture')
		recovery_unlock_tool(c'/root/bad.vrecover', c'/root/recovery.key', false, 1); missing(c'/dev/mapper/vinix60')
		recovery_unlock_tool(c'/root/volume.vrecover', c'/root/volume.vrecover', false, 1); missing(c'/dev/mapper/vinix60')
		recovery_unlock_view(parent, c'/root/volume.vrecover', false, false)
		recovery_unlock_view(parent, c'/root/volume.vrecover', true, true)
		recovery_unlock_view(parent, c'/root/volume-ro.vrecover', false, true)
		recovery_unlock_tool(c'/root/volume-ro.vrecover', c'/root/recovery.key', false, 0)
		before := status(c'/dev/mapper/vinix60')
		recovery_unlock_tool(c'/root/volume.vrecover', c'/root/recovery.key', false, 1)
		after := status(c'/dev/mapper/vinix60')
		check(after.generation == before.generation && after.flags == before.flags, c'occupied slot refusal preserves mapping')
		simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
		recovery_unlock_retention(parent)
		volume_rewrap_read(c'/root/volume.vrecover', &again[0]); check(C.memcmp(&original[0], &again[0], 320) == 0, c'direct unlock never modifies backup')
		recovery_unlock_missing_credentials()
		check(C.unlink(c'/etc/vinix/volumes.vmap') == 0, c'disable initial invalid plain plan')
		marker := C.open(c'/second-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(marker >= 0 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist direct recovery reboot phase')
		for path in [&char(c'/root'), &char(c'/etc/vinix'), &char(c'/')]! {
			fd := C.open(path, C.O_RDONLY | C.O_DIRECTORY); check(fd >= 0 && C.fsync(fd) == 0 && C.close(fd) == 0, c'persist recovery backups and marker')
		}
		C.printf(c'PLAN RECOVERY UNLOCK PASSED: authenticated direct discovery, RW/RO rescue without original keys or credentials, occupied-slot refusal and measured lifetimes\n')
	}
}

fn recovery_unlock_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image()
	phase := C.open(c'/second-boot', C.O_RDONLY)
	if phase < 0 {
		parent := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }
		recovery_unlock_first(parent)
	} else {
		check(C.close(phase) == 0, c'close direct recovery phase')
		parent := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
		recovery_unlock_missing_credentials()
		recovery_unlock_view(parent, c'/root/volume.vrecover', false, false)
		recovery_unlock_view(parent, c'/root/volume.vrecover', true, true)
		recovery_unlock_view(parent, c'/root/volume-ro.vrecover', false, true)
		recovery_unlock_missing_credentials()
		C.printf(c'PLAN RECOVERY UNLOCK REORDERED BOOT PRESERVED\n')
	}
	C.printf(c'PLAN DONE\n'); for { C.pause() }
	return 0
}
