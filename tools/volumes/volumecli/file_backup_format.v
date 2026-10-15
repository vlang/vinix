// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

const file_backup_chunk = u64(65536)
const file_backup_limit = u64(67108864)
const file_backup_header = 256
const file_backup_record = 16

struct FileVersion {
mut:
	delta bool
	size u64
	mode u32
	uid u32
	gid u32
	seconds i64
	nanoseconds i64
	records u64
	content [32]u8
	base [32]u8
	body [32]u8
}

fn file_backup_chunks(size u64) u64 { return size / file_backup_chunk + u64(size % file_backup_chunk != 0) }
fn file_backup_length(size u64, index u64) u64 {
	if index >= file_backup_chunks(size) { return 0 }
	remaining := size - index * file_backup_chunk
	return if remaining < file_backup_chunk { remaining } else { file_backup_chunk }
}

@[direct_array_access]
fn file_version_valid(version &FileVersion) bool {
	if version.size > file_backup_limit || version.mode & ~u32(0o777) != 0 || version.uid == u32(-1) || version.gid == u32(-1)
		|| version.nanoseconds < 0 || version.nanoseconds >= 1000000000 || version.records > file_backup_chunks(version.size) { return false }
	mut nonzero := false; for byte in version.base { if byte != 0 { nonzero = true } }
	return if version.delta { nonzero } else { !nonzero && version.records == file_backup_chunks(version.size) }
}

@[direct_array_access]
fn file_backup_hash(bytes &u8, size usize, output &[32]u8) bool {
	mut hash := unsafe { &DataSha256(C.alloca(sizeof(DataSha256))) }; data_sha_init(mut hash)
	return data_sha_update(mut hash, bytes, size) && data_sha_finish(hash, output)
}

// All fields have fixed little-endian positions; unused bytes are canonical zero.
@[direct_array_access]
fn encode_file_version(version &FileVersion, output &u8) bool {
	if !file_version_valid(version) { return false }
	unsafe { C.memset(output, 0, file_backup_header); C.memcpy(output, c'VINIXBK1', 8) }
	put_le(output, 8, 4, 1); put_le(output, 12, 4, u64(version.delta)); put_le(output, 16, 4, file_backup_chunk)
	put_le(output, 24, 8, version.size); put_le(output, 32, 4, version.mode); put_le(output, 36, 4, version.uid); put_le(output, 40, 4, version.gid)
	put_le(output, 48, 8, u64(version.seconds)); put_le(output, 56, 8, u64(version.nanoseconds)); put_le(output, 128, 8, version.records)
	unsafe { C.memcpy(output + 64, &version.content[0], 32); C.memcpy(output + 96, &version.base[0], 32); C.memcpy(output + 136, &version.body[0], 32) }
	mut sum := [32]u8{}; if !file_backup_hash(output, 224, unsafe { &sum }) { return false }
	unsafe { C.memcpy(output + 224, &sum[0], 32) }; return true
}

@[direct_array_access]
fn decode_file_version(bytes &u8, mut output FileVersion) bool {
	if C.memcmp(bytes, c'VINIXBK1', 8) != 0 || get_le(bytes, 8, 4) != 1 || get_le(bytes, 12, 4) > 1 || get_le(bytes, 16, 4) != file_backup_chunk { return false }
	for at in 20 .. 24 { if unsafe { bytes[at] } != 0 { return false } }
	for at in 44 .. 48 { if unsafe { bytes[at] } != 0 { return false } }
	for at in 168 .. 224 { if unsafe { bytes[at] } != 0 { return false } }
	mut sum := [32]u8{}
	if !file_backup_hash(bytes, 224, unsafe { &sum }) || C.memcmp(unsafe { bytes + 224 }, &sum[0], 32) != 0 { return false }
	mut candidate := unsafe { &FileVersion(C.alloca(sizeof(FileVersion))) }
	unsafe { *candidate = FileVersion{delta: get_le(bytes, 12, 4) == 1, size: get_le(bytes, 24, 8), mode: u32(get_le(bytes, 32, 4)), uid: u32(get_le(bytes, 36, 4)), gid: u32(get_le(bytes, 40, 4)), seconds: i64(get_le(bytes, 48, 8)), nanoseconds: i64(get_le(bytes, 56, 8)), records: get_le(bytes, 128, 8)} }
	unsafe { C.memcpy(&candidate.content[0], bytes + 64, 32); C.memcpy(&candidate.base[0], bytes + 96, 32); C.memcpy(&candidate.body[0], bytes + 136, 32) }
	if !file_version_valid(candidate) { return false }; output = unsafe { *candidate }; return true
}

// Fixed-size result; never expose findings until archive publication succeeds.
fn file_backup_report(version &FileVersion, restoring bool) i32 {
	mut digest := [65]char{}
	if !scrub_digest_text(&version.content, &digest[0]) { return 1 }
	return finish_bundle_report(C.printf(c'format=VINIXBK1 operation=%s kind=%s bytes=%lu chunks=%lu stored_chunks=%lu mode=%03o uid=%u gid=%u mtime_seconds=%ld mtime_nanoseconds=%ld content_sha256=%s\n',
		if restoring { &char(c'restored-file') } else { &char(c'backed-up-file') }, if version.delta { &char(c'delta') } else { &char(c'full') }, version.size, file_backup_chunks(version.size), version.records, version.mode, version.uid, version.gid, version.seconds, version.nanoseconds, &digest[0]) >= 0)
}
