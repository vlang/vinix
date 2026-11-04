// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed atomic peer-login qualification. Evidence and tools are read-only inputs.
@[has_globals]
module main

import crypto.sha256
import dylibclosure
import json2 as json
import os
import perfconsole
import sourcecommand
import strconv
import time

#include <errno.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>
fn C.getpgid(i32) i32
fn C.kill(i32, i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.fork() i32
fn C.usleep(u32) i32
fn C.signal(i32, voidptr) voidptr
fn C.__atomic_load_n(&i32, i32) i32
fn C.__atomic_store_n(&i32, i32, i32)

const cache = '/Users/alex/Library/Caches/vinix-codex/section14'
const original = cache + '/matched-peer-frame-atomic-fresh-20261026'
const build = original + '/build-03'
const manifest = cache + '/matched-peer-frame-atomic-fresh-20261026-seal-01/complete/inventory.json'
const manifest_sha = 'e82671ca13c4d46b18d1d9762d661f4f392be0ee888d0fb20d1de21f540c54f0'
const reviewed_manifest_bytes = u64(2930169)
const checker = cache + '/alloc-track-frame-kernel-20261026-seal-02/frame-page-seal'
const checker_sha = 'fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6'
const checker_source = '/Users/alex/code/vinix/tests/kernel-allocs/frame-page-seal.v'
const checker_source_sha = '8cd5e58df42e07760d0e1b73c49807b0ee2c7e353412e7d54aca34a7597577d4'
const revision = '9acefa77bee69247c837e97987a2377536aa41cc'
const patch_sha = 'c1891d5ffe3823d9d7bfe9b3b47ba14fab590f8e8e12f2afb0d47b28cc2bb5f6'
const fixture = original + '/bootstrap-01/source/socket-peer-login/guest.v'
const fixture_sha = '209bc73d84912d2a6ea290a8801d05082ed4449823305bbe22123e616f90bc3a'
const vexe = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v'
const v_sha = 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
const cross = '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec'
const qemu = '/opt/homebrew/Cellar/qemu/11.1.1'
const mtools = '/opt/homebrew/Cellar/mtools/4.0.49/bin'
const xorriso = '/opt/homebrew/Cellar/xorriso/1.5.8.pl02/bin/xorriso'
const arm_loader = '/Users/alex/code/vinix/boot-image/limine-bin/BOOTAA64.EFI'
const x86_limine = '/Users/alex/code/vinix/build-amd64-iso/limine'
const phase = cache + '/peer-login-atomic-runtime-20261026'
const mib = u64(1024 * 1024)
const sample_window_ms = i64(5000)
const sample_nominal_ms = i64(1000)
const moving_resource_entry = 18027
const seal_scope = 'Complete quiescent root: regular bytes, literal links and directory metadata. Symlinks are never traversed. External link referents are not retained by this inventory. Trusted host; no hostile concurrent namespace guarantee.'
const markers = ['PEER-LOGIN failed-retry repeated-connect peer-close PASS',
	'PEER-LOGIN concurrent-connect rounds=32 PASS', 'PEER-LOGIN ALL PASS',
	'PEER-LOGIN INIT EXIT status=0']

struct Header { format string root string scope string }
struct Context {
	out string
	root string
	deadline i64
	env map[string]string
mut:
	next int
	stop i32
	failed i32
	reason string
	budget_timing BudgetTiming
	native_headers map[string]NativeHeader
}
struct NativeHeader { raw string selector string }
struct BudgetTiming {
mut:
	samples int
	previous_ms i64
	finished_ms i64
	max_gap_ms i64
	max_window_ms i64
	reason string
}
struct Child { log string mut: pid int }
struct Inventory { mut: values map[string]string entries int deadline i64 }
struct Count { mut: entries int }
struct WalkRetries { mut: attempts int reasons []string }
__global active = unsafe { &Context(nil) }

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn clock_ms() i64 { return i64(time.sys_mono_now() / 1000000) }
fn cancelled() bool {
	return perfconsole.cancelled() || (!isnil(active) &&
		(clock_ms() >= active.deadline || unsafe { C.__atomic_load_n(&active.failed, 2) } != 0))
}
fn root_path() string { return os.dir(os.dir(os.real_path(os.dir(@FILE)))) }
fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		if cancelled() { return error('cancelled while hashing') }
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}
fn pin(path string, expected string) ! {
	require(os.is_file(path) && !os.is_link(path), 'not a regular input: ' + path)!
	require(digest(path)! == expected, 'digest mismatch: ' + path)!
}
fn spawned(pid int, opaque voidptr) ! {
	mut child := unsafe { &Child(opaque) }
	child.pid = pid
	require(C.getpgid(i32(pid)) == pid, 'child lacks private process group')!
}
fn chunk(value string, opaque voidptr) ! {
	child := unsafe { &Child(opaque) }
	if child.log != '' {
		mut file := os.open_append(child.log)!
		defer { file.close() }
		file.write_string(value)!
	}
}
fn clean(pid int) ! {
	if pid <= 0 { return }
	mut status := i32(0)
	C.errno = 0
	require(C.waitpid(i32(pid), &status, C.WNOHANG) == -1 && C.errno == C.ECHILD,
		'leader was not solely reaped by sourcecommand')!
	until := clock_ms() + 5000
	for {
		C.errno = 0
		if C.kill(i32(-pid), 0) == -1 && C.errno == C.ESRCH { return }
		if clock_ms() >= until { return error('private process group remains') }
		time.sleep(20 * time.millisecond)
	}
}
fn no_children() ! {
	mut status := i32(0)
	C.errno = 0
	require(C.waitpid(-1, &status, C.WNOHANG) == -1 && C.errno == C.ECHILD,
		'owned process still has a child')!
}
fn probe(argv []string, deadline i64) !string {
	remaining := deadline - clock_ms()
	require(remaining > 0 && !cancelled(), 'sample deadline before resource probe')!
	timeout := if remaining < 3000 { f64(remaining) / 1000.0 } else { f64(3) }
	mut child := Child{}
	result := sourcecommand.capture_combined_owned(argv, active.env, timeout, 1024 * 1024,
		cancelled, chunk, spawned, &child, 0, active.root) or {
		mut failure := 'resource probe owner failed; partial raw output unavailable: ' + err.msg()
		clean(child.pid) or { failure += '; cleanup: ' + err.msg() }
		return error(failure)
	}
	clean(child.pid)!
	if result.status != 0 {
		prefix_len := if result.stdout.len < 4096 { result.stdout.len } else { 4096 }
		return error('resource probe actual exit=' + result.status.str()
			+ '; completed raw prefix only: ' + result.stdout[..prefix_len])
	}
	require(clock_ms() <= deadline, 'resource probe finished after sample deadline; completed raw not retained')!
	return result.stdout
}
fn command(argv []string, seconds f64, limit int) !sourcecommand.Output {
	active.next++
	stem := active.out + '/command-' + active.next.str()
	os.write_file(stem + '.argv.json', json.encode(argv) + '\n')!
	os.write_file(stem + '.log', '')!
	mut child := Child{log: stem + '.log'}
	start := clock_ms()
	remaining := f64(active.deadline - start) / 1000
	require(remaining > 0, 'global 1800s deadline exceeded')!
	timeout := if seconds < remaining { seconds } else { remaining }
	mut failure := ''
	result := sourcecommand.capture_combined_owned(argv, active.env, timeout, limit,
		cancelled, chunk, spawned, &child, 5, active.root) or {
		failure = err.msg()
		sourcecommand.Output{status: -999}
	}
	actual_available := failure == ''
	mut cleanup := if child.pid > 0 { 'leader reaped; group absent' } else { 'no leader was spawned' }
	clean(child.pid) or { cleanup = err.msg(); failure += '; cleanup: ' + err.msg() }
	os.write_file(stem + '.status.json', json.encode({
		'actual_exit': if actual_available { result.status.str() } else { 'unavailable' }
		'status_kind': if actual_available { 'actual child status' } else { 'interrupted or owner error; no actual status claim' }
		'bound_seconds': timeout.str()
		'output_limit_bytes': limit.str()
		'failure': failure
		'pid': child.pid.str()
		'elapsed_ms': (clock_ms() - start).str()
		'cleanup': cleanup
	}) + '\n')!
	if failure != '' { return error(failure) }
	return result
}
fn run0(argv []string, seconds f64, limit int) !string {
	result := command(argv, seconds, limit)!
	require(result.status == 0, 'command actual exit=' + result.status.str())!
	return result.stdout
}
fn checked(argv []string) !string { return run0(argv, 10, 4 * 1024 * 1024) }

