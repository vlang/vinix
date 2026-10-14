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

struct ScrubRefIO {
mut:
	active bool
	mode int
	opened int
	closed int
	reads int
	stats int
}
__global scrub_ref_io ScrubRefIO

fn scrub_ref_open(path &char, flags i32) i32 {
	if scrub_ref_io.active { assert flags == C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC }
	fd := C.open(path, flags); if scrub_ref_io.active && fd >= 0 { scrub_ref_io.opened++ }; return fd
}
fn scrub_ref_openat(directory i32, path &char, flags i32) i32 {
	if scrub_ref_io.active { assert flags == C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK }
	fd := C.openat(directory, path, flags); if scrub_ref_io.active && scrub_ref_io.opened == 3 { monitor_verify_fd = fd }; if scrub_ref_io.active && fd >= 0 { scrub_ref_io.opened++ }; return fd
}
fn scrub_ref_close(fd i32) i32 { if scrub_ref_io.active { scrub_ref_io.closed++; assert scrub_ref_io.closed <= scrub_ref_io.opened }; return C.close(fd) }
fn scrub_ref_flock(fd i32, flags i32) i32 { assert !scrub_ref_io.active; return C.flock(fd, flags) }
fn scrub_ref_stat(fd i32, info &C.stat) i32 {
	scrub_ref_io.stats++
	if scrub_ref_io.mode == 10 || (scrub_ref_io.mode == 13 && scrub_ref_io.stats == 2) { return -1 }
	result := C.fstat(fd, info); if scrub_ref_io.mode == 6 { unsafe { info.st_size++ } }; return result
}
fn scrub_ref_read(fd i32, bytes voidptr, size usize) i64 {
	scrub_ref_io.reads++
	match scrub_ref_io.mode {
		1 { if scrub_ref_io.reads == 1 { unsafe { C.errno = C.EINTR }; return -1 }; return C.read(fd, bytes, if size > 3 { usize(3) } else { size }) }
		2 { return 0 }
		3 { unsafe { C.errno = C.EIO }; return -1 }
		4 { return i64(size + 1) }
		5 { result := C.read(fd, bytes, size); return if result == 0 { i64(1) } else { result } }
		11 { result := C.read(fd, bytes, size); if result == 0 && scrub_ref_io.reads == 2 { unsafe { C.errno = C.EINTR }; return -1 }; return result }
		12 { if scrub_ref_io.reads == 3 { unsafe { C.errno = C.EIO }; return -1 }; return C.read(fd, bytes, size) }
		else { return C.read(fd, bytes, size) }
	}
}
fn scrub_ref_mock_encode(manifest &DataManifest, report &DataScrubReport, output &char) int {
	assert scrub_ref_io.active && scrub_ref_io.opened == 4 && scrub_ref_io.closed == 0
	if scrub_ref_io.mode == 7 { return 0 }; return encode_data_scrub_reference(manifest, report, output)
}
fn scrub_ref_print(text &char) i32 {
	assert scrub_ref_io.active && scrub_ref_io.opened == 4 && scrub_ref_io.closed == 0
	if scrub_ref_io.mode == 14 { return -1 }; return C.printf(c'%s', text)
}
fn scrub_ref_flush(stream voidptr) i32 { if scrub_ref_io.active { assert scrub_ref_io.opened == 4 && scrub_ref_io.closed == 0 }; if scrub_ref_io.active && scrub_ref_io.mode == 8 { return -1 }; return C.fflush(stream) }
fn scrub_ref_ferror(stream voidptr) i32 { if scrub_ref_io.active { assert scrub_ref_io.opened == 4 && scrub_ref_io.closed == 0 }; if scrub_ref_io.active && scrub_ref_io.mode == 9 { return 1 }; return C.ferror(stream) }

