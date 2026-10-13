// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
$if macos {
	fn C.mkfifo(const_name &char, mode u16) i32
} $else {
	fn C.mkfifo(const_name &char, mode u32) i32
}
fn C.fork() i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32

struct ScrubViewIO {
mut:
	active bool
	mode int
	opened int
	closed int
	reads int
}
__global scrub_view_io ScrubViewIO

fn scrub_view_open(path &char, flags i32) i32 {
	if scrub_view_io.active { assert flags == C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC }
	fd := C.open(path, flags); if scrub_view_io.active && fd >= 0 { scrub_view_io.opened++ }; return fd
}
fn scrub_view_openat(directory i32, path &char, flags i32) i32 {
	if scrub_view_io.active { assert flags == C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK }
	fd := C.openat(directory, path, flags); if scrub_view_io.active && fd >= 0 { scrub_view_io.opened++ }; return fd
}
fn scrub_view_close(fd i32) i32 {
	if scrub_view_io.active { scrub_view_io.closed++; assert scrub_view_io.closed <= scrub_view_io.opened }
	return C.close(fd)
}
fn scrub_view_flock(fd i32, flags i32) i32 { assert !scrub_view_io.active; return C.flock(fd, flags) }
fn scrub_view_stat(fd i32, info &C.stat) i32 {
	if scrub_view_io.active && scrub_view_io.mode == 10 { return -1 }
	result := C.fstat(fd, info)
	if scrub_view_io.active && scrub_view_io.mode == 6 { unsafe { info.st_size++ } }
	return result
}
fn scrub_view_read(fd i32, bytes voidptr, size usize) i64 {
	scrub_view_io.reads++
	match scrub_view_io.mode {
		1 { if scrub_view_io.reads == 1 { unsafe { C.errno = C.EINTR }; return -1 }; return C.read(fd, bytes, if size > 3 { usize(3) } else { size }) }
		2 { return 0 }
		3 { unsafe { C.errno = C.EIO }; return -1 }
		4 { return i64(size + 1) }
		5 { result := C.read(fd, bytes, size); return if result == 0 { i64(1) } else { result } }
		11 { result := C.read(fd, bytes, size); if result == 0 && scrub_view_io.reads == 2 { unsafe { C.errno = C.EINTR }; return -1 }; return result }
		else { return C.read(fd, bytes, size) }
	}
}
fn scrub_view_print(text &u8) i32 {
	assert scrub_view_io.active && scrub_view_io.opened == 2 && scrub_view_io.closed == 0
	if scrub_view_io.mode == 7 { return -1 }; return C.printf(c'%s', text)
}
fn scrub_view_flush(stream voidptr) i32 {
	if scrub_view_io.active { assert scrub_view_io.opened == 2 && scrub_view_io.closed == 0 }
	if scrub_view_io.active && scrub_view_io.mode == 8 { return -1 }; return C.fflush(stream)
}
fn scrub_view_ferror(stream voidptr) i32 {
	if scrub_view_io.active { assert scrub_view_io.opened == 2 && scrub_view_io.closed == 0 }
	if scrub_view_io.active && scrub_view_io.mode == 9 { return 1 }; return C.ferror(stream)
}

fn scrub_view_text(changed bool) string {
	zero := '0'.repeat(64)
	return 'format=VINIXSR1 operation=scrubbed-data disks=2 mappings=2 matched=${if changed { 1 } else { 2 }} changed=${int(changed)} algorithm=sha256 reference_sha256=${zero}\n' +
		'disk=0 slot=63 offset=0 bytes=512 readonly=1 result=match expected_sha256=${zero} actual_sha256=${zero}\n' +
		'disk=1 slot=0 offset=512 bytes=4096 readonly=0 result=${if changed { 'changed' } else { 'match' }} expected_sha256=${zero} actual_sha256=${if changed { 'f'.repeat(64) } else { zero }}\n'
}

fn scrub_view_check(path string, mode int, expected i32) string {
	capture := os.dir(path) + '/view-capture'; assert C.fflush(C.stdout) == 0
	saved := C.dup(1); fd := C.open(capture.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); assert saved >= 0 && fd >= 0 && C.dup2(fd, 1) == 1 && C.close(fd) == 0
	scrub_view_io = ScrubViewIO{active: true, mode: mode}
	unsafe { args := [&char(c'vinix-volume'), &char(c'show-data-scrub'), path.str, &char(nil)]!; assert run(3, &args[0]) == expected }
	assert scrub_view_io.opened == scrub_view_io.closed
	scrub_view_io.active = false; assert C.fflush(C.stdout) == 0 && C.dup2(saved, 1) == 1 && C.close(saved) == 0
	text := os.read_file(capture) or { panic(err) }; os.rm(capture) or { panic(err) }
	if expected == 1 && mode !in [8, 9] { assert !text.contains('format=VINIXSR1') && !text.contains('disk=') }; return text
}

fn test_scrub_view_real_readers_balanced_descriptors_pinned_output_and_error_precedence() {
	work := os.join_path(os.temp_dir(), 'vinix-scrub-view-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	path := work + '/report'
	for changed in [false, true] {
		text := scrub_view_text(changed); os.write_file(path, text)!; os.chmod(path, 0o644)!
		for mode in 0 .. 12 {
			result := scrub_view_check(path, mode, if mode in [0, 1, 11] { 0 } else { 1 })
			if mode in [0, 1, 11] { assert result == text }; assert os.read_file(path)! == text
		}
		os.link(path, work + '/alias')!; assert scrub_view_check(work + '/alias', 0, 0) == text; os.rm(work + '/alias')!
		mut owner := PlanEdit{}; assert open_plan_edit(path.str, mut owner, true)
		assert scrub_view_check(path, 0, 0) == text; close_plan_edit(mut owner)
		child := C.fork(); assert child >= 0
		if child == 0 {
			fd := C.open(c'/dev/null', C.O_RDONLY); if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(3) }; C.close(fd)
			scrub_view_io = ScrubViewIO{active: true}; result := show_data_scrub_file(path.str)
			C._exit(if result == 1 && scrub_view_io.opened == scrub_view_io.closed { 0 } else { 5 })
		}
		mut code := i32(-1); assert C.waitpid(child, &code, 0) == child && code == 0
		for size in 0 .. text.len { os.write_file(path, text[..size])!; scrub_view_check(path, 0, 1) }
		os.write_file(path, text.replace('slot=0', 'slot=63'))!; scrub_view_check(path, 0, 1)
		os.write_file(path, text + '\x00')!; scrub_view_check(path, 0, 1)
	}
	os.write_file(path, 'x'.repeat(32768))!; scrub_view_check(path, 0, 1)
	os.mv(path, path + '.saved')!; os.symlink(path + '.saved', path)!; scrub_view_check(path, 0, 1); os.rm(path)!
	os.mkdir(path)!; scrub_view_check(path, 0, 1); os.rmdir(path)!
	assert C.mkfifo(path.str, 0o600) == 0; scrub_view_check(path, 0, 1); os.rm(path)!
	scrub_view_check(path, 0, 1)
}