// otool's default header identifies its native image selection on this host.
// Refuse universal/multiple or unfamiliar headers instead of guessing another
// CPU family. ARM64e system tools need their actual subtype selector, whereas
// ordinary ARM64 tools retain the helper's original arm64 selector.
fn native_selector(path string, text string) !string {
	require(text.len <= 65536, 'native Mach-O header output limit')!
	lines := text.trim_space().split_into_lines()
	require(lines.len == 4 && lines[0] == path + ':' && lines[1] == 'Mach header'
		&& lines[2].fields() == ['magic', 'cputype', 'cpusubtype', 'caps', 'filetype', 'ncmds', 'sizeofcmds', 'flags'],
		'expected one native Mach-O header')!
	words := lines[3].fields()
	require(words.len >= 8 && words[0] == 'MH_MAGIC_64' && words[1] == 'ARM64',
		'native ARM64 Mach-O header required; no other-family fallback')!
	for index in [5, 6] {
		require(words[index].len > 0 && words[index].len <= 10
			&& words[index].bytes().all(it >= `0` && it <= `9`), 'invalid native load-command count/size')!
	}
	require(strconv.parse_uint(words[5], 10, 32)! <= 4096
		&& strconv.parse_uint(words[6], 10, 32)! <= 4 * mib, 'native load-command count/size bound')!
	if words[2] == 'ALL' && words[3] == '0x00' { return 'arm64' }
	if words[2] == 'E' && words[3] == 'USR00' { return 'arm64e' }
	return error('unsupported native ARM64 subtype/capabilities')
}
fn checked_native(argv []string) !string {
	if argv.len != 5 || argv[0] != '/usr/bin/otool' || argv[1] != '-arch'
		|| argv[2] != 'arm64' || argv[3] !in ['-L', '-l'] {
		return checked(argv)
	}
	header := run0([argv[0], '-hv', argv[4]], 10, 65536)!
	selector := native_selector(argv[4], header)!
	if argv[4] in active.native_headers {
		previous := active.native_headers[argv[4]]
		require(previous.raw == header && previous.selector == selector,
			'native image header/selection changed between load-command observations')!
	}
	active.native_headers[argv[4]] = NativeHeader{raw: header, selector: selector}
	mut actual := argv.clone()
	actual[2] = selector
	return checked(actual)
}

