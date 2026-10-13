// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn volume_recovery_tool(input &char, a &char, b &char, output &char, backup bool, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), if backup { &char(c'backup-volume') } else { &char(c'recover-volume') }, input, a, b, output, &char(nil)]!
		run_utility(&args[0], expected)
	}
}

@[direct_array_access]
fn volume_recovery_fixture(parent &char) {
	unsafe {
		mut key := [64]u8{init: u8(index * 13 + 7)}
		mut recovery := [64]u8{init: u8(index * 29 + 41)}
		mut old := [u8(0), 10, 0xe2, 0x82, 0xac, 0xff]!
		mut next := [u8(0), 10, 0xfe, 0x17, 13, 0x7f, 0, 42]!
		defer { unsafe {
			for i in 0 .. 64 { (&BootByte(&key[0]))[i].value = 0; (&BootByte(&recovery[0]))[i].value = 0 }
			for i in 0 .. 6 { (&BootByte(&old[0]))[i].value = 0 }
			for i in 0 .. 8 { (&BootByte(&next[0]))[i].value = 0 }
		} }
		for i in 0 .. 4 {
			path := match i { 0 { &char(c'/root/crypt.key') } 1 { &char(c'/root/recovery.key') } 2 { &char(c'/root/crypt.pass') } else { &char(c'/root/next.pass') } }
			bytes := match i { 0 { &key[0] } 1 { &recovery[0] } 2 { &old[0] } else { &next[0] } }
			length := if i < 2 { 64 } else if i == 2 { 6 } else { 8 }
			fd := C.open(path, C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
			check(fd >= 0 && C.write(fd, bytes, usize(length)) == length && C.fsync(fd) == 0 && C.close(fd) == 0, c'private recovery fixtures')
		}
		crypt_tool(parent, c'/root/crypt.key', false, 0)
		fd := C.open(c'/dev/mapper/vinix60', C.O_RDWR); mut data := [512]u8{init: 0x73}
		check(fd >= 0 && C.pwrite(fd, &data[0], 512, 0) == 512 && C.fsync(fd) == 0 && C.close(fd) == 0, c'persist recovery ciphertext')
		simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
		volume_seal_tool(parent, c'/root/volume.sealed', false, 0); volume_seal_tool(parent, c'/root/volume-ro.sealed', true, 0)
		check(C.unlink(c'/root/crypt.key') == 0, c'raw key deleted before every configuration recovery')
	}
}

fn volume_recovery_view(parent &char, config &char, readonly bool) {
	volume_seal_open_tool(parent, config, c'/root/next.pass', false, 0)
	info := status(c'/dev/mapper/vinix60')
	check(info.flags & 64 != 0 && (info.flags & 1 != 0) == readonly && info.bytes == 4096
		&& info.start == 15728640 && info.disk_id == status(parent).disk_id, c'recovered exact disk, extent and mode')
	fd := C.open(c'/dev/mapper/vinix60', if readonly { C.O_RDONLY } else { C.O_RDWR })
	check(fd >= 0, c'open recovered view'); crypt_data(fd, 0, 0x73)
	if readonly { check(C.open(c'/dev/mapper/vinix60', C.O_RDWR) < 0 && unsafe { C.errno == C.EROFS }, c'recovered readonly cannot escalate') }
	check(C.close(fd) == 0, c'close recovered view'); unsafe { simple(c'remove', c'/dev/mapper/vinix60', nil, 0) }
}

@[direct_array_access]
fn volume_recovery_cycles(parent &char, count int) {
	for _ in 0 .. count {
		volume_recovery_tool(c'/root/volume-ro.sealed', c'/root/crypt.pass', c'/root/recovery.key', c'/root/cycle.vrecover', true, 0)
		volume_recovery_tool(c'/root/cycle.vrecover', c'/root/recovery.key', c'/root/next.pass', c'/root/cycle.vcrypt', false, 0)
		volume_recovery_view(parent, c'/root/cycle.vcrypt', true)
		check(C.unlink(c'/root/cycle.vrecover') == 0 && C.unlink(c'/root/cycle.vcrypt') == 0, c'recovery cycle cleanup')
	}
	C.sleep(13); C.printf(c'PLAN VOLUME RECOVERY CYCLES count=%d\n', count)
}

@[direct_array_access]
fn volume_recovery_retention(parent &char) {
	volume_recovery_cycles(parent, 4)
	mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	volume_recovery_cycles(parent, 4); heap_snapshot(mut after)
	C.printf(c'PLAN VOLUME RECOVERY LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'configuration recovery large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN VOLUME RECOVERY RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'configuration recovery slab retention')
	}
}

