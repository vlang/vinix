// SPDX-License-Identifier: GPL-2.0-or-later
// Bounded ordinary records and atomic publication under a stable sibling lock.
module main

#include <sys/file.h>

fn activity_preferences_home(home string) string {
	if home.len == 0 || home.len >= 4096 || home.index_u8(0) >= 0 { return '' }
	terminated := home.clone()
	defer { unsafe { terminated.free() } }
	mut buffer := [4096]u8{}
	if unsafe { C.realpath(&char(terminated.str), &char(&buffer[0])) } == unsafe { nil } { return '' }
	mut length := 0
	for length < buffer.len && buffer[length] != 0 { length++ }
	if length == buffer.len { return '' }
	return unsafe { tos(&buffer[0], length) }.clone()
}

fn activity_read_view_preferences(directory int) (ActivityViewPreferences, PreferenceFileState) {
	if directory < 0 { return ActivityViewPreferences{}, .invalid }
	fd := C.openat(directory, c'.vinix-activity-settings', C.O_RDONLY | C.O_CLOEXEC | C.O_NONBLOCK | C.O_NOFOLLOW, 0)
	if fd < 0 {
		return ActivityViewPreferences{}, if C.errno == C.ENOENT { PreferenceFileState.missing } else { PreferenceFileState.invalid }
	}
	defer { desktop_close(fd) }
	mut info := C.stat{}
	if unsafe { C.fstat(fd, &info) } != 0 || u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG)
		|| info.st_size <= 0 || info.st_size > activity_preferences_limit { return ActivityViewPreferences{}, .invalid }
	// V3 heap-lifts a fixed read buffer through this parser call. Own its
	// bounded allocation explicitly so every success/error branch releases it.
	mut buffer := []u8{len: int(info.st_size) + 1}
	defer { unsafe { buffer.free() } }
	mut length := 0
	mut interrupts := 0
	for length < buffer.len {
		read := desktop_read(fd, unsafe { &u8(buffer.data) + length }, u64(buffer.len - length))
		if read < 0 && C.errno == C.EINTR && interrupts < 8 { interrupts++ continue }
		if read < 0 { return ActivityViewPreferences{}, .invalid }
		if read == 0 { break }
		length += int(read)
	}
	if length != int(info.st_size) { return ActivityViewPreferences{}, .invalid }
	p := activity_parse_view_preferences(unsafe { tos(buffer.data, length) }) or { return ActivityViewPreferences{}, .invalid }
	return p, .loaded
}

fn (mut a ActivityApp) load_view_preferences(home string) {
	if a.preferences.initialized { return }
	a.preferences.initialized = true
	canonical := activity_preferences_home(home)
	defer { unsafe { canonical.free() } }
	if canonical.len > 0 {
		a.preferences.home_fd = C.open(&char(canonical.str), C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW, 0)
	}
	p, state := activity_read_view_preferences(a.preferences.home_fd)
	a.preferences.expected = p
	a.preferences.expected_state = state
	a.preferences.attempted = p
	a.preferences.read_failed = state == .invalid
	a.preferences.status = if state == .invalid { 'activity.preferences.read_failed' } else { '' }
	a.apply_view_preferences(p)
}

fn activity_preferences_lock(directory int) int {
	if directory < 0 { return -1 }
	fd := C.openat(directory, c'.vinix-activity-settings.lock', C.O_RDWR | C.O_CREAT | C.O_CLOEXEC | C.O_NONBLOCK | C.O_NOFOLLOW, 0o600)
	if fd < 0 { return -1 }
	mut info := C.stat{}
	if unsafe { C.fstat(fd, &info) } != 0 || u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG)
		|| C.flock(fd, C.LOCK_EX | C.LOCK_NB) != 0 {
		desktop_close(fd)
		return -1
	}
	return fd
}

fn activity_preferences_own_temporary(directory int, name string, original C.stat) bool {
	mut current := C.stat{}
	return unsafe { C.fstatat(directory, &char(name.str), &current, C.AT_SYMLINK_NOFOLLOW) } == 0
		&& u32(current.st_mode) & u32(C.S_IFMT) == u32(C.S_IFREG)
		&& current.st_dev == original.st_dev && current.st_ino == original.st_ino
}

fn activity_preferences_remove_temporary(directory int, name string, original C.stat) {
	if activity_preferences_own_temporary(directory, name, original) { C.unlinkat(directory, &char(name.str), 0) }
}

fn (p &ActivityPreferenceStore) compare_record() string {
	current, state := activity_read_view_preferences(p.home_fd)
	if state == .invalid { return 'activity.preferences.save_failed' }
	if state != p.expected_state || current != p.expected { return 'activity.preferences.changed' }
	return ''
}

fn (mut p ActivityPreferenceStore) publish(next ActivityViewPreferences) string {
	data := activity_encode_view_preferences(next) or { return 'activity.preferences.save_failed' }
	defer { unsafe { data.free() } }
	lock_fd := activity_preferences_lock(p.home_fd)
	if lock_fd < 0 { return 'activity.preferences.save_failed' }
	defer { desktop_close(lock_fd) }
	before := p.compare_record()
	if before.len > 0 { return before }
	pid := C.getpid().str()
	mut temporary := ''
	defer { unsafe { pid.free() temporary.free() } }
	mut fd := -1
	for _ in 0 .. 16 {
		p.sequence++
		serial := p.sequence.str()
		unsafe { temporary.free() }
		temporary = '.vinix-activity-settings.tmp.${pid}.${serial}'
		unsafe { serial.free() }
		fd = C.openat(p.home_fd, &char(temporary.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC | C.O_NONBLOCK | C.O_NOFOLLOW, 0o600)
		if fd >= 0 { break }
		if C.errno != C.EEXIST { return 'activity.preferences.save_failed' }
	}
	if fd < 0 { return 'activity.preferences.save_failed' }
	mut identity := C.stat{}
	identified := unsafe { C.fstat(fd, &identity) } == 0
	mut published := false
	defer {
		if !published && identified { activity_preferences_remove_temporary(p.home_fd, temporary, identity) }
		if fd >= 0 { desktop_close(fd) }
	}
	if !identified || !desktop_write_all(fd, data.str, u64(data.len)) || !desktop_preferences_fsync(fd)
		|| !activity_preferences_own_temporary(p.home_fd, temporary, identity) { return 'activity.preferences.save_failed' }
	// Also preserve a record damaged or replaced by a non-cooperating writer
	// while the private sibling was being written.
	after := p.compare_record()
	if after.len > 0 { return after }
	if C.renameat(p.home_fd, &char(temporary.str), p.home_fd, c'.vinix-activity-settings') != 0 { return 'activity.preferences.save_failed' }
	published = true
	p.expected = next
	p.expected_state = .loaded
	// Rename is the publication boundary. A later sync/close failure must not
	// pretend the old record survived or attempt a destructive rollback.
	synced := archive_sync_parent(p.home_fd, fd)
	closed := desktop_close(fd) == 0
	fd = -1
	return if synced && closed { '' } else { 'activity.preferences.unsynced' }
}

fn (mut p ActivityPreferenceStore) close() {
	if p.home_fd >= 0 { desktop_close(p.home_fd) }
	p.home_fd = -1
	p.initialized = false
}