fn tree_bytes(path string, depth int, deadline i64, mut count Count) !u64 {
	require(depth < 128 && count.entries < 250000 && !cancelled(), 'tree traversal bound')!
	require(clock_ms() <= deadline, 'resource walk sample deadline')!
	count.entries++
	info := os.lstat(path) or {
		if err.code() == C.ENOENT { return error_with_code('resource entry moved: ' + path, moving_resource_entry) }
		return err
	}
	kind := info.mode & 0o170000
	if kind == 0o120000 {
		literal := os.readlink(path) or {
			if err.code() == C.ENOENT { return error_with_code('resource link moved: ' + path, moving_resource_entry) }
			return err
		}
		return u64(literal.len)
	}
	if kind == 0o100000 { return info.size }
	require(kind == 0o040000, 'special output entry: ' + path)!
	mut sum := u64(0)
	names := os.ls(path) or {
		if err.code() == C.ENOENT { return error_with_code('resource directory moved: ' + path, moving_resource_entry) }
		return err
	}
	for name in names { sum += tree_bytes(path + '/' + name, depth + 1, deadline, mut count)! }
	return sum
}
fn retry_walk(code int, attempt int, now i64, deadline i64) bool {
	return code == moving_resource_entry && attempt < 2 && now < deadline
}
fn logical_bytes(deadline i64, mut retries WalkRetries) !u64 {
	for attempt in 0 .. 3 {
		require(clock_ms() <= deadline, 'resource walk retry sample deadline')!
		retries.attempts = attempt + 1
		// A retry recounts both roots with one new, shared entry budget.
		mut count := Count{}
		mut logical := u64(0)
		mut failure := ''
		mut code := 0
		for path in [phase, active.root] {
			logical += tree_bytes(path, 0, deadline, mut count) or { failure = err.msg(); code = err.code(); break }
		}
		if failure == '' { return logical }
		retries.reasons << if failure.len <= 4096 { failure } else { failure[..4096] }
		if !retry_walk(code, attempt, clock_ms(), deadline) {
			return error_with_code(failure, code)
		}
	}
	return error('resource walk retry limit')
}
fn budget_values(free u64, allocated u64, logical u64, admission bool) ! {
	require(free >= if admission { 2 * 1024 * mib } else { 1024 * mib }, 'free-space floor')!
	require(allocated <= 512 * mib && logical <= 512 * mib, '512MiB inclusive phase/worktree cap')!
	if admission { require(logical + 400 * mib <= 448 * mib, '400MiB projection exceeds admission budget')! }
}
fn sample_timing(gap i64, window i64) ! {
	require(gap >= 0 && window >= 0 && gap <= sample_window_ms && window <= sample_window_ms,
		'actual resource sample gap/window exceeds 5s')!
}
fn final_timing(end i64, deadline i64, sample_start i64) ! {
	require(end < deadline, 'global deadline after runtime result write')!
	sample_timing(0, end - sample_start)!
}
fn sample_deadline(start i64) i64 {
	deadline := start + sample_window_ms
	return if deadline < active.deadline { deadline } else { active.deadline }
}
fn budget_until(admission bool, deadline i64, mut retries WalkRetries) !string {
	df := probe(['/bin/df', '-k', phase], deadline)!
	lines := df.trim_space().split_into_lines()
	require(lines.len == 2, 'unexpected df output')!
	columns := lines[1].fields()
	require(columns.len >= 4, 'short df output')!
	free := strconv.parse_uint(columns[3], 10, 64)! * 1024
	du := probe(['/usr/bin/du', '-skl', phase, active.root], deadline)!
	mut blocks := u64(0)
	for line in du.trim_space().split_into_lines() {
		fields := line.fields()
		require(fields.len >= 2, 'short du output')!
		blocks += strconv.parse_uint(fields[0], 10, 64)! * 1024
	}
	logical := logical_bytes(deadline, mut retries)!
	budget_values(free, blocks, logical, admission)!
	require(clock_ms() <= deadline, 'resource measurement exceeded sample/global deadline')!
	return json.encode({'df': df, 'du': du, 'logical_bytes': logical.str(), 'admission': admission.str()})
}
fn budget(admission bool) !string {
	start := clock_ms()
	mut retries := WalkRetries{}
	line := budget_until(admission, sample_deadline(start), mut retries)!
	sample_timing(0, clock_ms() - start)!
	return line
}
// The receipt is written before the final timing check, so the metrics retained
// in result.json after monitor join include the complete write/close window.
// Capture-owner errors cannot return partial in-memory probe streams; they are
// explicitly unavailable, rather than represented as complete raw evidence.
fn observed_budget(admission bool, path string, append bool, mut timing BudgetTiming) ! {
	start := clock_ms()
	gap := if timing.samples == 0 { i64(0) } else { start - timing.previous_ms }
	timing.previous_ms = start
	timing.samples++
	if gap > timing.max_gap_ms { timing.max_gap_ms = gap }
	mut failure := ''
	mut retries := WalkRetries{}
	sample_timing(gap, 0) or { failure = err.msg() }
	mut line := ''
	if failure == '' {
		line = budget_until(admission, sample_deadline(start), mut retries) or { failure = err.msg(); '' }
	}
	record := json.encode({'start_monotonic_ms': start.str(), 'gap_ms': gap.str(),
		'measurement_ms': (clock_ms() - start).str(), 'error': failure, 'budget': line,
		'logical_walk_attempts': retries.attempts.str(), 'logical_walk_errors': json.encode(retries.reasons),
		'raw_scope': 'Only a complete successful budget retains both df/du outputs. Earlier successful output may be unavailable after a later failure. Owner errors lose partial raw output; nonzero completion errors retain at most a 4096-byte prefix.'}) + '\n'
	mut opened := true
	mut file := os.open_file(path, if append { 'a' } else { 'w' }) or {
		opened = false
		failure += '; journal open: ' + err.msg()
		os.File{}
	}
	if opened {
		n := file.write_string(record) or { failure += '; journal write: ' + err.msg(); 0 }
		file.close()
		if n != record.len { failure += '; short resource journal write' }
	}
	timing.finished_ms = clock_ms()
	window := timing.finished_ms - start
	if window > timing.max_window_ms { timing.max_window_ms = window }
	sample_timing(gap, window) or { failure += '; ' + err.msg() }
	if timing.finished_ms > active.deadline { failure += '; global deadline after resource journal' }
	timing.reason = failure
	if failure != '' { return error(failure) }
}
fn monitor() {
	for unsafe { C.__atomic_load_n(&active.stop, 2) } == 0 {
		observed_budget(false, active.out + '/budgets.jsonl', true, mut active.budget_timing) or {
			active.reason = err.msg()
			unsafe { C.__atomic_store_n(&active.failed, 1, 3) }
			return
		}
		// Schedule from the actual sample start; probe/walk time is not added
		// to the nominal interval. A slow successful sample starts again now.
		next := active.budget_timing.previous_ms + sample_nominal_ms
		for clock_ms() < next {
			if unsafe { C.__atomic_load_n(&active.stop, 2) } != 0 { return }
			time.sleep(20 * time.millisecond)
		}
	}
}

