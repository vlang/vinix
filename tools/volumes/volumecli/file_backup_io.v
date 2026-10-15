// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

#include <time.h>
struct C.timespec {
mut:
	tv_sec i64
	tv_nsec i64
}
fn C.pwrite(i32, voidptr, usize, i64) i64
fn C.fchown(i32, u32, u32) i32
fn C.futimens(i32, &C.timespec) i32
fn C.memset(voidptr, i32, usize) voidptr

// Regular-file identity and mutation evidence are checked on the held inode.
// Callers must quiesce writers; timestamp checks are not an atomic snapshot.
fn file_backup_metadata(fd i32, mut info C.stat, mut version FileVersion) bool {
	if C.fstat(fd, &info) != 0 || C.S_ISREG(info.st_mode) == 0 || info.st_size < 0 || u64(info.st_size) > file_backup_limit || info.st_mode & 0o7000 != 0 { return false }
	version.size = u64(info.st_size); version.mode = info.st_mode & 0o777; version.uid = info.st_uid; version.gid = info.st_gid
	$if macos { version.seconds = info.st_mtimespec.tv_sec; version.nanoseconds = info.st_mtimespec.tv_nsec }
	$else { version.seconds = info.st_mtim.tv_sec; version.nanoseconds = info.st_mtim.tv_nsec }
	return version.uid != u32(-1) && version.gid != u32(-1) && version.nanoseconds >= 0 && version.nanoseconds < 1000000000
}

fn file_backup_same(fd i32, before &C.stat) bool {
	mut after := C.stat{}
	if C.fstat(fd, &after) != 0 || after.st_dev != before.st_dev || after.st_ino != before.st_ino || after.st_size != before.st_size
		|| after.st_mode != before.st_mode || after.st_uid != before.st_uid || after.st_gid != before.st_gid { return false }
	$if macos { return after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec && after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec && after.st_ctimespec.tv_sec == before.st_ctimespec.tv_sec && after.st_ctimespec.tv_nsec == before.st_ctimespec.tv_nsec }
	$else { return after.st_mtim.tv_sec == before.st_mtim.tv_sec && after.st_mtim.tv_nsec == before.st_mtim.tv_nsec && after.st_ctim.tv_sec == before.st_ctim.tv_sec && after.st_ctim.tv_nsec == before.st_ctim.tv_nsec }
}

@[direct_array_access]
fn file_backup_read(fd i32, output &u8, size u64, offset u64) bool {
	mut done := u64(0)
	for done < size {
		n := C.pread(fd, unsafe { output + done }, usize(size - done), i64(offset + done))
		if n < 0 && unsafe { C.errno == C.EINTR } { continue }
		if n <= 0 || u64(n) > size - done { return false }; done += u64(n)
	}; return true
}

@[direct_array_access]
fn file_backup_write(fd i32, input &u8, size u64, offset u64) bool {
	mut done := u64(0)
	for done < size {
		n := C.pwrite(fd, unsafe { input + done }, usize(size - done), i64(offset + done))
		if n < 0 && unsafe { C.errno == C.EINTR } { continue }
		if n <= 0 || u64(n) > size - done { return false }; done += u64(n)
	}; return true
}

fn file_backup_eof(fd i32, offset u64) bool {
	mut byte := u8(0)
	for { n := C.pread(fd, &byte, 1, i64(offset)); if n < 0 && unsafe { C.errno == C.EINTR } { continue }; return n == 0 }
	return false
}

