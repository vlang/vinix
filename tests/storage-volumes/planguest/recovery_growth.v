// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn recovery_growth_tool(parent &char, input &char, capacity &char, length &char, output &char, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'plan-grow-recovery-volume'), parent, input, &char(c'/root/recovery.key'), capacity, length, output, &char(nil)]!
		run_utility(&args[0], expected)
	}
}

@[direct_array_access]
fn recovery_growth_metadata(input &char, output &char, capacity u64, length u64) {
	mut old := [320]u8{}; mut next := [320]u8{}
	volume_rewrap_read(input, &old[0]); volume_rewrap_read(output, &next[0])
	for i in 88 .. 192 { if i < 136 || i >= 144 { check(old[i] == next[i], c'recovery growth preserves other metadata') } }
	mut bytes := u64(0); mut extent := u64(0)
	for i in 0 .. 8 { bytes |= u64(next[80 + i]) << (8 * i); extent |= u64(next[136 + i]) << (8 * i) }
	check(bytes == capacity && extent == length && C.memcmp(&old[56], &next[56], 12) != 0, c'recovery growth declares exact geometry and fresh nonce')
}

fn recovery_growth_view(parent &char, backup &char, force bool, saved_readonly bool, length u64, initialize bool) {
	unsafe {
		recovery_unlock_tool(backup, c'/root/recovery.key', force, 0)
		readonly := force || saved_readonly; info := status(c'/dev/mapper/vinix60')
		check(info.flags & 64 != 0 && (info.flags & 1 != 0) == readonly && info.bytes == length
			&& info.start == 15728640 && info.disk_id == status(parent).disk_id, c'grown recovery identity, length and mode')
		fd := C.open(c'/dev/mapper/vinix60', if readonly { C.O_RDONLY } else { C.O_RDWR }); check(fd >= 0, c'open grown recovery view')
		crypt_data(fd, 0, 0x73)
		if initialize {
			check(!readonly, c'initialize only writable recovery view')
			mut data := [512]u8{init: if length == 8192 { u8(0xa6) } else { u8(0xc2) }}
			position := if length == 8192 { i64(4096) } else { i64(8192) }
			check(C.pwrite(fd, &data[0], 512, position) == 512 && C.fsync(fd) == 0, c'persist newly exposed encrypted recovery data')
		}
		crypt_data(fd, 4096, 0xa6); if length == 12288 { crypt_data(fd, 8192, 0xc2) }
		if readonly { check(C.open(c'/dev/mapper/vinix60', C.O_RDWR) < 0 && C.errno == C.EROFS, c'grown recovery readonly cannot escalate') }
		check(C.close(fd) == 0, c'close grown recovery view'); simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
	}
}

fn recovery_growth_cycles(parent &char, count int) {
	for _ in 0 .. count {
		recovery_growth_tool(parent, c'/root/volume-ro.vrecover', c'16777216', c'8192', c'/root/cycle.vrecover', 0)
		recovery_growth_view(parent, c'/root/cycle.vrecover', false, true, 8192, false)
		check(C.unlink(c'/root/cycle.vrecover') == 0, c'recovery growth cycle output cleanup')
	}
	C.sleep(13); C.printf(c'PLAN RECOVERY GROWTH CYCLES count=%d\n', count)
}

@[direct_array_access]
fn recovery_growth_retention(parent &char) {
	recovery_growth_cycles(parent, 200)
	mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	recovery_growth_cycles(parent, 200); heap_snapshot(mut after)
	C.printf(c'PLAN RECOVERY GROWTH LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'recovery growth large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN RECOVERY GROWTH RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'recovery growth slab retention')
	}
}

