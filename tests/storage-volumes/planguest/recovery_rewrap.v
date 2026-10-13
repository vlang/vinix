// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn recovery_rewrap_tool(input &char, old &char, next &char, output &char, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'rewrap-recovery-volume'), input, old, next, output, &char(nil)]!
		run_utility(&args[0], expected)
	}
}

fn recovery_rewrap_cycles(parent &char, count int) {
	for _ in 0 .. count {
		recovery_rewrap_tool(c'/root/volume-ro.vrecover', c'/root/old-recovery.key', c'/root/recovery.key', c'/root/cycle.vrecover', 0)
		recovery_unlock_view(parent, c'/root/cycle.vrecover', false, true)
		check(C.unlink(c'/root/cycle.vrecover') == 0, c'rewrap cycle removes only its output')
	}
	C.sleep(13); C.printf(c'PLAN RECOVERY REWRAP CYCLES count=%d\n', count)
}

@[direct_array_access]
fn recovery_rewrap_retention(parent &char) {
	recovery_rewrap_cycles(parent, 200)
	mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	recovery_rewrap_cycles(parent, 200); heap_snapshot(mut after)
	C.printf(c'PLAN RECOVERY REWRAP LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'recovery rewrap large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN RECOVERY REWRAP RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'recovery rewrap slab retention')
	}
}

@[direct_array_access]
fn recovery_rewrap_first(parent &char) {
	unsafe {
		volume_recovery_fixture(parent)
		volume_recovery_tool(c'/root/volume.sealed', c'/root/crypt.pass', c'/root/recovery.key', c'/root/volume.vrecover', true, 0)
		volume_recovery_tool(c'/root/volume-ro.sealed', c'/root/crypt.pass', c'/root/recovery.key', c'/root/volume-ro.vrecover', true, 0)
		check(C.unlink(c'/root/volume.sealed') == 0 && C.unlink(c'/root/volume-ro.sealed') == 0
			&& C.unlink(c'/root/crypt.pass') == 0 && C.unlink(c'/root/next.pass') == 0, c'credential change uses no passphrase or ordinary configuration')
		check(C.rename(c'/root/recovery.key', c'/root/old-recovery.key') == 0, c'retain old recovery credential separately')
		mut next := [64]u8{init: u8(index * 37 + 23)}
		defer { unsafe { for i in 0 .. 64 { (&BootByte(&next[0]))[i].value = 0 } } }
		fd := C.open(c'/root/recovery.key', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(fd >= 0 && C.write(fd, &next[0], 64) == 64 && C.fsync(fd) == 0 && C.close(fd) == 0, c'private replacement recovery key')
		for i in 0 .. 64 { (&BootByte(&next[0]))[i].value = 0 }
		recovery_unlock_missing_credentials()
		for readonly in [false, true]! {
			input := if readonly { &char(c'/root/volume-ro.vrecover') } else { &char(c'/root/volume.vrecover') }
			output := if readonly { &char(c'/root/rotated-ro.vrecover') } else { &char(c'/root/rotated.vrecover') }
			mut original := [320]u8{}; mut result := [320]u8{}; mut again := [320]u8{}
			volume_rewrap_read(input, &original[0])
			recovery_rewrap_tool(input, c'/root/recovery.key', c'/root/recovery.key', c'/root/no-output', 1)
			check(C.open(c'/root/no-output', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'wrong old recovery credential never publishes')
			recovery_rewrap_tool(input, c'/root/old-recovery.key', c'/root/recovery.key', output, 0)
			volume_rewrap_read(output, &result[0])
			check(C.memcmp(&original[80], &result[80], 112) == 0 && C.memcmp(&original[56], &result[56], 12) != 0, c'exact rewrapped metadata and fresh nonce')
			recovery_unlock_tool(output, c'/root/old-recovery.key', false, 1); missing(c'/dev/mapper/vinix60')
			recovery_unlock_view(parent, output, false, readonly)
			// Prior media is still an access path under its prior credential.
			recovery_unlock_tool(input, c'/root/old-recovery.key', false, 0)
			info := status(c'/dev/mapper/vinix60'); check((info.flags & 1 != 0) == readonly, c'original recovery mode unchanged')
			data := C.open(c'/dev/mapper/vinix60', C.O_RDONLY); check(data >= 0, c'open original recovery mapping')
			crypt_data(data, 0, 0x73); check(C.close(data) == 0, c'close original recovery mapping')
			simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
			for destination in [input, output, &char(c'/root/recovery.key')]! {
				recovery_rewrap_tool(input, c'/root/old-recovery.key', c'/root/recovery.key', destination, 1)
			}
			volume_rewrap_read(input, &again[0]); check(C.memcmp(&original[0], &again[0], 320) == 0, c'source backup unchanged')
			volume_rewrap_read(output, &again[0]); check(C.memcmp(&result[0], &again[0], 320) == 0, c'new backup never overwritten')
		}
		recovery_rewrap_retention(parent)
		check(C.unlink(c'/root/old-recovery.key') == 0, c'delete prior recovery credential before reboot')
		recovery_unlock_missing_credentials()
		check(C.unlink(c'/etc/vinix/volumes.vmap') == 0, c'disable invalid initial plain boot plan')
		marker := C.open(c'/second-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(marker >= 0 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist rewrap reboot phase')
		for path in [&char(c'/root'), &char(c'/etc/vinix'), &char(c'/')]! {
			file := C.open(path, C.O_RDONLY | C.O_DIRECTORY); check(file >= 0 && C.fsync(file) == 0 && C.close(file) == 0, c'persist rewrapped backups and new credential')
		}
		C.printf(c'PLAN RECOVERY REWRAP PASSED: authenticated credential changes, preserved metadata/key and readonly, old backup retained, no-overwrite publication and measured lifetimes\n')
	}
}

fn recovery_rewrap_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image()
	phase := C.open(c'/second-boot', C.O_RDONLY)
	if phase < 0 {
		parent := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }
		recovery_rewrap_first(parent)
	} else {
		check(C.close(phase) == 0, c'close rewrap phase')
		parent := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
		recovery_unlock_missing_credentials()
		check(C.open(c'/root/old-recovery.key', C.O_RDONLY) < 0 && unsafe { C.errno == C.ENOENT }, c'prior recovery key remains absent')
		recovery_unlock_tool(c'/root/volume.vrecover', c'/root/recovery.key', false, 1); missing(c'/dev/mapper/vinix60')
		recovery_unlock_view(parent, c'/root/rotated.vrecover', false, false)
		recovery_unlock_view(parent, c'/root/rotated.vrecover', true, true)
		recovery_unlock_view(parent, c'/root/rotated-ro.vrecover', false, true)
		recovery_unlock_missing_credentials()
		C.printf(c'PLAN RECOVERY REWRAP REORDERED BOOT PRESERVED\n')
	}
	C.printf(c'PLAN DONE\n'); for { C.pause() }
	return 0
}