// Verify an entire archive before its content is used as a base. A delta needs
// the full base to verify reconstructed content, checked again during restore.
@[direct_array_access]
fn read_file_archive(fd i32, mut version FileVersion, mut info C.stat, digest &[32]u8) bool {
	if C.fstat(fd, &info) != 0 || C.S_ISREG(info.st_mode) == 0 || info.st_size < file_backup_header || u64(info.st_size) > file_backup_limit + 16640 { return false }
	mut header := [256]u8{}; mut candidate := FileVersion{}
	if !file_backup_read(fd, &header[0], 256, 0) || !decode_file_version(&header[0], mut candidate) { return false }
	mut whole := unsafe { &DataSha256(C.alloca(sizeof(DataSha256))) }; mut body := unsafe { &DataSha256(C.alloca(sizeof(DataSha256))) }; mut content := unsafe { &DataSha256(C.alloca(sizeof(DataSha256))) }; data_sha_init(mut whole); data_sha_init(mut body); data_sha_init(mut content)
	if !data_sha_update(mut whole, &header[0], 256) { return false }
	mut bytes := [65536]u8{}; mut record := [16]u8{}; mut offset := u64(256); mut previous := u64(0)
	for at := u64(0); at < candidate.records; at++ {
		if !file_backup_read(fd, &record[0], 16, offset) { return false }; offset += 16
		index := get_le(&record[0], 0, 8); length := get_le(&record[0], 8, 4)
		if (at != 0 && index <= previous) || (!candidate.delta && index != at) || length == 0 || length != file_backup_length(candidate.size, index) || get_le(&record[0], 12, 4) != 0 { return false }
		previous = index
		if !file_backup_read(fd, &bytes[0], length, offset) || !data_sha_update(mut whole, &record[0], 16) || !data_sha_update(mut whole, &bytes[0], usize(length))
			|| !data_sha_update(mut body, &record[0], 16) || !data_sha_update(mut body, &bytes[0], usize(length)) || (!candidate.delta && !data_sha_update(mut content, &bytes[0], usize(length))) { return false }
		offset += length
	}
	mut body_sum := [32]u8{}; mut content_sum := [32]u8{}; mut sum := [32]u8{}
	if offset != u64(info.st_size) || !file_backup_eof(fd, offset) || !file_backup_same(fd, &info)
		|| !data_sha_finish(body, unsafe { &body_sum }) || body_sum != candidate.body || !data_sha_finish(whole, unsafe { &sum })
		|| (!candidate.delta && (!data_sha_finish(content, unsafe { &content_sum }) || content_sum != candidate.content)) { return false }
	version = candidate; unsafe { *digest = sum }; return true
}

// Temp creation/publication stays relative to the same locked directory inode.
// linkat refuses any existing destination, including a symlink or input alias.
fn file_backup_temporary(edit &PlanEdit, name &char) i32 {
	for attempt := 0; attempt < 64; attempt++ {
		if C.snprintf(name, 64, c'.vinix-backup-%ld-%u', i64(C.getpid()), u32(attempt)) <= 0 { return -1 }
		if C.strcmp(name, &edit.name[0]) == 0 { continue }
		fd := C.openat(edit.directory, name, C.O_RDWR | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, u32(0o600))
		if fd >= 0 || unsafe { C.errno != C.EEXIST } { return fd }
	}; return -1
}

fn file_backup_publish(fd &i32, owned &bool, edit &PlanEdit, name &char) bool {
	if C.fsync(unsafe { *fd }) != 0 { return false }
	closed := C.close(unsafe { *fd }); unsafe { *fd = -1 }; if closed != 0 { return false }
	if C.linkat(edit.directory, name, edit.directory, &edit.name[0], 0) != 0 { return false }
	if C.unlinkat(edit.directory, name, 0) != 0 { return false }
	unsafe { *owned = false }
	return C.fsync(edit.directory) == 0
}