@[direct_array_access]
fn volume_recovery_first(parent &char, wrong &char) {
	unsafe {
		volume_recovery_fixture(parent)
		for readonly in [false, true]! {
			config := if readonly { &char(c'/root/volume-ro.sealed') } else { &char(c'/root/volume.sealed') }
			backup := if readonly { &char(c'/root/volume-ro.vrecover') } else { &char(c'/root/volume.vrecover') }
			output := if readonly { &char(c'/root/recovered-ro.vcrypt') } else { &char(c'/root/recovered.vcrypt') }
			mut original := [320]u8{}; mut saved := [320]u8{}; mut result := [320]u8{}; mut again := [320]u8{}
			volume_rewrap_read(config, &original[0])
			volume_recovery_tool(config, c'/root/crypt.pass', c'/root/recovery.key', backup, true, 0)
			volume_rewrap_read(backup, &saved[0])
			volume_recovery_tool(backup, c'/root/recovery.key', c'/root/next.pass', output, false, 0)
			volume_rewrap_read(output, &result[0])
			check(C.memcmp(&original[80], &saved[80], 112) == 0 && C.memcmp(&original[80], &result[80], 112) == 0, c'exact recovery disk/mapping metadata')
			check(C.memcmp(&original[40], &result[40], 28) != 0, c'fresh recovery salt and nonce')
			volume_seal_open_tool(parent, output, c'/root/crypt.pass', true, 1); missing(c'/dev/mapper/vinix60')
			volume_seal_open_tool(wrong, output, c'/root/next.pass', true, 1); missing(c'/dev/mapper/vinix60')
			volume_recovery_view(parent, output, readonly)
			volume_recovery_tool(config, c'/root/crypt.pass', c'/root/recovery.key', backup, true, 1)
			volume_recovery_tool(backup, c'/root/recovery.key', c'/root/next.pass', output, false, 1)
			volume_rewrap_read(config, &again[0]); check(C.memcmp(&original[0], &again[0], 320) == 0, c'source configuration unchanged')
			volume_rewrap_read(backup, &again[0]); check(C.memcmp(&saved[0], &again[0], 320) == 0, c'backup never replaced')
			volume_rewrap_read(output, &again[0]); check(C.memcmp(&result[0], &again[0], 320) == 0, c'recovered configuration never replaced')
		}
		mut damaged := [320]u8{}; volume_rewrap_read(c'/root/volume.vrecover', &damaged[0]); damaged[144] ^= 1
		bad := C.open(c'/root/bad.vrecover', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(bad >= 0 && C.write(bad, &damaged[0], 320) == 320 && C.close(bad) == 0, c'recovery metadata tamper fixture')
		volume_recovery_tool(c'/root/bad.vrecover', c'/root/recovery.key', c'/root/next.pass', c'/root/no-output', false, 1)
		volume_recovery_tool(c'/root/volume.vrecover', c'/root/volume.vrecover', c'/root/next.pass', c'/root/no-output', false, 1)
		check(C.open(c'/root/no-output', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'bad recovery never publishes')
		volume_recovery_retention(parent)
		// Only recovery material and the new credential survive the reboot.
		check(C.unlink(c'/root/volume.sealed') == 0 && C.unlink(c'/root/volume-ro.sealed') == 0
			&& C.unlink(c'/root/crypt.pass') == 0 && C.unlink(c'/root/recovered.vcrypt') == 0, c'simulate original credential/configuration loss')
		check(C.unlink(c'/etc/vinix/volumes.vmap') == 0, c'disable initial invalid plain boot plan')
		boot_copy(c'/root/next.pass', c'/etc/vinix/boot-volume.pass'); boot_copy(c'/root/recovered-ro.vcrypt', c'/etc/vinix/boot-volume.vcrypt')
		marker := C.open(c'/second-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(marker >= 0 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist recovery reboot phase')
		for path in [&char(c'/root'), &char(c'/etc/vinix'), &char(c'/')]! {
			fd := C.open(path, C.O_RDONLY | C.O_DIRECTORY); check(fd >= 0 && C.fsync(fd) == 0 && C.close(fd) == 0, c'persist recovery inputs and boot configuration')
		}
		C.printf(c'PLAN VOLUME RECOVERY PASSED: lost-credential recovery, exact authenticated metadata/key, private no-overwrite publication, RW/RO ciphertext unlock and full-cost lifetimes\n')
	}
}

fn volume_recovery_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image()
	phase := C.open(c'/second-boot', C.O_RDONLY)
	if phase < 0 {
		parent := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }
		wrong := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
		volume_recovery_first(parent, wrong)
	} else {
		check(C.close(phase) == 0, c'close recovery phase')
		parent := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
		wrong := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }
		info := status(c'/dev/mapper/vinix60')
		check(info.flags & 65 == 65 && info.bytes == 4096 && info.start == 15728640
			&& info.disk_id == status(parent).disk_id, c'production init restores recovered readonly mapping after reorder')
		fd := C.open(c'/dev/mapper/vinix60', C.O_RDONLY); check(fd >= 0, c'open production recovered view')
		crypt_data(fd, 0, 0x73); check(C.close(fd) == 0, c'close production recovered view')
		unsafe { simple(c'remove', c'/dev/mapper/vinix60', nil, 0) }
		volume_recovery_tool(c'/root/volume.vrecover', c'/root/recovery.key', c'/root/next.pass', c'/root/recovered.vcrypt', false, 0)
		volume_seal_open_tool(wrong, c'/root/recovered.vcrypt', c'/root/next.pass', true, 1); missing(c'/dev/mapper/vinix60')
		volume_recovery_view(parent, c'/root/recovered.vcrypt', false)
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && unsafe { C.errno == C.ENOENT }, c'recovery and boot create no raw keyfile')
		C.printf(c'PLAN VOLUME RECOVERY REORDERED BOOT PRESERVED\n')
	}
	C.printf(c'PLAN DONE\n'); for { C.pause() }
	return 0
}
