// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli
import os
import crypto.sha256

fn backup_test_time(path string, mode u32) {
	fd := C.open(path.str, C.O_RDWR); assert fd >= 0
	mut times := [2]C.timespec{}
	times[0].tv_sec = 1700000000; times[1].tv_sec = 1700001234; times[1].tv_nsec = 123456789
	assert C.fchmod(fd, mode) == 0 && C.futimens(fd, &times[0]) == 0 && C.close(fd) == 0
}
fn backup_test_bytes(size int) []u8 { return []u8{len: size, init: u8(index * 17 + index / 65536)} }
fn backup_test_clean(work string) { assert os.ls(work)!.all(!it.starts_with('.vinix-backup-')) }
fn backup_test_put(mut bytes []u8, at int, width int, value u64) { for i in 0 .. width { bytes[at + i] = u8(value >> (i * 8)) } }
fn backup_test_checksum(mut bytes []u8) { sum := sha256.sum(bytes[..224]); for i in 0 .. 32 { bytes[224 + i] = sum[i] } }

// Build every byte independently, including both SHA values and record layout.
fn backup_test_expected(data []u8, metadata &FileVersion, base []u8, old []u8) []u8 {
	mut body := []u8{}; mut count := 0
	for at := 0; at < data.len; at += 65536 {
		n := if data.len - at < 65536 { data.len - at } else { 65536 }
		old_n := if at >= old.len { 0 } else if old.len - at < 65536 { old.len - at } else { 65536 }
		if base.len != 0 && n == old_n && data[at..at + n] == old[at..at + n] { continue }
		mut record := []u8{len: 16}; backup_test_put(mut record, 0, 8, u64(at / 65536)); backup_test_put(mut record, 8, 4, u64(n)); body << record; body << data[at..at + n]; count++
	}
	mut header := []u8{len: 256}; copy(mut header, 'VINIXBK1'.bytes())
	for field in [[8, 4, u64(1)], [12, 4, u64(base.len != 0)], [16, 4, u64(65536)], [24, 8, u64(data.len)], [32, 4, u64(metadata.mode)], [36, 4, u64(metadata.uid)], [40, 4, u64(metadata.gid)], [48, 8, u64(metadata.seconds)], [56, 8, u64(metadata.nanoseconds)], [128, 8, u64(count)]] { backup_test_put(mut header, int(field[0]), int(field[1]), u64(field[2])) }
	content := sha256.sum(data); digest := sha256.sum(body); for i in 0 .. 32 { header[64 + i] = content[i]; header[136 + i] = digest[i] }
	if base.len != 0 { sum := sha256.sum(base); for i in 0 .. 32 { header[96 + i] = sum[i] } }
	backup_test_checksum(mut header); header << body; return header
}

fn backup_test_metadata(path string) FileVersion {
	fd := C.open(path.str, C.O_RDONLY); assert fd >= 0; mut info := C.stat{}; mut version := FileVersion{}
	assert file_backup_metadata(fd, mut info, mut version) && C.close(fd) == 0; return version
}