@[direct_array_access]
fn backup_file(source_path &char, base_path &char, destination_path &char) i32 {
	mut source := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }; mut base := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }; mut destination := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	unsafe { *source = PlanEdit{}; *base = PlanEdit{}; *destination = PlanEdit{} }
	defer { close_plan_edit(mut destination); close_plan_edit(mut base); close_plan_edit(mut source) }
	mut version := unsafe { &FileVersion(C.alloca(sizeof(FileVersion))) }; unsafe { *version = FileVersion{delta: base_path != nil} }; mut original := C.stat{}; mut base_info := C.stat{}; mut base_version := FileVersion{}; mut base_sum := [32]u8{}
	if !open_plan_edit(source_path, mut source, false) || !file_backup_metadata(source.source, mut original, mut version) { return plan_error(c'backup requires a bounded quiescent regular file without special mode bits') }
	if version.delta {
		if !open_plan_edit(base_path, mut base, false) || !read_file_archive(base.source, mut base_version, mut base_info, unsafe { &base_sum }) || base_version.delta { return plan_error(c'delta requires a valid full base archive') }
		version.base = base_sum
	}
	if !open_plan_destination(destination_path, mut destination, true) { return 1 }
	mut temporary := [64]char{}; mut fd := file_backup_temporary(destination, &temporary[0]); if fd < 0 { return plan_error(c'cannot create backup temporary') }
	mut owned := true
	defer { if fd >= 0 { C.close(fd) }; if owned { C.unlinkat(destination.directory, &temporary[0], 0) } }
	mut bytes := [65536]u8{}; mut prior := [65536]u8{}; mut record := [16]u8{}; mut offset := u64(256)
	mut content := unsafe { &DataSha256(C.alloca(sizeof(DataSha256))) }; mut body := unsafe { &DataSha256(C.alloca(sizeof(DataSha256))) }; data_sha_init(mut content); data_sha_init(mut body)
	for index := u64(0); index < file_backup_chunks(version.size); index++ {
		length := file_backup_length(version.size, index)
		if !file_backup_read(source.source, &bytes[0], length, index * file_backup_chunk) || !data_sha_update(mut content, &bytes[0], usize(length)) { return plan_error(c'backup source read failed') }
		mut same := false
		if version.delta && length == file_backup_length(base_version.size, index) {
			if !file_backup_read(base.source, &prior[0], length, 272 + index * (file_backup_chunk + 16)) { return plan_error(c'backup base read failed') }
			same = C.memcmp(&bytes[0], &prior[0], usize(length)) == 0
		}
		if same { continue }
		put_le(&record[0], 0, 8, index); put_le(&record[0], 8, 4, length)
		if !file_backup_write(fd, &record[0], 16, offset) || !file_backup_write(fd, &bytes[0], length, offset + 16)
			|| !data_sha_update(mut body, &record[0], 16) || !data_sha_update(mut body, &bytes[0], usize(length)) { return plan_error(c'backup write failed') }
		offset += 16 + length; version.records++
	}
	mut header := [256]u8{}
	if !data_sha_finish(content, unsafe { &version.content }) || !data_sha_finish(body, unsafe { &version.body }) || !encode_file_version(version, &header[0])
		|| !file_backup_eof(source.source, version.size) || !file_backup_same(source.source, &original) || (version.delta && !file_backup_same(base.source, &base_info))
		|| !file_backup_write(fd, &header[0], 256, 0) { return plan_error(c'backup input changed or finalization failed') }
	// Verify our complete stream from the original temporary descriptor before
	// publication. Quiescence remains the caller's consistency requirement.
	mut observed := FileVersion{}; mut info := C.stat{}; mut sum := [32]u8{}
	if !read_file_archive(fd, mut observed, mut info, unsafe { &sum }) || C.fchmod(fd, 0o600) != 0 || !file_backup_same(source.source, &original)
		|| (version.delta && !file_backup_same(base.source, &base_info)) || !file_backup_publish(unsafe { &fd }, unsafe { &owned }, destination, &temporary[0]) { return plan_error(c'backup validation or durable no-overwrite publication failed') }
	return file_backup_report(version, false)
}

