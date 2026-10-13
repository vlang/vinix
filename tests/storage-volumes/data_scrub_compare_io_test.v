// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os
import crypto.sha256

fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
fn C.fork() i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
$if macos { fn C.mkfifo(const_name &char, mode u16) i32 } $else { fn C.mkfifo(const_name &char, mode u32) i32 }

struct ScrubHistoryIO {
mut:
	active bool
	mode int
	opened int
	closed int
	reads int
	stats int
}
__global scrub_history_io ScrubHistoryIO

fn scrub_history_open(path &char, flags i32) i32 {
	if scrub_history_io.active { assert flags == C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC }
	fd := C.open(path, flags); if scrub_history_io.active && fd >= 0 { scrub_history_io.opened++ }; return fd
}
fn scrub_history_openat(directory i32, path &char, flags i32) i32 {
	if scrub_history_io.active { assert flags == C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK }
	fd := C.openat(directory, path, flags); if scrub_history_io.active && fd >= 0 { scrub_history_io.opened++ }; return fd
}
fn scrub_history_close(fd i32) i32 { if scrub_history_io.active { scrub_history_io.closed++; assert scrub_history_io.closed <= scrub_history_io.opened }; return C.close(fd) }
fn scrub_history_flock(fd i32, flags i32) i32 { assert !scrub_history_io.active; return C.flock(fd, flags) }
fn scrub_history_stat(fd i32, info &C.stat) i32 {
	scrub_history_io.stats++
	if scrub_history_io.mode == 10 || (scrub_history_io.mode == 13 && scrub_history_io.stats == 2) { return -1 }
	result := C.fstat(fd, info); if scrub_history_io.mode == 6 { unsafe { info.st_size++ } }; return result
}
fn scrub_history_read(fd i32, bytes voidptr, size usize) i64 {
	scrub_history_io.reads++
	match scrub_history_io.mode {
		1 { if scrub_history_io.reads == 1 { unsafe { C.errno = C.EINTR }; return -1 }; return C.read(fd, bytes, if size > 3 { usize(3) } else { size }) }
		2 { return 0 }
		3 { unsafe { C.errno = C.EIO }; return -1 }
		4 { return i64(size + 1) }
		5 { result := C.read(fd, bytes, size); return if result == 0 { i64(1) } else { result } }
		11 { result := C.read(fd, bytes, size); if result == 0 && scrub_history_io.reads == 2 { unsafe { C.errno = C.EINTR }; return -1 }; return result }
		12 { if scrub_history_io.reads == 3 { unsafe { C.errno = C.EIO }; return -1 }; return C.read(fd, bytes, size) }
		else { return C.read(fd, bytes, size) }
	}
}
fn scrub_history_mock_encode(before &DataScrubReport, after &DataScrubReport, output &char) int {
	assert scrub_history_io.active && scrub_history_io.opened == 4 && scrub_history_io.closed == 0
	if scrub_history_io.mode == 7 { return 0 }; return encode_data_scrub_comparison(before, after, output)
}
fn scrub_history_print(text &char) i32 {
	assert scrub_history_io.active && scrub_history_io.opened == 4 && scrub_history_io.closed == 0
	if scrub_history_io.mode == 14 { return -1 }; return C.printf(c'%s', text)
}
fn scrub_history_flush(stream voidptr) i32 { if scrub_history_io.active { assert scrub_history_io.opened == 4 && scrub_history_io.closed == 0 }; if scrub_history_io.active && scrub_history_io.mode == 8 { return -1 }; return C.fflush(stream) }
fn scrub_history_ferror(stream voidptr) i32 { if scrub_history_io.active { assert scrub_history_io.opened == 4 && scrub_history_io.closed == 0 }; if scrub_history_io.active && scrub_history_io.mode == 9 { return 1 }; return C.ferror(stream) }