fn test_file_backup_full_delta_restore_independent_bytes_boundary_growth_shrink_and_metadata() {
	work := os.join_path(os.temp_dir(), 'vinix-file-backup-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	source := work + '/source'; full := work + '/full'; delta := work + '/delta'; restored := work + '/restored'
	for size in [0, 1, 65535, 65536, 65537, 131072, 131089] {
		original := backup_test_bytes(size); os.write_file_array(source, original)!; backup_test_time(source, 0o751); metadata := backup_test_metadata(source)
		assert backup_file(source.str, unsafe { nil }, full.str) == 0
		base := os.read_bytes(full)!; assert base == backup_test_expected(original, &metadata, []u8{}, []u8{})
		assert restore_file(full.str, unsafe { nil }, restored.str) == 0 && os.read_bytes(restored)! == original
		actual := backup_test_metadata(restored); assert actual.size == metadata.size && actual.mode == metadata.mode && actual.uid == metadata.uid && actual.gid == metadata.gid && actual.seconds == metadata.seconds && actual.nanoseconds == metadata.nanoseconds
		os.rm(restored)!
		for kind in 0 .. 5 {
			mut changed := original.clone()
			if kind == 1 && changed.len != 0 { changed[0] ^= 1; changed[changed.len - 1] ^= 2 }
			if kind == 2 { changed << [u8(7), 8, 9] }
			if kind == 3 { changed = []u8{} }
			if kind == 4 && changed.len != 0 { changed = changed[..changed.len - 1].clone() }
			os.write_file_array(source, changed)!; backup_test_time(source, 0o640); current := backup_test_metadata(source)
			assert backup_file(source.str, full.str, delta.str) == 0
			assert os.read_bytes(delta)! == backup_test_expected(changed, &current, base, original)
			assert restore_file(delta.str, full.str, restored.str) == 0 && os.read_bytes(restored)! == changed
			now := backup_test_metadata(restored); assert now.size == current.size && now.mode == current.mode && now.uid == current.uid && now.gid == current.gid && now.seconds == current.seconds && now.nanoseconds == current.nanoseconds
			assert os.read_bytes(full)! == base && os.read_bytes(source)! == changed
			assert backup_file(source.str, full.str, delta.str) == 1 && restore_file(delta.str, full.str, restored.str) == 1
			os.rm(delta)!; os.rm(restored)!; backup_test_clean(work)
		}
		os.rm(full)!
	}
}

fn test_file_backup_malformed_archives_base_binding_input_kinds_and_no_overwrite() {
	work := os.join_path(os.temp_dir(), 'vinix-file-backup-invalid-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	source := work + '/source'; full := work + '/full'; bad := work + '/bad'; out := work + '/out'; delta := work + '/delta'
	os.write_file(source, 'a complete file version')!; backup_test_time(source, 0o600); assert backup_file(source.str, unsafe { nil }, full.str) == 0; bytes := os.read_bytes(full)!
	for at in 0 .. bytes.len { mut damaged := bytes.clone(); damaged[at] ^= 1; os.write_file_array(bad, damaged)!; assert restore_file(bad.str, unsafe { nil }, out.str) == 1 && !os.exists(out); backup_test_clean(work) }
	for size in 0 .. bytes.len { os.write_file_array(bad, bytes[..size])!; assert restore_file(bad.str, unsafe { nil }, out.str) == 1 && !os.exists(out) }
	mut trailing := bytes.clone(); trailing << u8(0); os.write_file_array(bad, trailing)!; assert restore_file(bad.str, unsafe { nil }, out.str) == 1
	for field in [[20, 4, u64(1)], [24, 8, u64(67108865)], [32, 4, u64(0o4755)], [36, 4, u64(0xffffffff)], [40, 4, u64(0xffffffff)], [56, 8, u64(1000000000)], [128, 8, u64(0)], [168, 1, u64(1)]] {
		mut damaged := bytes.clone(); backup_test_put(mut damaged, int(field[0]), int(field[1]), u64(field[2])); backup_test_checksum(mut damaged); os.write_file_array(bad, damaged)!; assert restore_file(bad.str, unsafe { nil }, out.str) == 1 && !os.exists(out)
	}
	assert backup_file(source.str, full.str, delta.str) == 0
	assert restore_file(delta.str, unsafe { nil }, out.str) == 1 && restore_file(full.str, full.str, out.str) == 1
	os.write_file(source, 'other valid base')!; assert backup_file(source.str, unsafe { nil }, bad.str) == 1; os.rm(bad)!; assert backup_file(source.str, unsafe { nil }, bad.str) == 0
	assert restore_file(delta.str, bad.str, out.str) == 1 && !os.exists(out)
	assert backup_file(source.str, delta.str, out.str) == 1 && !os.exists(out)
	os.symlink(source, out)!; assert restore_file(full.str, unsafe { nil }, out.str) == 1 && os.is_link(out); os.rm(out)!
	os.link(source, out)!; assert restore_file(full.str, unsafe { nil }, out.str) == 1 && os.read_file(source)! == 'other valid base'; os.rm(out)!
	os.mkdir(out)!; assert restore_file(full.str, unsafe { nil }, out.str) == 1; os.rmdir(out)!
	os.symlink(source, out)!; assert backup_file(out.str, unsafe { nil }, (work + '/unused').str) == 1; os.rm(out)!
	assert backup_file(work.str, unsafe { nil }, out.str) == 1
	backup_test_time(source, 0o4755); assert backup_file(source.str, unsafe { nil }, out.str) == 1
	mut locked := PlanEdit{}; assert open_plan_destination(out.str, mut locked, true); assert restore_file(full.str, unsafe { nil }, out.str) == 1; close_plan_edit(mut locked)
	backup_test_clean(work)
}

fn test_file_backup_decoder_preserves_caller_on_invalid_header_and_cli_bounds() {
	mut version := FileVersion{size: 1, records: 1, mode: 0o600, uid: 1, gid: 1}; mut header := [256]u8{}; assert encode_file_version(&version, &header[0]); saved := version
	for at in 0 .. 256 { mut bad := header; bad[at] ^= 1; assert !decode_file_version(&bad[0], mut version) && version == saved }
	unsafe { mut args := [&char(c'vinix-volume'), &char(c'backup-file'), &char(c'/missing'), &char(c'/unused'), &char(c'extra'), &char(nil)]!
		for command in [&char(c'backup-file'), &char(c'restore-file')]! { args[1] = command; for count in [2, 3, 5] { assert run(count, &args[0]) == 2 } }
		for command in [&char(c'backup-file-delta'), &char(c'restore-file-delta')]! { args[1] = command; for count in [2, 3, 4, 6] { assert run(count, &args[0]) == 2 } }
	}
}