fn scrub_ref_manifest() []u8 {
	mut manifest := DataManifest{}
	for disk in 0 .. 2 {
		mut plan := Plan{count: 1, key: DiskKey{bytes: 1048576, sector: 512, kind: 1}}; plan.key.id[0] = u8(disk + 1)
		plan.rows[0] = Request{slot: if disk == 0 { u32(63) } else { u32(0) }, offset: u64(disk * 512), length: if disk == 0 { u64(512) } else { u64(4096) }, flags: u64(1 - disk)}
		assert append_plan(mut manifest.set, &plan); manifest.digests.disks[disk] = u32(disk); manifest.digests.slots[disk] = plan.rows[0].slot
	}
	manifest.digests.count = 2; mut bytes := [11392]u8{}; size := encode_data_manifest(&manifest, &bytes[0]); assert size > 0; return bytes[..size].clone()
}
fn scrub_ref_input(state int) string {
	zero := '0'.repeat(64)
	return 'format=VINIXSR1 operation=scrubbed-data disks=2 mappings=2 matched=${if state == 0 { 2 } else { 1 }} changed=${int(state != 0)} algorithm=sha256 reference_sha256=' + sha256.hexhash(scrub_ref_manifest().bytestr()) + '\n' +
		'disk=0 slot=63 offset=0 bytes=512 readonly=1 result=match expected_sha256=${zero} actual_sha256=${zero}\n' +
		'disk=1 slot=0 offset=512 bytes=4096 readonly=0 result=${if state == 0 { 'match' } else { 'changed' }} expected_sha256=${zero} actual_sha256=${if state == 0 { zero } else if state == 1 { 'f'.repeat(64) } else { 'a'.repeat(64) }}\n'
}
fn scrub_ref_expected(state int) string {
	zero := '0'.repeat(64)
	return 'format=VINIXSR1 operation=verified-data-scrub-reference disks=2 mappings=2 matched=${if state == 0 { 2 } else { 1 }} changed=${int(state != 0)} algorithm=sha256 reference_sha256=' + sha256.hexhash(scrub_ref_manifest().bytestr()) + ' report_sha256=' + sha256.hexhash(scrub_ref_input(state)) + '\n' +
		'disk=0 disk_bytes=1048576 sector=512 identity=mbr:00000001\n' +
		'disk=0 slot=63 offset=0 bytes=512 readonly=1 result=match expected_sha256=${zero} actual_sha256=${zero}\n' +
		'disk=1 disk_bytes=1048576 sector=512 identity=mbr:00000002\n' +
		'disk=1 slot=0 offset=512 bytes=4096 readonly=0 result=${if state == 0 { 'match' } else { 'changed' }} expected_sha256=${zero} actual_sha256=${if state == 0 { zero } else if state == 1 { 'f'.repeat(64) } else { 'a'.repeat(64) }}\n'
}

fn scrub_ref_check(first string, second string, mode int, expected i32) string {
	capture := os.dir(first) + '/history-capture'; assert C.fflush(C.stdout) == 0
	saved := C.dup(1); fd := C.open(capture.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); assert saved >= 0 && fd >= 0 && C.dup2(fd, 1) == 1 && C.close(fd) == 0
	scrub_ref_io = ScrubRefIO{active: true, mode: mode}
	unsafe { args := [&char(c'vinix-volume'), &char(c'verify-data-scrub-reference'), first.str, second.str, &char(nil)]!; assert run(4, &args[0]) == expected }
	assert scrub_ref_io.opened == scrub_ref_io.closed; scrub_ref_io.active = false
	assert C.fflush(C.stdout) == 0 && C.dup2(saved, 1) == 1 && C.close(saved) == 0
	text := os.read_file(capture) or { panic(err) }; os.rm(capture) or { panic(err) }
	if expected == 1 && mode !in [8, 9] { assert !text.contains('format=VINIXSR1') && !text.contains('disk=') }; return text
}