@[direct_array_access]
fn recovery_growth_first(parent &char, wrong &char) {
	unsafe {
		volume_recovery_fixture(parent)
		volume_recovery_tool(c'/root/volume.sealed', c'/root/crypt.pass', c'/root/recovery.key', c'/root/volume.vrecover', true, 0)
		volume_recovery_tool(c'/root/volume-ro.sealed', c'/root/crypt.pass', c'/root/recovery.key', c'/root/volume-ro.vrecover', true, 0)
		check(C.unlink(c'/root/volume.sealed') == 0 && C.unlink(c'/root/volume-ro.sealed') == 0
			&& C.unlink(c'/root/crypt.pass') == 0 && C.unlink(c'/root/next.pass') == 0, c'grow without raw keys, passphrases or ordinary configurations')
		recovery_unlock_missing_credentials()
		recovery_growth_tool(wrong, c'/root/volume.vrecover', c'16777216', c'8192', c'/root/no-output', 1)
		recovery_growth_tool(parent, c'/root/volume.vrecover', c'33554432', c'8192', c'/root/no-output', 1)
		recovery_growth_tool(parent, c'/root/volume.vrecover', c'16777216', c'512', c'/root/no-output', 1)
		recovery_growth_tool(parent, c'/root/volume.vrecover', c'16777216', c'8193', c'/root/no-output', 1)
		check(C.open(c'/root/no-output', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'wrong identity/capacity and invalid growth never publish')
		recovery_unlock_tool(c'/root/volume.vrecover', c'/root/recovery.key', false, 0)
		before := status(c'/dev/mapper/vinix60'); held := C.open(c'/dev/mapper/vinix60', C.O_RDWR)
		check(held >= 0, c'hold original encrypted descriptor')
		mut ciphertext := [512]u8{}; mut again := [512]u8{}
		raw := C.open(parent, C.O_RDONLY); check(raw >= 0 && C.pread(raw, &ciphertext[0], 512, 15728640) == 512, c'capture ciphertext before planning')
		for readonly in [false, true]! {
			input := if readonly { &char(c'/root/volume-ro.vrecover') } else { &char(c'/root/volume.vrecover') }
			output := if readonly { &char(c'/root/grown-ro.vrecover') } else { &char(c'/root/grown.vrecover') }
			recovery_growth_tool(parent, input, c'16777216', c'8192', output, 0)
			recovery_growth_metadata(input, output, 16777216, 8192)
			recovery_growth_tool(parent, input, c'16777216', c'8192', output, 1)
			recovery_growth_tool(parent, input, c'16777216', c'8192', input, 1)
		}
		after := status(c'/dev/mapper/vinix60'); check(after.bytes == 4096 && after.generation == before.generation, c'planning preserves live mapping and held descriptor')
		crypt_data(held, 0, 0x73)
		check(C.pread(raw, &again[0], 512, 15728640) == 512 && C.memcmp(&ciphertext[0], &again[0], 512) == 0, c'planning never writes physical ciphertext')
		check(C.close(raw) == 0 && C.close(held) == 0, c'close original retained descriptors'); simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
		recovery_growth_view(parent, c'/root/grown.vrecover', false, false, 8192, true)
		recovery_growth_view(parent, c'/root/grown.vrecover', true, false, 8192, false)
		recovery_growth_view(parent, c'/root/grown-ro.vrecover', false, true, 8192, false)
		recovery_growth_retention(parent); recovery_unlock_missing_credentials()
		check(C.unlink(c'/etc/vinix/volumes.vmap') == 0, c'disable invalid plain boot plan')
		marker := C.open(c'/second-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(marker >= 0 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist recovery growth phase')
		for path in [&char(c'/root'), &char(c'/etc/vinix'), &char(c'/')]! {
			fd := C.open(path, C.O_RDONLY | C.O_DIRECTORY); check(fd >= 0 && C.fsync(fd) == 0 && C.close(fd) == 0, c'persist recovery growth backups')
		}
		C.printf(c'PLAN RECOVERY GROWTH PASSED: authenticated extent growth, unchanged live descriptors/data, RW/RO ciphertext and measured lifetimes\n')
	}
}

fn recovery_growth_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image()
	phase := C.open(c'/second-boot', C.O_RDONLY)
	if phase < 0 {
		parent := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }
		wrong := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
		recovery_growth_first(parent, wrong)
	} else {
		check(C.close(phase) == 0, c'close recovery growth phase'); recovery_unlock_missing_credentials()
		parent := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
		wrong := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }
		check(status(parent).bytes == 33554432, c'physical capacity grew across reordered boot')
		recovery_unlock_tool(c'/root/grown.vrecover', c'/root/recovery.key', false, 1); missing(c'/dev/mapper/vinix60')
		recovery_growth_tool(wrong, c'/root/grown.vrecover', c'33554432', c'12288', c'/root/no-output', 1)
		recovery_growth_tool(parent, c'/root/grown.vrecover', c'16777216', c'12288', c'/root/no-output', 1)
		recovery_growth_tool(parent, c'/root/grown.vrecover', c'33554432', c'12288', c'/root/capacity.vrecover', 0)
		recovery_growth_tool(parent, c'/root/grown-ro.vrecover', c'33554432', c'12288', c'/root/capacity-ro.vrecover', 0)
		recovery_growth_metadata(c'/root/grown.vrecover', c'/root/capacity.vrecover', 33554432, 12288)
		recovery_growth_metadata(c'/root/grown-ro.vrecover', c'/root/capacity-ro.vrecover', 33554432, 12288)
		recovery_growth_view(parent, c'/root/capacity.vrecover', false, false, 12288, true)
		recovery_growth_view(parent, c'/root/capacity.vrecover', true, false, 12288, false)
		recovery_growth_view(parent, c'/root/capacity-ro.vrecover', false, true, 12288, false)
		recovery_unlock_missing_credentials(); C.printf(c'PLAN RECOVERY GROWTH CAPACITY BOOT PRESERVED\n')
	}
	C.printf(c'PLAN DONE\n'); for { C.pause() }
	return 0
}