fn file_backup_restore_metadata(fd i32, version &FileVersion) bool {
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 { return false }
	if (info.st_uid != version.uid || info.st_gid != version.gid) && C.fchown(fd, version.uid, version.gid) != 0 { return false }
	mut times := [2]C.timespec{}
	times[0].tv_nsec = i64(C.UTIME_OMIT); times[1].tv_sec = version.seconds; times[1].tv_nsec = version.nanoseconds
	return C.fchmod(fd, version.mode) == 0 && C.futimens(fd, &times[0]) == 0
}

@[direct_array_access]
fn restore_file(archive_path &char, base_path &char, destination_path &char) i32 {
	mut archive := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }; mut base := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }; mut destination := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	unsafe { *archive = PlanEdit{}; *base = PlanEdit{}; *destination = PlanEdit{} }
	defer { close_plan_edit(mut destination); close_plan_edit(mut base); close_plan_edit(mut archive) }
	mut version := FileVersion{}; mut info := C.stat{}; mut sum := [32]u8{}; mut base_version := FileVersion{}; mut base_info := C.stat{}; mut base_sum := [32]u8{}
	if !open_plan_edit(archive_path, mut archive, false) || !read_file_archive(archive.source, mut version, mut info, unsafe { &sum }) || version.delta != (base_path != unsafe { nil }) { return plan_error(c'invalid archive or missing full base') }
	if version.delta {
		if !open_plan_edit(base_path, mut base, false) || !read_file_archive(base.source, mut base_version, mut base_info, unsafe { &base_sum }) || base_version.delta || base_sum != version.base { return plan_error(c'delta base fingerprint mismatch') }
	}
	if !open_plan_destination(destination_path, mut destination, true) { return 1 }
	mut temporary := [64]char{}; mut fd := file_backup_temporary(destination, &temporary[0]); if fd < 0 { return plan_error(c'cannot create restoration temporary') }
	mut owned := true
	defer { if fd >= 0 { C.close(fd) }; if owned { C.unlinkat(destination.directory, &temporary[0], 0) } }
	mut bytes := [65536]u8{}; mut record := [16]u8{}; mut content := unsafe { &DataSha256(C.alloca(sizeof(DataSha256))) }; data_sha_init(mut content)
	mut offset := u64(256); mut at := u64(0); mut next := u64(-1)
	if version.records != 0 { if !file_backup_read(archive.source, &record[0], 16, offset) { return 1 }; next = get_le(&record[0], 0, 8); offset += 16 }
	for index := u64(0); index < file_backup_chunks(version.size); index++ {
		length := file_backup_length(version.size, index)
		if index == next {
			if get_le(&record[0], 8, 4) != length || get_le(&record[0], 12, 4) != 0 || !file_backup_read(archive.source, &bytes[0], length, offset) { return plan_error(c'restoration archive read failed') }
			offset += length; at++; next = u64(-1)
			if at < version.records { if !file_backup_read(archive.source, &record[0], 16, offset) { return 1 }; next = get_le(&record[0], 0, 8); offset += 16 }
		} else {
			if !version.delta || length != file_backup_length(base_version.size, index) || !file_backup_read(base.source, &bytes[0], length, 272 + index * (file_backup_chunk + 16)) { return plan_error(c'delta has an uncovered changed-length chunk') }
		}
		if !data_sha_update(mut content, &bytes[0], usize(length)) || !file_backup_write(fd, &bytes[0], length, index * file_backup_chunk) { return plan_error(c'restoration write failed') }
	}
	mut restored := [32]u8{}
	if at != version.records || offset != u64(info.st_size) || !data_sha_finish(content, unsafe { &restored }) || restored != version.content
		|| !file_backup_same(archive.source, &info) || (version.delta && !file_backup_same(base.source, &base_info))
		|| !file_backup_restore_metadata(fd, &version) || !file_backup_publish(unsafe { &fd }, unsafe { &owned }, destination, &temporary[0]) { return plan_error(c'restoration validation or durable no-overwrite publication failed') }
	return file_backup_report(&version, true)
}