__global monitor_verify_fd i32 = -1
__global monitor_verify_reads int
__global monitor_verify_eof_interrupted bool
fn monitor_verify_stat(fd i32, info &C.stat) i32 {
	if scrub_ref_io.mode == 15 && scrub_ref_io.stats == 2 { scrub_ref_io.stats++; return -1 }; result := scrub_ref_stat(fd, info)
	if scrub_ref_io.stats == 3 { unsafe { if scrub_ref_io.mode == 16 { info.st_size++ }; if scrub_ref_io.mode == 17 { info.st_mode = (info.st_mode & ~C.S_IFMT) | C.S_IFDIR } } }; return result
}
fn monitor_verify_read(fd i32, bytes voidptr, size usize) i64 {
	assert scrub_ref_io.active && scrub_ref_io.opened == 4 && scrub_ref_io.closed == 0 && fd == monitor_verify_fd; monitor_verify_reads++
	if scrub_ref_io.mode == 18 && monitor_verify_reads == 2 { unsafe { C.errno = C.EIO }; return -1 }
	n := scrub_ref_read(fd, bytes, size)
	if scrub_ref_io.mode == 19 && n == 0 && !monitor_verify_eof_interrupted { monitor_verify_eof_interrupted = true; unsafe { C.errno = C.EINTR }; return -1 }; return n
}
fn monitor_verify_accept(manifest &DataManifest, data &u8, size int, prefix int, mut history DataMonitorHistory) bool {
	assert scrub_ref_io.active && scrub_ref_io.opened == 4 && scrub_ref_io.closed == 0; return accept_data_monitor_sample(manifest, data, size, prefix, mut history)
}
fn monitor_verify_encode(manifest &DataManifest, history &DataMonitorHistory, digest &[32]u8, output &char) int {
	assert scrub_ref_io.active && scrub_ref_io.opened == 4 && scrub_ref_io.closed == 0; if scrub_ref_io.mode == 7 { return 0 }; return encode_data_monitor_history(manifest, history, digest, output)
}
fn monitor_verify_input(states []int) string {
	mut text := ''; mut changed := 0; for sample, state in states { if state != 0 { changed++ }; text += 'format=VINIXDM1 operation=monitored-data sample=${sample + 1} changed_samples=${changed} session_changed=${int(changed != 0)}\n' + scrub_ref_input(state) }; return text
}
fn monitor_verify_wanted(states []int) string {
	zero := '0'.repeat(64); mut changed := 0; mut classes := [4]int{}; table := [[0, 1, 1]!, [2, 0, 3]!, [2, 3, 0]!]!
	for sample, state in states { if state != 0 { changed++ }; if sample != 0 { classes[table[states[sample - 1]][state]]++ } }; final := states.last(); digest := if final == 0 { zero } else if final == 1 { 'f'.repeat(64) } else { 'a'.repeat(64) }
	return 'format=VINIXDM1 operation=verified-data-monitor disks=2 mappings=2 samples=${states.len} changed_samples=${changed} session_changed=${int(changed != 0)} final_changed=${int(final != 0)} algorithm=sha256 reference_sha256=' + sha256.hexhash(scrub_ref_manifest().bytestr()) + ' transcript_sha256=' + sha256.hexhash(monitor_verify_input(states)) + '\n' +
		'disk=0 disk_bytes=1048576 sector=512 identity=mbr:00000001\ndisk=0 slot=63 offset=0 bytes=512 readonly=1 changed_samples=0 stable=${states.len - 1} new_changes=0 restored=0 changed_again=0 final=match expected_sha256=${zero} final_sha256=${zero}\n' +
		'disk=1 disk_bytes=1048576 sector=512 identity=mbr:00000002\ndisk=1 slot=0 offset=512 bytes=4096 readonly=0 changed_samples=${changed} stable=${classes[0]} new_changes=${classes[1]} restored=${classes[2]} changed_again=${classes[3]} final=${if final == 0 { 'match' } else { 'changed' }} expected_sha256=${zero} final_sha256=${digest}\n'
}
fn monitor_verify_check(first string, second string, mode int, expected i32) string {
	capture := os.dir(first) + '/verify-capture'; assert C.fflush(C.stdout) == 0; saved := C.dup(1); fd := C.open(capture.str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); assert saved >= 0 && fd >= 0 && C.dup2(fd, 1) == 1 && C.close(fd) == 0
	scrub_ref_io = ScrubRefIO{active: true, mode: mode}; monitor_verify_fd = -1; monitor_verify_reads = 0; monitor_verify_eof_interrupted = false
	unsafe { args := [&char(c'vinix-volume'), &char(c'verify-data-monitor'), first.str, second.str, &char(nil)]!; assert run(4, &args[0]) == expected }
	assert scrub_ref_io.opened == scrub_ref_io.closed; scrub_ref_io.active = false; assert C.fflush(C.stdout) == 0 && C.dup2(saved, 1) == 1 && C.close(saved) == 0
	text := os.read_file(capture) or { panic(err) }; os.rm(capture) or { panic(err) }; if expected == 1 && mode !in [8, 9] { assert !text.contains('operation=verified-data-monitor') && !text.contains('disk=') }; return text
}
fn test_monitor_verify_real_cli_complete_validation_buffering_owners_errors_and_no_partial_findings() {
	work := os.join_path(os.temp_dir(), 'vinix-monitor-verify-${os.getpid()}'); os.mkdir(work)!; defer { os.rmdir_all(work) or {} }; first := work + '/reference'; second := work + '/transcript'; manifest := scrub_ref_manifest(); os.write_file_array(first, manifest)!; os.chmod(first, 0o644)!
	for sequence in 0 .. 27 { states := [sequence % 3, (sequence / 3) % 3, sequence / 9]; transcript := monitor_verify_input(states); os.write_file(second, transcript)!; os.chmod(second, 0o644)!
		for mode in 0 .. 18 { result := if mode in [0, 1, 11] { if states.all(it == 0) { 0 } else { 2 } } else { 1 }; actual := monitor_verify_check(first, second, mode, result); if result != 1 { assert actual == monitor_verify_wanted(states) }; assert os.read_bytes(first)! == manifest && os.read_file(second)! == transcript }
		assert monitor_verify_check(first, second, 19, if states.all(it == 0) { 0 } else { 2 }) == monitor_verify_wanted(states) && monitor_verify_eof_interrupted
	}
	states := [1, 2, 0]; transcript := monitor_verify_input(states); os.write_file(second, transcript)!; monitor_verify_check(first, first, 0, 1)
	for path in [first, second] { os.link(path, path + '.alias')! }; assert monitor_verify_check(first + '.alias', second + '.alias', 0, 2) == monitor_verify_wanted(states)
	mut writer := PlanEdit{}; assert open_plan_edit(first.str, mut writer, true); assert monitor_verify_check(first, second, 0, 2) == monitor_verify_wanted(states); close_plan_edit(mut writer)
	mut boundaries := map[int]int{}; for i in 1 .. states.len + 1 { boundaries[monitor_verify_input(states[..i]).len] = i }
	for size in 0 .. transcript.len { os.write_file(second, transcript[..size])!; count := boundaries[size]; actual := monitor_verify_check(first, second, 0, if count > 0 { 2 } else { 1 }); if count > 0 { assert actual == monitor_verify_wanted(states[..count]) } }; os.write_file(second, transcript)!
	for pair in [['sample=2', 'sample=3'], ['sample=2', 'sample=02'], ['changed_samples=2', 'changed_samples=1'], ['session_changed=1', 'session_changed=0'], ['slot=0', 'slot=1'], ['readonly=0', 'readonly=1'], ['offset=512', 'offset=1024'], ['bytes=4096', 'bytes=8192'], ['reference_sha256=' + sha256.hexhash(manifest.bytestr()), 'reference_sha256=' + '1'.repeat(64)]] { os.write_file(second, transcript.replace(pair[0], pair[1]))!; monitor_verify_check(first, second, 0, 1) }
	for suffix in ['\x00', 'vinix-volume: checksum disk identity or geometry changed\n', '\n', 'format=VINIXDM1 operation=monitored-data sample=4'] { os.write_file(second, transcript + suffix)!; monitor_verify_check(first, second, 0, 1) }
	for at in 0 .. manifest.len { mut bad := manifest.clone(); bad[at] ^= 1; os.write_file_array(first, bad)!; os.write_file(second, transcript)!; monitor_verify_check(first, second, 0, 1) }; os.write_file_array(first, manifest)!
	for path in [first, second] { bytes := os.read_bytes(path)!; os.mv(path, path + '.saved')!; os.symlink(path + '.saved', path)!; monitor_verify_check(first, second, 0, 1); os.rm(path)!; os.mkdir(path)!; monitor_verify_check(first, second, 0, 1); os.rmdir(path)!; assert C.mkfifo(path.str, 0o600) == 0; monitor_verify_check(first, second, 0, 1); os.rm(path)!; monitor_verify_check(first, second, 0, 1); os.mv(path + '.saved', path)!; assert os.read_bytes(path)! == bytes }
	long_states := []int{len: 512, init: index % 3}; os.write_file(second, monitor_verify_input(long_states))!; assert monitor_verify_check(first, second, 0, 2) == monitor_verify_wanted(long_states) && monitor_verify_reads < 16; monitor_verify_check(first, second, 18, 1)
	// Oversized inputs reject at stat before transcript reads; caller state stays private.
	os.truncate(second, 67108865)!; monitor_verify_check(first, second, 0, 1); assert monitor_verify_reads == 0; os.write_file(second, transcript)!
	child := C.fork(); assert child >= 0; if child == 0 { fd := C.open(c'/dev/null', C.O_RDONLY); if fd < 0 || C.dup2(fd, 1) != 1 { C._exit(3) }; C.close(fd); scrub_ref_io = ScrubRefIO{active: true}; result := verify_data_monitor_files(first.str, second.str); C._exit(if result == 1 && scrub_ref_io.opened == scrub_ref_io.closed { 0 } else { 5 }) }; mut code := i32(-1); assert C.waitpid(child, &code, 0) == child && code == 0
}
