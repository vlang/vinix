// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn volume_growth_tool(parent &char, source &char, password &char, length &char, output &char, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'plan-grow-volume'), parent, source, password, length, output, &char(nil)]!
		run_utility(&args[0], expected)
	}
}

@[direct_array_access]
fn volume_growth_metadata(source &char, output &char, bytes u64, length u64) {
	mut old := [320]u8{}; mut next := [320]u8{}
	volume_rewrap_read(source, &old[0]); volume_rewrap_read(output, &next[0])
	for i in 80 .. 192 {
		if (i < 80 || i >= 88) && (i < 136 || i >= 144) { check(old[i] == next[i], c'encrypted growth preserves other metadata') }
	}
	mut capacity := u64(0); mut extent := u64(0)
	for i in 0 .. 8 { capacity |= u64(next[80 + i]) << (8 * i); extent |= u64(next[136 + i]) << (8 * i) }
	check(capacity == bytes && extent == length && C.memcmp(&old[40], &next[40], 16) != 0
		&& C.memcmp(&old[56], &next[56], 12) != 0, c'encrypted growth authenticates new geometry with fresh salt and nonce')
}

fn volume_growth_view(parent &char, config &char, force_readonly bool, saved_readonly bool, length u64, initialize bool) {
	unsafe {
		volume_seal_open_tool(parent, config, c'/root/next.pass', force_readonly, 0)
		info := status(c'/dev/mapper/vinix60'); readonly := force_readonly || saved_readonly
		check(info.flags & 64 != 0 && (info.flags & 1 != 0) == readonly && info.bytes == length
			&& info.start == 15728640 && info.disk_id == status(parent).disk_id, c'grown encrypted mapping geometry, mode and parent')
		fd := C.open(c'/dev/mapper/vinix60', if readonly { C.O_RDONLY } else { C.O_RDWR }); check(fd >= 0, c'open grown encrypted view')
		crypt_data(fd, 0, 0x73); crypt_data(fd, 4096, 0xa6)
		if readonly { check(C.open(c'/dev/mapper/vinix60', C.O_RDWR) < 0 && C.errno == C.EROFS, c'grown saved readonly cannot escalate') }
		else {
			mut data := [512]u8{init: 0xa6}; check(C.pwrite(fd, &data[0], 512, 4096) == 512, c'grown writable data')
			if initialize { data = [512]u8{init: 0xc2}; check(C.pwrite(fd, &data[0], 512, 8192) == 512, c'initialize newly exposed encrypted data') }
			check(C.fsync(fd) == 0, c'persist grown encrypted data')
		}
		if length == 12288 { crypt_data(fd, 8192, 0xc2) }
		check(C.close(fd) == 0, c'close grown encrypted view'); simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
	}
}

@[direct_array_access]
fn planned_volume_growth(parent &char, wrong &char) {
	unsafe {
		check(C.unlink(c'/root/crypt.key') == 0, c'delete raw key before authenticated growth')
		volume_growth_tool(parent, c'/root/volume-next.sealed', c'/root/crypt.pass', c'8192', c'/root/no-growth.sealed', 1)
		volume_growth_tool(wrong, c'/root/volume-next.sealed', c'/root/next.pass', c'8192', c'/root/no-growth.sealed', 1)
		volume_growth_tool(parent, c'/root/volume-next.sealed', c'/root/next.pass', c'512', c'/root/no-growth.sealed', 1)
		volume_growth_tool(parent, c'/root/volume-next.sealed', c'/root/next.pass', c'8193', c'/root/no-growth.sealed', 1)
		check(C.open(c'/root/no-growth.sealed', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'rejected growth publishes nothing')
		volume_seal_open_tool(parent, c'/root/volume-next.sealed', c'/root/next.pass', false, 0)
		before := status(c'/dev/mapper/vinix60'); live := C.open(c'/dev/mapper/vinix60', C.O_RDWR); check(live >= 0, c'hold original encrypted descriptor')
		mut ciphertext := [512]u8{}; mut after := [512]u8{}
		raw := C.open(parent, C.O_RDONLY); check(raw >= 0 && C.pread(raw, &ciphertext[0], 512, 15728640) == 512, c'original ciphertext before planning')
		volume_growth_tool(parent, c'/root/volume-next.sealed', c'/root/next.pass', c'8192', c'/root/volume-grown.sealed', 0)
		check(status(c'/dev/mapper/vinix60').bytes == 4096 && status(c'/dev/mapper/vinix60').generation == before.generation, c'growth planning preserves active mapping')
		tool(c'grow', c'/dev/mapper/vinix60', c'8192', nil, nil, 0)
		check(status(c'/dev/mapper/vinix60').generation == before.generation, c'explicit live encrypted growth preserves generation')
		crypt_data(live, 0, 0x73); crypt_data(live, 4096, 0xa6); check(C.close(live) == 0, c'held descriptor survives live growth')
		simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
		volume_growth_tool(parent, c'/root/volume-ro-next.sealed', c'/root/next.pass', c'8192', c'/root/volume-grown-ro.sealed', 0)
		volume_growth_metadata(c'/root/volume-next.sealed', c'/root/volume-grown.sealed', 16777216, 8192)
		volume_growth_metadata(c'/root/volume-ro-next.sealed', c'/root/volume-grown-ro.sealed', 16777216, 8192)
		tool(c'create', parent, c'61', c'15732736', c'4096', 0)
		volume_seal_open_tool(parent, c'/root/volume-grown.sealed', c'/root/next.pass', true, 1); missing(c'/dev/mapper/vinix60')
		simple(c'remove', c'/dev/mapper/vinix61', nil, 0)
		volume_growth_view(parent, c'/root/volume-grown.sealed', false, false, 8192, false)
		volume_growth_view(parent, c'/root/volume-grown-ro.sealed', false, true, 8192, false)
		check(C.pread(raw, &after[0], 512, 15728640) == 512 && C.close(raw) == 0 && C.memcmp(&ciphertext[0], &after[0], 512) == 0, c'growth preserves original ciphertext and tweak positions')
		mut saved := [320]u8{}; volume_rewrap_read(c'/root/volume-grown.sealed', &saved[0])
		volume_growth_tool(parent, c'/root/volume-next.sealed', c'/root/next.pass', c'8192', c'/root/volume-grown.sealed', 1)
		bundle_unchanged(c'/root/volume-grown.sealed', &saved[0], 320)
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'encrypted growth creates no raw key')
		volume_seal_key_tool(c'/root/volume-grown.sealed', c'/root/next.pass', c'/root/crypt.key', 0); recovery_check(c'/root/crypt.key')
		C.printf(c'PLAN VOLUME GROWTH PASSED: preserved key/ciphertext/start/mode, separate live growth, held descriptor, extension conflict and private publication\n')
	}
}