fn header_valid(header Header) bool {
	return header.format == 'frame-page-state-v1' && header.root == original && header.scope == seal_scope
}
fn manifest_length(size u64) ! {
	require(size == reviewed_manifest_bytes, 'reviewed fresh manifest length differs')!
}
fn original_check() ! {
	pin(manifest, manifest_sha)!
	pin(checker, checker_sha)!
	pin(checker_source, checker_source_sha)!
	manifest_length(os.file_size(manifest))!
	header := json.decode[Header](os.read_file(manifest)!)!
	require(header_valid(header), 'original manifest header mismatch')!
	text := run0([checker, 'check', original, manifest], 300, 2 * 1024 * 1024)!
	require(text == 'FRAME-PAGE COMPLETE STATE CHECK PASS\n', 'original full checker output mismatch')!
	pin(manifest, manifest_sha)!
}
fn elf_sha(arch string) string {
	return if arch == 'aarch64' { 'a9d79c09a0d575facafc23b2f65be8e94ffa423cb92e183b5d4c73719f13a469' }
		else { '2a7973b2dcb21c7b40aa4fb0fd1de6c9c29c8c6c246a4353445f5698b5150eac' }
}
fn kernel_pins() ! {
	pin(vexe, v_sha)!
	pin(fixture, fixture_sha)!
	pin(os.dir(fixture) + '/abi.h', '363c81fbbf005e6a396c43c9f66834ed31098caf2b71c89d134e623d30654a5e')!
	pin(os.dir(fixture) + '/dylibclosure/core.v', '503f30711a16017ef56a12555bf609dfb5ecb5bad4d0ec5ff18e3768caf6727c')!
	pin(build + '/source.patch', patch_sha)!
	require(os.read_file(build + '/source-revision.txt')! == revision + '\n', 'source revision mismatch')!
	sources := {
		'kernel/alloctrack/frame_page.v': 'be2b4cee4283cc4c5275cd5a1cb668a12ab2e08300c18a15b4731ca185dad48d'
		'kernel/alloctrack/track_d_alloc_track.v': '23aacc0a9c15cb1f22a6fd808c7b849d7ac203975c10118dbf9a0a509660302e'
		'kernel/file/locks.v': '74067cb8deb1f7d41bfc1deeee51af94b48ece3761078c179ed06a90d7a6a1b6'
		'kernel/memory/slab.v': '5c476a01dab2e01d8b13bcddce5be7fa6505f4e98f51875219bb360ce35a1aa4'
		'kernel/socket/public/public.v': '19b4b0a8fceaf0bbb78957d69025e7a6e8d805b1557d5f9c924067f82a3e372a'
		'kernel/socket/socket.v': '98588cce3eb94e72a89baf181178b92ea4de2a2b304d139c0f79af2571c7c3a8'
		'kernel/socket/unix/unix.v': 'c869568959cd09e16b58dbcc5400b49fdb0a1cb27275d0b73c430dce8f82f810'
	}
	for path, hash in sources { pin(build + '/source/' + path, hash)! }
	for arch in ['aarch64', 'x86_64'] {
		pin(build + '/' + arch + '/bin/vinix', elf_sha(arch))!
		argv := json.decode[[]string](os.read_file(build + '/' + arch + '/build.argv.json')!)!
		for flag in ['ARCH=' + arch, 'ALLOC_TRACK=1', 'PROD=true', 'LIMINE_MP=' + if arch == 'aarch64' { '1' } else { '0' }] {
			require(argv.filter(it == flag).len == 1, 'missing/duplicated original build flag ' + flag)!
		}
		status := json.decode[map[string]string](os.read_file(build + '/' + arch + '/build.status.json')!)!
		require(status['exit_code'] == '0' && status['reason'] == '' && status['cleanup'] == 'leader reaped; group absent', 'unqualified original build')!
	}
	pin(arm_loader, '3a23c79b75dd78fbacb6430472ce4aa5e90ef89089a4970459a0282cf44ccb4f')!
	pin(x86_limine + '/BOOTX64.EFI', 'c1d6c34cf827e0c5cb0f3546d2db8568dd29aae26833a6332db5532b823503c3')!
}