fn scrub_history_input(state int) string {
	zero := '0'.repeat(64)
	return 'format=VINIXSR1 operation=scrubbed-data disks=2 mappings=2 matched=${if state == 0 { 2 } else { 1 }} changed=${int(state != 0)} algorithm=sha256 reference_sha256=${zero}\n' +
		'disk=0 slot=63 offset=0 bytes=512 readonly=1 result=match expected_sha256=${zero} actual_sha256=${zero}\n' +
		'disk=1 slot=0 offset=512 bytes=4096 readonly=0 result=${if state == 0 { 'match' } else { 'changed' }} expected_sha256=${zero} actual_sha256=${if state == 0 { zero } else if state == 1 { 'f'.repeat(64) } else { 'a'.repeat(64) }}\n'
}
fn scrub_history_expected(before int, after int) string {
	zero := '0'.repeat(64); different := before != after; result := if !different { 'stable' } else if after == 0 { 'restored' } else if before == 0 { 'new-change' } else { 'changed-again' }
	mut text := 'format=VINIXSR1 operation=compared-data-scrubs disks=2 mappings=2 stable=${if different { 1 } else { 2 }} changed=${int(different)} new_changes=${int(different && before == 0)} restored=${int(different && after == 0)} changed_again=${int(different && before != 0 && after != 0)} algorithm=sha256 reference_sha256=${zero} before_report_sha256=' + sha256.hexhash(scrub_history_input(before)) + ' after_report_sha256=' + sha256.hexhash(scrub_history_input(after)) + '\n'
	text += 'disk=0 slot=63 offset=0 bytes=512 readonly=1 before=match after=match result=stable expected_sha256=${zero} before_sha256=${zero} after_sha256=${zero}\n'
	return text + 'disk=1 slot=0 offset=512 bytes=4096 readonly=0 before=${if before == 0 { 'match' } else { 'changed' }} after=${if after == 0 { 'match' } else { 'changed' }} result=${result} expected_sha256=${zero} before_sha256=${if before == 0 { zero } else if before == 1 { 'f'.repeat(64) } else { 'a'.repeat(64) }} after_sha256=${if after == 0 { zero } else if after == 1 { 'f'.repeat(64) } else { 'a'.repeat(64) }}\n'
}
fn scrub_history_check(first string, second string, mode int, expected i32) string {
	capture := os.dir(first) + '/history-capture'; assert C.fflush(C.stdout) == 0
	saved := C.dup(1); fd := C.open(capture.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); assert saved >= 0 && fd >= 0 && C.dup2(fd, 1) == 1 && C.close(fd) == 0
	scrub_history_io = ScrubHistoryIO{active: true, mode: mode}
	unsafe { args := [&char(c'vinix-volume'), &char(c'compare-data-scrubs'), first.str, second.str, &char(nil)]!; assert run(4, &args[0]) == expected }
	assert scrub_history_io.opened == scrub_history_io.closed; scrub_history_io.active = false
	assert C.fflush(C.stdout) == 0 && C.dup2(saved, 1) == 1 && C.close(saved) == 0
	text := os.read_file(capture) or { panic(err) }; os.rm(capture) or { panic(err) }
	if expected == 1 && mode !in [8, 9] { assert !text.contains('format=VINIXSR1') && !text.contains('disk=') }; return text
}
fn test_scrub_history_real_cli_complete_input_binding_read_and_output_faults_pinned_owners() {
	work := os.join_path(os.temp_dir(), 'vinix-scrub-history-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }; first := work + '/first'; second := work + '/second'
	for before in 0 .. 3 { for after in 0 .. 3 {
		left := scrub_history_input(before); right := scrub_history_input(after); os.write_file(first, left)!; os.write_file(second, right)!; os.chmod(first, 0o644)!; os.chmod(second, 0o644)!
		for mode in 0 .. 15 {
			text := scrub_history_check(first, second, mode, if mode in [0, 1, 11] { if before == after { 0 } else { 2 } } else { 1 })
			if mode in [0, 1, 11] { assert text == scrub_history_expected(before, after) }; assert os.read_file(first)! == left && os.read_file(second)! == right
		}
		child := C.fork(); assert child >= 0
		if child == 0 { fd := C.open(c'/dev/null', C.O_RDONLY); if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(3) }; C.close(fd); scrub_history_io = ScrubHistoryIO{active: true}; result := compare_data_scrub_files(first.str, second.str); C._exit(if result == 1 && scrub_history_io.opened == scrub_history_io.closed { 0 } else { 5 }) }
		mut code := i32(-1); assert C.waitpid(child, &code, 0) == child && code == 0
	} }
	os.write_file(first, scrub_history_input(1))!; os.write_file(second, scrub_history_input(0))!
	assert scrub_history_check(first, first, 0, 0) == scrub_history_expected(1, 1)
	os.link(first, work + '/alias')!; assert scrub_history_check(first, work + '/alias', 0, 0) == scrub_history_expected(1, 1); os.rm(work + '/alias')!
	mut owner := PlanEdit{}; assert open_plan_edit(first.str, mut owner, true); assert scrub_history_check(first, second, 0, 2) == scrub_history_expected(1, 0); close_plan_edit(mut owner)
	for path in [first, second] {
		text := os.read_file(path)!
		for size in 0 .. text.len { os.write_file(path, text[..size])!; scrub_history_check(first, second, 0, 1) }; os.write_file(path, text + '\x00')!; scrub_history_check(first, second, 0, 1)
		os.write_file(path, text.replace('slot=0', 'slot=63'))!; scrub_history_check(first, second, 0, 1); os.write_file(path, 'x'.repeat(32768))!; scrub_history_check(first, second, 0, 1)
		os.write_file(path, text)!; os.mv(path, path + '.saved')!; os.symlink(path + '.saved', path)!; scrub_history_check(first, second, 0, 1); os.rm(path)!
		os.mkdir(path)!; scrub_history_check(first, second, 0, 1); os.rmdir(path)!; assert C.mkfifo(path.str, 0o600) == 0; scrub_history_check(first, second, 0, 1); os.rm(path)!; scrub_history_check(first, second, 0, 1); os.mv(path + '.saved', path)!
	}
	// Valid but different later metadata/expectations take precedence over changes.
	for pair in [['slot=0', 'slot=1'], ['offset=512', 'offset=1024'], ['bytes=4096', 'bytes=8192'], ['readonly=0', 'readonly=1'], ['disks=2', 'disks=3'], ['reference_sha256=' + '0'.repeat(64), 'reference_sha256=' + '1'.repeat(64)]] {
		text := scrub_history_input(2).replace(pair[0], pair[1]); os.write_file(second, text)!; scrub_history_check(first, second, 0, 1)
	}
	text := scrub_history_input(2).replace('result=changed expected_sha256=' + '0'.repeat(64), 'result=changed expected_sha256=' + '1'.repeat(64)); os.write_file(second, text)!; scrub_history_check(first, second, 0, 1)
}