fn volume_growth_cycles(parent &char, count int) {
	unsafe {
		for _ in 0 .. count {
			volume_growth_tool(parent, c'/root/volume-next.sealed', c'/root/next.pass', c'8192', c'/root/cycle-growth.sealed', 0)
			volume_growth_view(parent, c'/root/cycle-growth.sealed', true, false, 8192, false)
			check(C.unlink(c'/root/cycle-growth.sealed') == 0, c'growth cycle cleanup')
		}
		C.sleep(13); C.printf(c'PLAN VOLUME GROWTH CYCLES count=%d\n', count)
	}
}

@[direct_array_access]
fn volume_growth_retention(parent &char) {
	volume_growth_cycles(parent, 4)
	mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	volume_growth_cycles(parent, 4); heap_snapshot(mut after)
	C.printf(c'PLAN VOLUME GROWTH LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'encrypted growth large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN VOLUME GROWTH RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'encrypted growth slab retention')
	}
}

fn volume_growth_reordered_boot(parent &char) {
	unsafe {
		check(C.unlink(c'/root/crypt.key') == 0, c'delete raw key before grown reboot unlock')
		volume_growth_view(parent, c'/root/volume-grown.sealed', true, false, 8192, false)
		volume_growth_view(parent, c'/root/volume-grown-ro.sealed', false, true, 8192, false)
		volume_seal_key_tool(c'/root/volume-grown.sealed', c'/root/next.pass', c'/root/crypt.key', 0); recovery_check(c'/root/crypt.key')
		C.printf(c'PLAN VOLUME GROWTH REORDERED BOOT PRESERVED\n')
	}
}

fn volume_growth_capacity_boot(parent &char) {
	unsafe {
		existing := C.open(c'/root/volume-capacity.sealed', C.O_RDONLY)
		if existing < 0 {
			check(C.errno == C.ENOENT && C.unlink(c'/root/crypt.key') == 0, c'delete raw key before physical capacity adoption')
			volume_growth_tool(parent, c'/root/volume-grown.sealed', c'/root/next.pass', c'12288', c'/root/volume-capacity.sealed', 0)
			volume_growth_tool(parent, c'/root/volume-grown-ro.sealed', c'/root/next.pass', c'12288', c'/root/volume-capacity-ro.sealed', 0)
			volume_growth_metadata(c'/root/volume-grown.sealed', c'/root/volume-capacity.sealed', 25165824, 12288)
			volume_growth_metadata(c'/root/volume-grown-ro.sealed', c'/root/volume-capacity-ro.sealed', 25165824, 12288)
			volume_growth_view(parent, c'/root/volume-capacity.sealed', false, false, 12288, true)
			volume_growth_view(parent, c'/root/volume-capacity-ro.sealed', false, true, 12288, false)
			volume_seal_key_tool(c'/root/volume-capacity.sealed', c'/root/next.pass', c'/root/crypt.key', 0); recovery_check(c'/root/crypt.key')
			C.printf(c'PLAN VOLUME GROWTH CAPACITY ADOPTED\n')
		} else {
			check(C.close(existing) == 0, c'close persisted capacity configuration')
			volume_growth_view(parent, c'/root/volume-capacity.sealed', true, false, 12288, false)
			volume_growth_view(parent, c'/root/volume-capacity-ro.sealed', false, true, 12288, false)
			C.printf(c'PLAN VOLUME GROWTH CAPACITY BOOT PRESERVED\n')
		}
	}
}