fn metadata(info os.Stat) string {
	// Reading bytes may update atime. Preserve identity, ownership, mode and
	// modification/change times; the immutable original seal remains separate.
	return json.encode({'dev': info.dev.str(), 'inode': info.inode.str(), 'nlink': info.nlink.str(),
		'mode': info.mode.str(), 'uid': info.uid.str(), 'gid': info.gid.str(), 'rdev': info.rdev.str(),
		'size': info.size.str(), 'mtime': info.mtime.str(), 'ctime': info.ctime.str()})
}
fn guest_libc_target(path string, literal string) !string {
	for arch in ['aarch64', 'x86_64'] {
		sysroot := cross + '/' + arch + '-linux-musl'
		if path == sysroot + '/lib/ld-musl-' + arch + '.so.1' {
			require(literal == '/lib/libc.so', 'unexpected fixed guest-root loader link')!
			return sysroot + '/lib/libc.so'
		}
	}
	return ''
}
// Inventory fixed inputs separately from the charged, fresh output namespace.
// Literal symlinks and their referents are retained, including tool libraries.
fn (mut inv Inventory) visit(path string, depth int) ! {
	require(depth < 128 && inv.entries < 250000 && clock_ms() < inv.deadline && !cancelled(), 'input inventory bound')!
	if 'stat:' + path in inv.values { return }
	inv.entries++
	before := os.lstat(path)!
	inv.values['stat:' + path] = metadata(before)
	kind := before.mode & 0o170000
	if kind == 0o120000 {
		literal := os.readlink(path)!
		inv.values['link:' + path] = literal
		guest := guest_libc_target(path, literal)!
		resolved := if guest != '' { guest } else { os.real_path(path) }
		if guest != '' {
			require(os.is_file(guest) && !os.is_link(guest), 'guest-root libc must be regular, not a link')!
			inv.values['interpretation:' + path] = 'Fixed target guest-root literal /lib/libc.so; same-sysroot regular referent, not host /lib/libc.so'
		}
		require(resolved != path && os.exists(resolved), 'unresolved input link: ' + path)!
		inv.values['resolved:' + path] = resolved
		inv.visit(resolved, depth + 1)!
	} else if kind == 0o100000 {
		inv.values['sha256:' + path] = digest(path)!
	} else if kind == 0o040000 {
		mut names := os.ls(path)!
		names.sort()
		inv.values['children:' + path] = json.encode(names)
		for name in names { inv.visit(path + '/' + name, depth + 1)! }
	} else { return error('special fixed input: ' + path) }
	after := os.lstat(path)!
	require(metadata(before) == metadata(after), 'input changed during inventory: ' + path)!
}
fn tool_paths() []string {
	mut paths := [os.executable(), vexe, checker, '/usr/bin/tar', '/bin/df', '/usr/bin/du',
		mtools + '/mformat', mtools + '/mmd', mtools + '/mcopy', xorriso,
		qemu + '/bin/qemu-system-aarch64', qemu + '/bin/qemu-system-x86_64']
	for arch in ['aarch64', 'x86_64'] {
		target := arch + '-linux-musl'
		for name in ['gcc', 'readelf'] { paths << cross + '/bin/' + target + '-' + name }
		for name in ['as', 'ld'] { paths << cross + '/' + target + '/bin/' + name }
		for name in ['cc1', 'collect2'] { paths << cross + '/libexec/gcc/' + target + '/14.2.0/' + name }
	}
	return paths
}
fn inputs() !map[string]string {
	tools := tool_paths()
	active.native_headers = map[string]NativeHeader{}
	// Exactly one unchanged helper traversal: its root/image/path limits,
	// dependency grammar, rpath resolution and shared-cache policy still apply.
	closure := dylibclosure.closure(tools, checked_native)!
	mut inv := Inventory{values: map[string]string{}, deadline: clock_ms() + 120000}
	mut paths := [os.dir(vexe), active.root + '/tools/sourcecommand',
		active.root + '/tests/desktop-perf/perfconsole', @FILE,
		active.root + '/tests/socket-peer-login/init.v', active.root + '/build-support/limine.conf',
		manifest, checker_source, fixture, os.dir(fixture) + '/abi.h', original + '/bootstrap-01/source/socket-peer-login/dylibclosure',
		build + '/source', build + '/source.patch', build + '/source-revision.txt', arm_loader,
		x86_limine + '/BOOTX64.EFI', x86_limine + '/limine-uefi-cd.bin',
		qemu + '/share/qemu/edk2-aarch64-code.fd', qemu + '/share/qemu/edk2-arm-vars.fd',
		qemu + '/share/qemu/edk2-x86_64-code.fd']
	for arch in ['aarch64', 'x86_64'] {
		target := arch + '-linux-musl'
		paths << cross + '/' + target
		paths << cross + '/lib/gcc/' + target + '/14.2.0'
		for suffix in ['/bin/vinix', '/build.argv.json', '/build.status.json'] { paths << build + '/' + arch + suffix }
	}
	paths << tools
	paths << closure.paths
	for path in paths { inv.visit(path, 0)! }
	for key, value in closure.metadata { inv.values['dylib:' + key] = value }
	for path, header in active.native_headers { inv.values['native-header:' + path] = json.encode(header) }
	return inv.values
}
fn marker_check(result sourcecommand.Output) ! {
	require(result.status == 0, 'QEMU did not exit naturally with status0')!
	lines := result.stdout.replace('\r', '').split_into_lines()
	for marker in markers { require(lines.filter(it == marker).len == 1, 'missing/duplicated marker: ' + marker)! }
	lower := result.stdout.to_lower()
	for failure in ['peer-login fail:', 'peer-login init fail ', 'panic', 'could not start init'] {
		require(!lower.contains(failure), 'guest failure text: ' + failure)!
	}
}
fn timing_controls() !int {
	mut count := 0
	sample_timing(sample_window_ms, sample_window_ms)!; count++
	for pair in [[sample_window_ms + 1, i64(0)]!, [i64(0), sample_window_ms + 1]!,
		[i64(-1), i64(0)]!, [i64(0), i64(-1)]!] {
		mut refused := false
		sample_timing(pair[0], pair[1]) or { refused = true }
		require(refused, 'resource timing boundary accepted')!; count++
	}
	final_timing(10000, 10001, 5000)!; count++
	for triple in [[i64(10000), i64(10000), i64(5000)]!,
		[i64(10000), i64(10001), i64(4999)]!] {
		mut refused := false
		final_timing(triple[0], triple[1], triple[2]) or { refused = true }
		require(refused, 'final runtime deadline/sample boundary accepted')!; count++
	}
	mut walk_count := Count{}
	mut walk_refused := false
	tree_bytes(active.out, 0, clock_ms() - 1, mut walk_count) or {
		walk_refused = err.msg() == 'resource walk sample deadline'; u64(0)
	}
	require(walk_refused && walk_count.entries == 0, 'expired resource walk was not refused before traversal')!; count++
	missing := active.out + '/timing-control-missing'
	require(!os.exists(missing) && !os.is_link(missing), 'fresh missing-entry control required')!
	mut missing_count := Count{}
	mut missing_tagged := false
	tree_bytes(missing, 0, sample_deadline(clock_ms()), mut missing_count) or {
		missing_tagged = err.code() == moving_resource_entry; u64(0)
	}
	require(missing_tagged && missing_count.entries == 1, 'actual ENOENT did not retain its moving-entry tag')!; count++
	require(retry_walk(moving_resource_entry, 0, 0, 5000) && retry_walk(moving_resource_entry, 1, 0, 5000)
		&& !retry_walk(moving_resource_entry, 2, 0, 5000) && !retry_walk(moving_resource_entry, 0, 5000, 5000)
		&& !retry_walk(0, 0, 0, 5000) && !retry_walk(int(C.EACCES), 0, 0, 5000),
		'resource retry count/deadline/policy boundary failed')!; count++
	// A closed child outlives this short probe deadline. Exercise the real
	// capture timeout/sole-reap path without waiting five seconds or consuming
	// the monitor's own deadline. Partial pipe output is not recoverable here.
	start := clock_ms()
	mut probe_failure := ''
	probe([os.executable(), '__leaf', 'probe-sleep'], start + 100) or {
		probe_failure = err.msg(); ''
	}
	require(probe_failure.contains('resource probe owner failed; partial raw output unavailable: command timed out'),
		'deadline-aware resource probe did not refuse truthfully')!
	sample_timing(0, clock_ms() - start)!; count++
	os.write_file(active.out + '/timing-controls.json', json.encode({'checks': count.str(),
		'probe_start_monotonic_ms': start.str(), 'probe_elapsed_ms': (clock_ms() - start).str(),
		'probe_error': probe_failure, 'scope': 'Timing/final-guard boundaries, pre-traversal deadline refusal, actual ENOENT classification/retry bounds and actual closed-child probe timeout only.'}) + '\n')!
	sample_timing(0, clock_ms() - start)!
	require(!cancelled(), 'phase cancelled during timing controls')!
	return count
}
fn native_header_controls() !int {
	path := '/native-header-fixture'
	prefix := path + ':\nMach header\nmagic cputype cpusubtype caps filetype ncmds sizeofcmds flags\n'
	arm := prefix + 'MH_MAGIC_64 ARM64 ALL 0x00 EXECUTE 18 1768 NOUNDEFS\n'
	arm_e := prefix + 'MH_MAGIC_64 ARM64 E USR00 EXECUTE 18 1768 NOUNDEFS\n'
	require(native_selector(path, arm)! == 'arm64' && native_selector(path, arm_e)! == 'arm64e',
		'native ARM header selection controls failed')!
	mut count := 2
	for bad in [arm.replace('ARM64', 'X86_64'), arm.replace('ALL 0x00', 'E USR01'),
		arm.replace('ALL 0x00', 'E.X1 USR00'),
		arm.replace('ALL 0x00', 'V8 0x00'), arm.replace('MH_MAGIC_64', 'MH_CIGAM_64'),
		arm.replace('ncmds sizeofcmds', 'sizeofcmds ncmds'), arm + arm,
		arm + 'trailing unparsed data\n', arm.replace(path + ':', '/unreviewed:'),
		arm.replace('18 1768', '4294967296 1768'), arm.replace('18 1768', '18 4194305'),
		arm.replace('18 1768', '-1 1768'), arm.replace('1768 NOUNDEFS', '1768')] {
		mut refused := false
		native_selector(path, bad) or { refused = true; '' }
		require(refused, 'unsupported/malformed native header was accepted')!
		count++
	}
	return count
}
fn controls() ! {
	mut manifest_cases := 0
	for delta in [-1, 0, 1] {
		mut accepted := true
		manifest_length(u64(i64(reviewed_manifest_bytes) + delta)) or { accepted = false }
		require(accepted == (delta == 0), 'fresh manifest length admission control failed')!
		manifest_cases++
	}
	timing_cases := timing_controls()!
	native_header_cases := native_header_controls()!
	mut guest_links := 0
	for arch in ['aarch64', 'x86_64'] {
		sysroot := cross + '/' + arch + '-linux-musl'
		path := sysroot + '/lib/ld-musl-' + arch + '.so.1'
		require(guest_libc_target(path, '/lib/libc.so')! == sysroot + '/lib/libc.so', 'guest-root link mapping control failed')!
		mut rejected := false
		guest_libc_target(path, '/lib/unexpected.so') or { rejected = true }
		require(rejected, 'unexpected guest-root loader literal accepted')!
		require(guest_libc_target(path + '-unexpected', '/lib/libc.so')! == '', 'unlisted path received guest-root interpretation')!
		guest_links += 3
	}
	mut boundaries := 0
	for delta in [-1, 0, 1] {
		for admission in [false, true] {
			floor := if admission { 2 * 1024 * mib } else { 1024 * mib }
			mut accepted := true
			budget_values(u64(i64(floor) + delta), 0, 0, admission) or { accepted = false }
			require(accepted == (delta >= 0), 'floor boundary control failed')!
			boundaries++
		}
		for logical in [false, true] {
			size := u64(i64(512 * mib) + delta)
			mut accepted := true
			budget_values(2 * 1024 * mib, if logical { 0 } else { size },
				if logical { size } else { 0 }, false) or { accepted = false }
			require(accepted == (delta <= 0), 'allocated/logical cap boundary control failed')!
			boundaries++
		}
		mut accepted := true
		budget_values(2 * 1024 * mib, 0, u64(i64(48 * mib) + delta), true) or { accepted = false }
		require(accepted == (delta <= 0), 'projection boundary control failed')!
		boundaries++
	}
	mut rejected := false
	pin(build + '/aarch64/bin/vinix', '0'.repeat(64)) or { rejected = true }
	require(rejected, 'wrong ELF digest was accepted')!
	require(!header_valid(Header{format: 'frame-page-state-v1', root: original + '-wrong', scope: seal_scope}), 'wrong audit root accepted')!
	for code in ['0', '7'] {
		result := command([os.executable(), '__leaf', 'markers', code], 3, 4096)!
		require(result.status == code.int(), 'control actual exit mismatch')!
		mut accepted := true
		marker_check(result) or { accepted = false }
		require(accepted == (code == '0'), 'marker/actual-exit control failed')!
	}
	mut flood := false
	command([os.executable(), '__leaf', 'flood'], 3, 1024) or {
		flood = err.msg() == 'command output exceeds limit'
	}
	require(flood, 'output-limit control did not refuse')!
	mut timed := false
	pid_file := active.out + '/control-descendant.pid'
	command([os.executable(), '__leaf', 'hold', pid_file], 0.2, 4096) or {
		timed = err.msg() == 'command timed out'
	}
	require(timed && os.exists(pid_file), 'timeout/process-group control failed')!
	os.write_file(active.out + '/controls.json', json.encode({
		'status': 'PASS'
		'scope': 'Host refusal, actual exit, pipe cap, timeout and descendant retirement only; no kernel/guest claim'
		'checks': 'wrong ELF; wrong root; nonzero with valid markers; output cap; TERM-ignoring descendant; leader ECHILD; group ESRCH'
		'budget_boundary_cases': boundaries.str()
		'guest_root_link_cases': guest_links.str()
		'timing_cases': timing_cases.str()
		'manifest_length_cases': manifest_cases.str()
		'native_header_cases': native_header_cases.str()
	}) + '\n')!
}
fn compile_program(arch string, source string, name string, state string) ! {
	cfile := state + '/' + name + '.c'
	binary := state + '/' + name
	varch := if arch == 'aarch64' { 'arm64' } else { 'amd64' }
	run0([vexe, '-nocache', '-os', 'linux', '-arch', varch, '-gc', 'none', '-d', 'no_backtrace',
		'-d', 'no_segfault_handler', '-o', cfile, source], 120, 2 * 1024 * 1024)!
	require(os.file_size(cfile) <= 8 * mib, 'generated C exceeds 8MiB')!
	target := arch + '-linux-musl'
	run0([cross + '/bin/' + target + '-gcc', '--sysroot=' + cross + '/' + target,
		'-static', '-O1', '-D_GNU_SOURCE', '-fno-stack-protector',
		'-Werror=incompatible-pointer-types', '-Wl,--trace', '-o', binary, cfile, '-lm', '-lpthread'], 120, 2 * 1024 * 1024)!
	require(os.file_size(binary) <= 2 * mib, 'static target exceeds 2MiB')!
	elf := run0([cross + '/bin/' + target + '-readelf', '-h', '-l', '-d', binary], 10, 2 * 1024 * 1024)!
	require(elf.contains('ELF64') && elf.contains(if arch == 'aarch64' { 'AArch64' } else { 'Advanced Micro Devices X86-64' }), 'target ELF architecture mismatch')!
	require(!elf.contains('INTERP') && !elf.contains('NEEDED'), 'target is not fully static')!
}
fn copy_file(from string, to string) ! { os.cp(from, to)! }
fn media(arch string, state string) ![]string {
	rootfs := state + '/rootfs'
	for path in ['sbin', 'usr/bin', 'etc', 'dev', 'proc', 'sys', 'tmp', 'root'] { os.mkdir_all(rootfs + '/' + path)! }
	copy_file(state + '/init', rootfs + '/sbin/init')!
	copy_file(state + '/peer-login', rootfs + '/usr/bin/peer-login')!
	os.chmod(rootfs + '/sbin/init', 0o755)!
	os.chmod(rootfs + '/usr/bin/peer-login', 0o755)!
	tar := state + '/initramfs.tar'
	run0(['/usr/bin/tar', '--format=ustar', '-cf', tar, '-C', rootfs, '.'], 15, 2 * 1024 * 1024)!
	require(os.file_size(tar) <= 8 * mib, 'initramfs exceeds 8MiB')!
	config := state + '/limine.conf'
	os.write_file(config, os.read_file(active.root + '/build-support/limine.conf')! + '    cmdline: vinix.qemu_platform=1\n')!
	kernel := build + '/' + arch + '/bin/vinix'
	if arch == 'aarch64' {
		payload := os.file_size(kernel) + os.file_size(tar) + os.file_size(config) + os.file_size(arm_loader)
		require(payload + payload / 8 + 8 * mib <= 64 * mib, 'ARM FAT projection exceeds 64MiB')!
		image := state + '/boot.img'
		mut file := os.create(image)!
		file.close()
		os.truncate(image, 64 * mib)!
		run0([mtools + '/mformat', '-F', '-i', image, '::'], 15, 2 * 1024 * 1024)!
		run0([mtools + '/mmd', '-i', image, '::/EFI', '::/EFI/BOOT', '::/boot'], 15, 2 * 1024 * 1024)!
		for pair in [[arm_loader, '::/EFI/BOOT/BOOTAA64.EFI'], [config, '::/boot/limine.conf'],
			[kernel, '::/boot/vinix'], [tar, '::/boot/initramfs.tar']] {
			run0([mtools + '/mcopy', '-i', image, pair[0], pair[1]], 15, 2 * 1024 * 1024)!
		}
		copy_file(qemu + '/share/qemu/edk2-arm-vars.fd', state + '/vars.fd')!
		return ['-drive', 'if=pflash,format=raw,readonly=on,file=' + qemu + '/share/qemu/edk2-aarch64-code.fd',
			'-drive', 'if=pflash,format=raw,file=' + state + '/vars.fd', '-drive', 'format=raw,file=' + image]
	}
	stage := state + '/iso-root'
	os.mkdir_all(stage + '/boot')!
	os.mkdir_all(stage + '/EFI/BOOT')!
	for pair in [[kernel, stage + '/boot/vinix'], [tar, stage + '/boot/initramfs.tar'],
		[config, stage + '/boot/limine.conf'], [x86_limine + '/limine-uefi-cd.bin', stage + '/boot/limine-uefi-cd.bin'],
		[x86_limine + '/BOOTX64.EFI', stage + '/EFI/BOOT/BOOTX64.EFI']] { copy_file(pair[0], pair[1])! }
	mut count := Count{}
	require(tree_bytes(stage, 0, sample_deadline(clock_ms()), mut count)! <= 48 * mib, 'x86 ISO staging exceeds 48MiB')!
	iso := state + '/test.iso'
	run0([xorriso, '-as', 'mkisofs', '-iso-level', '3', '-R', '-r', '-J', '--efi-boot',
		'boot/limine-uefi-cd.bin', '-efi-boot-part', '--efi-boot-image', '--protective-msdos-label', stage, '-o', iso], 15, 2 * 1024 * 1024)!
	require(os.file_size(iso) <= 64 * mib, 'x86 ISO exceeds 64MiB')!
	return ['-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=' + qemu + '/share/qemu/edk2-x86_64-code.fd', '-cdrom', iso]
}
fn target(arch string) ! {
	state := active.out + '/' + arch
	os.mkdir(state)!
	compile_program(arch, fixture, 'peer-login', state)!
	compile_program(arch, active.root + '/tests/socket-peer-login/init.v', 'init', state)!
	drives := media(arch, state)!
	mut argv := []string{}
	if arch == 'aarch64' {
		argv = [qemu + '/bin/qemu-system-aarch64', '-machine', 'virt,gic-version=3', '-accel', 'hvf',
			'-cpu', 'host', '-m', '1024', '-smp', '2', '-object', 'rng-random,filename=/dev/urandom,id=vinix-rng',
			'-device', 'virtio-rng-device,rng=vinix-rng', '-device', 'virtio-keyboard-device', '-device', 'virtio-tablet-device', '-device', 'ramfb']
	} else {
		argv = [qemu + '/bin/qemu-system-x86_64', '-machine', 'q35,smm=off', '-accel', 'tcg', '-cpu', 'max', '-m', '1024', '-smp', '2']
	}
	argv << drives
	argv << ['-display', 'none', '-monitor', 'none', '-serial', 'stdio', '-no-reboot', '-nic', 'none']
	os.write_file(state + '/qemu.argv.json', json.encode(argv) + '\n')!
	budget(false)!
	pin(build + '/' + arch + '/bin/vinix', elf_sha(arch))!
	result := command(argv, 240, 8 * 1024 * 1024)!
	marker_check(result)!
	os.write_file(state + '/qualification.json', json.encode({'status': 'PASS', 'actual_qemu_exit': result.status.str(),
		'kernel_sha256': elf_sha(arch), 'manifest_sha256': manifest_sha, 'fixture_sha256': fixture_sha,
		'scope': 'Repeated, failed-retry, peer-close, concurrent-connect tuple qualification; no cross-login provenance claim'}) + '\n')!
}

fn environment(out string) map[string]string {
	mut env := {
		'PATH': '/usr/bin:/bin:/usr/sbin:/sbin'
		'DEVELOPER_DIR': '/Library/Developer/CommandLineTools'
		'COPYFILE_DISABLE': '1'
		'V': vexe
		'VEXE': vexe
		'V_MACOS_V3_CALLER_VEXE': vexe
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1'
		'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0'
		'V_MACOS_V3_NO_FALLBACK': '1'
		'V_MACOS_V3_CALLER_NO_FALLBACK': '1'
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1'
		'VTMP': out + '/vtmp'
		'TMPDIR': out + '/tmp'
		'VMODULES': out + '/vmodules'
		'V3CACHE': out + '/v3cache'
		'XDG_CACHE_HOME': out + '/cache'
		'LC_ALL': 'C'
	}
	for key in ['HOME', 'USER', 'LOGNAME'] { env[key] = os.getenv(key) }
	return env
}
fn work(mode string) ! {
	original_check()!
	kernel_pins()!
	before := inputs()!
	os.write_file(active.out + '/inputs.before.json', json.encode(before) + '\n')!
	controls()!
	if mode == 'qualify' {
		// A single root-reserved QEMU slot is reused sequentially.
		for arch in ['aarch64', 'x86_64'] { target(arch)! }
	}
	original_check()!
	kernel_pins()!
	after := inputs()!
	os.write_file(active.out + '/inputs.after.json', json.encode(after) + '\n')!
	require(before == after, 'fixed input closure changed; no qualification')!
}
fn execute(mode string, out string) ! {
	require(mode in ['controls', 'qualify'], 'expected controls or qualify')!
	require(os.is_dir(phase) && !os.is_link(phase) && os.real_path(phase) == phase, 'phase must be a pre-created canonical directory')!
	require(os.dir(out) == phase && !os.exists(out) && !os.is_link(out), 'output must be a fresh direct child of fixed phase')!
	leaf := os.file_name(out)
	require(leaf.starts_with(if mode == 'controls' { 'controls-' } else { 'attempt-' }) &&
		leaf.bytes().all((it >= `a` && it <= `z`) || (it >= `0` && it <= `9`) || it == `-`), 'invalid output leaf')!
	os.mkdir(out)!
	mut context := &Context{out: out, root: root_path(), deadline: clock_ms() + 1800000, env: environment(out)}
	active = context
	guard := perfconsole.own_commands()
	defer { guard.close(); active = unsafe { nil } }
	for name in ['vtmp', 'tmp', 'vmodules', 'v3cache', 'cache'] { os.mkdir(out + '/' + name)! }
	os.write_file(out + '/environment.json', json.encode(context.env) + '\n')!
	os.write_file(out + '/plan.json', json.encode({
		'global_deadline_seconds': '1800'
		'fresh_phase_and_worktree_cap_bytes': (512 * mib).str()
		'projected_additional_bytes': (400 * mib).str()
		'admission_free_floor_bytes': (2 * 1024 * mib).str()
		'live_free_floor_bytes': (1024 * mib).str()
		'guest_timeout_seconds': '240 each, sequential'
		'guest_alarm_seconds': '30, immutable fixture'
		'reservation': 'One externally reserved QEMU slot; max two global; no automatic discovery/reservation claim'
		'inputs': 'Fixed original evidence/tool/sysroot/firmware measured separately; never copied wholesale into fresh phase'
		'resource_sample_nominal_ms': sample_nominal_ms.str()
		'resource_sample_max_actual_gap_and_window_ms': sample_window_ms.str()
	}) + '\n')!
	observed_budget(true, out + '/admission.json', false, mut context.budget_timing)!
	os.write_file(out + '/budgets.jsonl', '')!
	watch := spawn monitor()
	mut failure := ''
	work(mode) or { failure = err.msg() }
	unsafe { C.__atomic_store_n(&context.stop, 1, 3) }
	watch.wait()
	if context.reason != '' { failure += '; monitor: ' + context.reason }
	if cancelled() { failure += '; cancelled or global deadline exceeded' }
	no_children() or { failure += '; final children: ' + err.msg() }
	if failure == '' {
		observed_budget(false, out + '/final-budget.json', false, mut context.budget_timing) or {
			failure += '; final budget: ' + err.msg()
		}
		no_children()!
	}
	os.write_file(out + '/result.json', json.encode({
		'status': if failure == '' { 'PASS' } else { 'FAIL' }
		'failure': failure
		'mode': mode
		'source_revision': revision
		'source_patch_sha256': patch_sha
		'original_root': original
		'manifest_path': manifest
		'manifest_sha256': manifest_sha
		'manifest_bytes': reviewed_manifest_bytes.str()
		'checker_path': checker
		'checker_sha256': checker_sha
		'checker_source_path': checker_source
		'checker_source_sha256': checker_source_sha
		'fixture_path': fixture
		'fixture_sha256': fixture_sha
		'budget_timing': json.encode(context.budget_timing)
		'status_kind': 'Provisional until the final elapsed guards complete, external actual exit0 and exact PEER-LOGIN RUNTIME ' + mode + ' PASS.'
		'scope': if mode == 'qualify' { 'Both architecture peer-login fixture with immutable original full audit before/after' } else { 'Host controls only; no guest or kernel qualification' }
	}) + '\n')!
	if failure != '' { return error(failure) }
	// Refusal cleanup may exceed a deadline, but PASS must include result
	// writing inside both the absolute phase and final sample's five seconds.
	require(!cancelled(), 'phase cancelled after runtime result write')!
	final_timing(clock_ms(), context.deadline, context.budget_timing.previous_ms)!
}
fn leaf(args []string) {
	if args.len < 3 { exit(64) }
	match args[2] {
		'probe-sleep' {
			if args.len != 3 { exit(64) }
			time.sleep(250 * time.millisecond)
			return
		}
		'markers' {
			if args.len != 4 || args[3] !in ['0', '7'] { exit(64) }
			for marker in markers { println(marker) }
			exit(args[3].int())
		}
		'flood' { for _ in 0 .. 4096 { println('x'.repeat(512)) }; exit(0) }
		'hold' {
			if args.len != 4 { exit(64) }
			C.signal(C.SIGTERM, C.SIG_IGN)
			pid := C.fork()
			if pid < 0 { exit(71) }
			if pid > 0 { os.write_file(args[3], pid.str() + '\n') or { exit(74) } }
			for { C.usleep(20000) }
		}
		else { exit(64) }
	}
}
fn main() {
	if os.args.len > 1 && os.args[1] == '__leaf' { leaf(os.args); return }
	if os.args.len != 3 { eprintln('usage: runtime-check controls|qualify FRESH-OUTPUT'); exit(64) }
	execute(os.args[1], os.args[2]) or { eprintln('PEER-LOGIN RUNTIME FAIL: ' + err.msg()); exit(1) }
	println('PEER-LOGIN RUNTIME ' + os.args[1] + ' PASS')
}
