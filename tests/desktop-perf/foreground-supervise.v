// SPDX-License-Identifier: GPL-2.0-or-later
// Foreground owner for the maintained prepared performance adapters.
@[has_globals]
module main

import crypto.sha256
import json2
import os
import perfconsole
import perfreport
import perfrunner
import sourcecommand
import time

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
fn C.getpgid(i32) i32
fn C.getppid() i32
fn C.fork() i32

struct Profile {
	adapter string
	prepared_state string
	prepared_sha256 string
	directory string
	timeout_seconds int
	log_limit_bytes int
	charged_limit_kib int = 524288
	charged_roots []string
	input_roots []string
}

struct AuditProfile {
	format int = 1
	charged_limit_kib int = 524288
	charged_roots []string
}

struct AuditSpec {
	root string
	manifest string
	manifest_sha256 string
}

const audit_checker = '/Users/alex/Library/Caches/vinix-codex/section14/alloc-track-frame-kernel-20261026-seal-02/frame-page-seal'
const audit_checker_sha256 = 'fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6'
const audit_source = '/Users/alex/code/vinix/tests/kernel-allocs/frame-page-seal.v'
const audit_source_sha256 = '8cd5e58df42e07760d0e1b73c49807b0ee2c7e353412e7d54aca34a7597577d4'
const audit_marker = 'FRAME-PAGE COMPLETE STATE CHECK PASS\n'

struct PreparedView {
	arch string = 'x86_64'
	root string
	base string
	arguments []string
	command []string
	inputs map[string]string
	base_manifest string
	staged_manifest string
	storage string
	socket string
	firmware string
	sysroot string
	sysroot_manifest string
	gcc string
	gcc_manifest string
}

// A fixed preparation operation, not a caller-supplied command or environment.
struct PrepareProfile {
	arch string = 'x86_64'
	adapter string
	adapter_sha256 string
	directory string
	base string
	base_mode u32
	base_manifest_sha256 string
	kernel string
	kernel_sha256 string
	desktop string
	desktop_sha256 string
	prepared_state string
	compiler string
	qemu string
	firmware string
	cc string
	readelf string
	mkfs string
	xorriso string
	limine string
	firmware_vars string
	sysroot string
	gcc string
	linker string
	mformat string
	mmd string
	mcopy string
	sdk string
	inputs_sha256 string
	timeout_seconds int = 1800
	log_limit_bytes int = 4194304
	charged_limit_kib int = 524288
	charged_roots []string
	input_roots []string
}

struct Inventory { mut: count int }

struct BudgetReading {
	raw string
	free_kib i64
	allocated_kib i64
	apparent_kib i64
}

struct Watch {
	state string
	profile Profile
mut:
	pid int
	started u64
	next_budget u64
	last_budget u64
	last_finish u64
	attempt_start u64
	attempt_previous u64
	max_gap u64
	max_window u64
	samples int
	journal_bytes u64
	reason string
	stopped i32
	failed i32
	tasks []thread
}

const observation_interval = u64(time.second)
const observation_bound = 5 * u64(time.second)
const observation_log_limit = u64(32 * 1024 * 1024)
const observation_row_limit = u64(256 * 1024)
const observation_reserve_kib = 1024

__global active_watch = unsafe { &Watch(nil) }

fn require(ok bool, text string) ! { if !ok { return error(text) } }
fn never() bool { return false }
fn inside(path string, root string) bool { return path == root || path.starts_with(root + '/') }
fn hash_bounded(path string, deadline u64) !string {
	mut file := os.open(path)!; defer { file.close() }
	mut sum := sha256.new(); defer { unsafe { sum.free() } }
	mut buffer := []u8{len: 1024 * 1024}; defer { unsafe { buffer.free() } }
	for {
		if time.sys_mono_now() > deadline { return error('file digest deadline') }
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }; sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}
fn hash(path string) !string { return hash_bounded(path, time.sys_mono_now() + 120 * u64(time.second)) }

fn command(argv []string) !string {
	result := sourcecommand.capture(argv, os.environ(), 3, 1024 * 1024, never)!
	if result.status != 0 { return error('observation failed: ' + argv.str() + result.stderr) }
	return result.stdout
}

fn number(text string) !i64 {
	if text == '' || text.len > 15 || !text.bytes().all(it >= `0` && it <= `9`) { return error('invalid size') }
	return text.i64()
}

fn usage_total(text string) !i64 {
	mut total := i64(0)
	for line in text.trim_space().split_into_lines() {
		fields := line.fields()
		if fields.len < 2 { return error('unexpected du output') }
		value := number(fields[0])!
		if value > 9223372036854775807 - total { return error('du total overflow') }
		total += value
	}
	return total
}

fn usage_within(allocated i64, apparent i64, limit int) ! {
	if allocated > i64(limit) { return error('allocated charged-root budget exceeded') }
	if apparent > i64(limit) { return error('apparent charged-root budget exceeded') }
}

fn budget_read(profile Profile, state string) !BudgetReading {
	require(profile.charged_limit_kib >= 524288 && profile.charged_limit_kib <= 4718592, 'charged limit must be 512 MiB..4.5 GiB')!
	df := command(['/bin/df', '-k', os.dir(state)])!
	rows := df.trim_space().split_into_lines()
	if rows.len != 2 || rows[1].fields().len < 4 { return error('unexpected df output') }
	free_kib := number(rows[1].fields()[3])!
	mut roots := profile.charged_roots.clone()
	if os.exists(state) && !roots.any(inside(state, it)) { roots << state }
	mut allocated := ''
	mut apparent := ''
	mut allocated_kib := i64(0)
	mut apparent_kib := i64(0)
	if roots.len > 0 {
		allocated = command(['/usr/bin/du', '-skl', ...roots])!
		apparent = command(['/usr/bin/du', '-skAl', ...roots])!
		allocated_kib = usage_total(allocated)!
		apparent_kib = usage_total(apparent)!
	}
	return BudgetReading{raw: df + '\nallocated KiB (du -skl):\n' + allocated
		+ '\napparent KiB (du -skAl):\n' + apparent, free_kib: free_kib,
		allocated_kib: allocated_kib, apparent_kib: apparent_kib}
}

fn budget_admit(reading BudgetReading, profile Profile, admission bool) ! {
	minimum := if admission { i64(2097152) } else { i64(1048576) }
	if reading.free_kib < minimum { return error('actual df below required floor') }
	// Leave room inside the inclusive ceiling for this sample and final receipts.
	usage_within(reading.allocated_kib, reading.apparent_kib,
		profile.charged_limit_kib - observation_reserve_kib)!
}

fn budget(profile Profile, state string, admission bool) !string {
	reading := budget_read(profile, state)!
	budget_admit(reading, profile, admission)!
	return reading.raw
}

fn inventory(path string, ancestors []string, deadline u64, mut context Inventory, mut values map[string]string) ! {
	context.count++
	if context.count > 250000 || time.sys_mono_now() > deadline { return error('input inventory entry/deadline limit') }
	if ancestors.len > 128 { return error('input nesting limit') }
	info := os.lstat(path)!
	values['mode:' + path] = info.mode.str()
	if info.get_filetype() == .regular { values[path] = hash_bounded(path, deadline)!; return }
	if info.get_filetype() == .symbolic_link {
		values['link:' + path] = os.readlink(path)!
		resolved := os.real_path(path)
		if resolved == '' || resolved == path || resolved in ancestors { return error('dangling/cyclic input') }
		values['resolved:' + path] = resolved
		inventory(resolved, ancestors, deadline, mut context, mut values)!
		return
	}
	if info.get_filetype() != .directory { return error('special input: ' + path) }
	resolved := os.real_path(path)
	if resolved in ancestors { return error('cyclic directory') }
	mut next := ancestors.clone(); next << resolved
	mut names := os.ls(path)!; names.sort()
	for name in names { inventory(path + '/' + name, next, deadline, mut context, mut values)! }
}

fn inputs(paths []string) !map[string]string {
	mut result := map[string]string{}
	mut context := Inventory{}
	deadline := time.sys_mono_now() + 120 * u64(time.second)
	for path in paths { inventory(path, [], deadline, mut context, mut result)! }
	return result
}

// The cross sysroot is a guest tree. Bind its literal links without resolving
// /usr/... targets into the host filesystem. The selected compiler searches
// only the explicit include/library directories retained in the build argv.
fn literal_inventory(path string, depth int, deadline u64, mut context Inventory, mut values map[string]string) ! {
	context.count++
	require(depth <= 128 && context.count <= 250000 && time.sys_mono_now() <= deadline, 'literal inventory entry/deadline limit')!
	info := os.lstat(path)!
	values['literal-mode:' + path] = info.mode.str()
	match info.get_filetype() {
		.regular { values[path] = hash_bounded(path, deadline)! }
		.symbolic_link { values['literal-link:' + path] = os.readlink(path)! }
		.directory {
			mut names := os.ls(path)!; names.sort()
			for name in names { literal_inventory(path + '/' + name, depth + 1, deadline, mut context, mut values)! }
		}
		else { return error('special literal input: ' + path) }
	}
}

fn prepare_inputs(p PrepareProfile, paths []string) !map[string]string {
	mut result := inputs(paths)!
	mut context := Inventory{}
	deadline := time.sys_mono_now() + 120 * u64(time.second)
	literal_inventory(p.sysroot, 0, deadline, mut context, mut result)!
	if p.arch == 'x86_64' { literal_inventory(p.gcc, 0, deadline, mut context, mut result)! }
	return result
}

fn runtime_inputs(p PreparedView, paths []string) !map[string]string {
	literal_roots := prepared_literal_roots(p)
	mut filtered := []string{}
	for path in paths {
		if !literal_roots.any(inside(path, it)) { filtered << path }
	}
	mut result := inputs(filtered)!
	if literal_roots.len > 0 {
		mut context := Inventory{}
		deadline := time.sys_mono_now() + 120 * u64(time.second)
		for root in literal_roots { literal_inventory(root, 0, deadline, mut context, mut result)! }
	}
	return result
}

fn x86_closure_present(p PreparedView) bool {
	return p.sysroot != '' || p.gcc != '' || p.sysroot_manifest != '' || p.gcc_manifest != ''
}

fn prepared_literal_roots(p PreparedView) []string {
	if p.arch == 'aarch64' { return [p.sysroot] }
	if p.arch == 'x86_64' && x86_closure_present(p) { return [p.sysroot, p.gcc].filter(it != '') }
	return []string{}
}

fn x86_prepared(p PreparedView, state string) ! {
	for path in [p.sysroot, p.gcc] {
		require(path != '' && path == os.real_path(path) && os.is_dir(path), 'canonical prepared x86 build directories required')!
	}
	for pair in [['sysroot-before.tsv', p.sysroot_manifest], ['gcc-before.tsv', p.gcc_manifest]] {
		require(digest_text(pair[1]) && hash(state + '/' + pair[0])! == pair[1], 'prepared x86 literal manifest differs')!
	}
}

fn arm_command(qemu string, firmware string, state string, socket string) []string {
	return [qemu, '-machine', 'virt,gic-version=3', '-accel', 'hvf', '-cpu', 'host', '-m', '3072', '-smp', '2',
		'-object', 'rng-random,filename=/dev/urandom,id=vinix-rng', '-device', 'virtio-rng-device,rng=vinix-rng',
		'-drive', 'if=pflash,format=raw,readonly=on,file=' + firmware,
		'-drive', 'if=pflash,format=raw,file=' + state + '/vars.fd',
		'-drive', 'if=none,id=vinix-boot,format=raw,readonly=on,file=' + state + '/boot.img',
		'-device', 'virtio-blk-pci,drive=vinix-boot',
		'-drive', 'if=none,format=raw,file=' + state + '/root.ext2,id=vinix-persist',
		'-device', 'virtio-blk-device,drive=vinix-persist', '-device', 'virtio-keyboard-device',
		'-device', 'virtio-tablet-device', '-device', 'ramfb', '-display', 'none', '-serial', 'mon:stdio',
		'-qmp', 'unix:' + socket + ',server=on,wait=off', '-no-reboot', '-nic', 'none']
}

fn arm_prepared(p PreparedView, state string) ! {
	require(p.sysroot == os.real_path(p.sysroot) && os.is_dir(p.sysroot), 'canonical prepared ARM sysroot required')!
	require(digest_text(p.sysroot_manifest) && hash(state + '/sysroot-before.tsv')! == p.sysroot_manifest,
		'prepared ARM sysroot manifest differs')!
	require(p.firmware == os.real_path(p.firmware) && p.firmware in p.inputs, 'prepared ARM firmware pin missing')!
	expected_socket := '/tmp/vinix-perf-arm-' + sha256.sum(state.bytes()).hex()[..16] + '.qmp'
	require(p.socket == expected_socket && p.command.len > 0
		&& p.command == arm_command(p.command[0], p.firmware, state, expected_socket), 'fixed prepared ARM QEMU command differs')!
}

fn preserve_source(source string, destination string, depth int, deadline u64, mut context Inventory) ! {
	context.count++
	require(depth <= 128 && context.count <= 250000 && time.sys_mono_now() <= deadline, 'source copy nesting/entry/deadline limit')!
	info := os.lstat(source)!
	match info.get_filetype() {
		.symbolic_link { os.symlink(os.readlink(source)!, destination)! }
		.regular { os.cp(source, destination)!; os.chmod(destination, int(info.mode & 0o7777))! }
		.directory {
			os.mkdir(destination)!
			mut names := os.ls(source)!; names.sort()
			for name in names { preserve_source(source + '/' + name, destination + '/' + name, depth + 1, deadline, mut context)! }
			os.chmod(destination, int(info.mode & 0o7777))!
		}
		else { return error('special source copy input') }
	}
}

fn group_absent(pid int) ! {
	require(pid > 1 && pid != C.getpgid(0), 'invalid child group')!
	deadline := time.sys_mono_now() + 5 * u64(time.second)
	for {
		if C.kill(-pid, 0) == -1 {
			if C.errno == C.ESRCH { return }
			if C.errno != C.EPERM { return os.error_posix() }
		}
		if time.sys_mono_now() > deadline { return error('child group remains after owner retirement') }
		time.sleep(10 * time.millisecond)
	}
}

fn no_children() !string {
	mut raw := i32(0)
	result := C.waitpid(-1, &raw, C.WNOHANG); saved := C.errno
	if result != -1 || saved != C.ECHILD { return error('waitable child remains: ' + result.str()) }
	return 'waitpid(-1,WNOHANG)=-1;errno=ECHILD'
}

fn observation_timing(previous u64, start u64, finish u64) ! {
	if start < previous || finish < start { return error('observation clock moved backwards') }
	if previous != 0 && start - previous > observation_bound { return error('observation start gap exceeds five seconds') }
	if finish - start > observation_bound { return error('observation window exceeds five seconds') }
}

fn observation_capacity(used u64, extra u64) ! {
	if extra > observation_row_limit { return error('observation row exceeds 256 KiB') }
	if used > observation_log_limit || extra > observation_log_limit - used {
		return error('observation journal exceeds 32 MiB')
	}
}

fn journal_append(path string, text string, expected u64) ! {
	before := os.lstat(path)!
	require(before.get_filetype() == .regular && before.size == expected, 'observation journal changed')!
	fd := C.open(path.str, C.O_WRONLY | C.O_APPEND | C.O_NOFOLLOW)
	if fd < 0 { return error('cannot open observation journal') }
	mut closed := false
	defer { if !closed { C.close(fd) } }
	mut offset := 0
	for offset < text.len {
		count := C.write(fd, unsafe { text.str + offset }, usize(text.len - offset))
		if count < 0 && C.errno == C.EINTR { continue }
		if count <= 0 || count > isize(text.len - offset) { return error('observation journal write failed') }
		offset += int(count)
	}
	closed = true
	if C.close(fd) != 0 { return error('observation journal close failed') }
	after := os.lstat(path)!
	require(after.get_filetype() == .regular && after.dev == before.dev && after.inode == before.inode
		&& after.size == expected + u64(text.len), 'observation journal identity or length changed')!
}

fn budget_sample(mut watch Watch) ! {
	start := time.sys_mono_now()
	previous := if watch.last_budget == 0 { watch.started } else { watch.last_budget }
	watch.attempt_start = start
	watch.attempt_previous = previous
	observation_timing(previous, start, start)!
	observation := budget_read(watch.profile, watch.state)!
	probes_done := time.sys_mono_now()
	line := json2.encode({
		'start_ns': start.str()
		'previous_start_ns': previous.str()
		'previous_finish_ns': watch.last_finish.str()
		'probes_done_ns': probes_done.str()
		'raw': observation.raw
	}) + '\n'
	observation_capacity(watch.journal_bytes, u64(line.len))!
	journal_append(watch.state + '/budgets.jsonl', line, watch.journal_bytes)!
	finish := time.sys_mono_now()
	gap := if previous == 0 { u64(0) } else { start - previous }
	if gap > watch.max_gap { watch.max_gap = gap }
	if finish - start > watch.max_window { watch.max_window = finish - start }
	watch.last_budget = start
	watch.last_finish = finish
	watch.next_budget = start + observation_interval
	watch.journal_bytes += u64(line.len)
	watch.samples++
	observation_timing(previous, start, finish)!
	budget_admit(observation, watch.profile, false)!
}

fn budget_watch(mut watch Watch) {
	for unsafe { C.__atomic_load_n(&watch.stopped, C.__ATOMIC_RELAXED) } == 0 {
		if time.sys_mono_now() >= watch.next_budget {
			budget_sample(mut watch) or {
				watch.reason = err.msg()
				unsafe { C.__atomic_store_n(&watch.failed, 1, C.__ATOMIC_RELEASE) }
				return
			}
		}
		time.sleep(20 * time.millisecond)
	}
}

fn cancel() bool {
	return perfconsole.cancelled() || unsafe { C.__atomic_load_n(&active_watch.failed, C.__ATOMIC_ACQUIRE) } != 0
}

fn log_chunk(chunk string, context voidptr) ! {
	watch := unsafe { &Watch(context) }
	mut log := os.open_append(watch.state + '/command.log')!; defer { log.close() }
	log.write_string(chunk)!
}

fn observe(pid int, context voidptr) ! {
	mut watch := unsafe { &Watch(context) }
	watch.pid = pid
	if watch.started == 0 { watch.started = time.sys_mono_now() }
	watch.next_budget = time.sys_mono_now()
	os.write_file(watch.state + '/child.json', json2.encode({'pid': pid.str(), 'ownership': 'SDK private process group; leader reserved with WNOWAIT until retirement'}) + '\n')!
	watch.tasks << spawn budget_watch(mut watch)
}

fn supervise(profile Profile, state string, argv []string) !int {
	return supervise_core(profile, state, argv, 0, 30)
}

fn supervise_core(profile Profile, state string, argv []string, started u64, grace int) !int {
	guard := perfconsole.own_commands(); defer { guard.close() }
	mut watch := Watch{state: state, profile: profile, started: started}
	active_watch = &watch
	defer { active_watch = unsafe { nil } }
	os.write_file(state + '/argv.json', json2.encode(argv) + '\n')!
	os.write_file(state + '/environment.json', json2.encode(os.environ()) + '\n')!
	os.write_file(state + '/command.log', '')!
	os.write_file(state + '/budgets.jsonl', '')!
	mut failure := ''
	output := sourcecommand.capture_combined_owned(argv, os.environ(), f64(profile.timeout_seconds),
		profile.log_limit_bytes, cancel, log_chunk, observe, &watch, f64(grace), profile.directory) or {
		failure = err.msg()
		sourcecommand.Output{}
	}
	unsafe { C.__atomic_store_n(&watch.stopped, 1, C.__ATOMIC_RELAXED) }
	for task in watch.tasks { task.wait() }
	if watch.reason != '' { failure = watch.reason }
	mut receipt := {
		'failure': failure
		'reason': watch.reason
		'owner_status': if failure == '' { output.status.str() } else { 'unavailable after observer refusal' }
		'elapsed_ns': (time.sys_mono_now() - watch.started).str()
		'pid': watch.pid.str()
		'cleanup': 'pending'
	}
	os.write_file(state + '/supervisor.json', json2.encode(receipt) + '\n')!
	if watch.pid > 1 { group_absent(watch.pid)! }
	receipt['cleanup'] = no_children()!
	if failure == '' {
		budget_sample(mut watch) or { failure = err.msg(); watch.reason = failure }
	}
	receipt['failure'] = failure
	receipt['reason'] = watch.reason
	receipt['owner_status'] = if failure == '' { output.status.str() } else { 'unavailable after observer refusal' }
	receipt['samples'] = watch.samples.str()
	receipt['max_start_gap_ns'] = watch.max_gap.str()
	receipt['max_sample_window_ns'] = watch.max_window.str()
	receipt['journal_bytes'] = watch.journal_bytes.str()
	receipt['last_sample_start_ns'] = watch.last_budget.str()
	receipt['last_sample_finish_ns'] = watch.last_finish.str()
	receipt['attempt_start_ns'] = watch.attempt_start.str()
	receipt['attempt_previous_start_ns'] = watch.attempt_previous.str()
	os.write_file(state + '/supervisor.json', json2.encode(receipt) + '\n')!
	if failure == '' {
		observation_timing(watch.last_budget, watch.last_budget, time.sys_mono_now()) or {
			failure = err.msg()
			receipt['failure'] = failure
			receipt['owner_status'] = 'unavailable after observer refusal'
			os.write_file(state + '/supervisor.json', json2.encode(receipt) + '\n')!
		}
	}
	if failure != '' { return error(failure) }
	return output.status
}

fn fresh(state string) ! {
	require(state.starts_with('/') && os.real_path(os.dir(state)) == os.dir(state)
		&& !os.exists(state) && !os.is_link(state), 'fresh canonical external state required')!
}

fn fixed_audit(which string) !AuditSpec {
	prefix := '/Users/alex/Library/Caches/vinix-codex/section14/'
	return match which {
		'frame' { AuditSpec{prefix + 'frame-peer-baseline-fresh-20261026',
			prefix + 'frame-peer-baseline-fresh-20261026-seal-01/complete/inventory.json',
			'918073b63294c83608ef2d08b7420929c1d5148fc0464df4798a95459d71e8d9'} }
		'atomic' { AuditSpec{prefix + 'matched-peer-frame-atomic-fresh-20261026',
			prefix + 'matched-peer-frame-atomic-fresh-20261026-seal-01/complete/inventory.json',
			'e82671ca13c4d46b18d1d9762d661f4f392be0ee888d0fb20d1de21f540c54f0'} }
		else { return error('audit requires fixed frame or atomic selection') }
	}
}

fn audit_argv(spec AuditSpec) []string {
	return [audit_checker, 'check', spec.root, spec.manifest]
}

fn audit_output(path string, value string) ! {
	observation_capacity(0, u64(value.len))!
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, 0o600)
	if fd < 0 { return error('cannot exclusively create audit output') }
	if C.close(fd) != 0 { return error('audit output create close failed') }
	journal_append(path, value, 0)!
}

fn audit_admission(p AuditProfile, spec AuditSpec, state string) !Profile {
	fresh(state)!
	require(p.format == 1, 'audit profile format must be 1')!
	require(p.charged_limit_kib >= 524288 && p.charged_limit_kib <= 4718592,
		'charged limit must be 512 MiB..4.5 GiB')!
	require(p.charged_roots.len > 0, 'audit charged roots required')!
	for index, root in p.charged_roots {
		require(root == os.real_path(root) && os.is_dir(root), 'canonical audit charged root required')!
		for other in p.charged_roots[..index] {
			require(!inside(root, other) && !inside(other, root), 'overlapping audit charged roots')!
		}
	}
	require(p.charged_roots.any(inside(state, it)), 'audit state must be covered by charged roots')!
	for input in [spec.root, os.dir(spec.manifest), os.dir(audit_checker),
		'/Users/alex/code/vinix', os.real_path(@DIR + '/../..')] {
		require(!inside(state, input) && !inside(input, state), 'audit output overlaps fixed input')!
	}
	return Profile{directory: '/Users/alex/code/vinix', timeout_seconds: 300,
		log_limit_bytes: 2 * 1024 * 1024, charged_limit_kib: p.charged_limit_kib,
		charged_roots: p.charged_roots}
}

fn audit_pinned(path string, expected string, deadline u64) !string {
	require(path == os.real_path(path) && os.lstat(path)!.get_filetype() == .regular,
		'canonical ordinary audit input required')!
	actual := hash_bounded(path, deadline)!
	require(actual == expected, 'fixed audit input digest differs: ' + path)!
	return actual
}

fn audit_root_identity(path string) !string {
	require(path == os.real_path(path), 'canonical audit root required')!
	info := os.lstat(path)!
	require(info.get_filetype() == .directory, 'ordinary audit root required')!
	return json2.encode({'dev': info.dev.str(), 'inode': info.inode.str(), 'mode': info.mode.str(),
		'uid': info.uid.str(), 'gid': info.gid.str(), 'size': info.size.str(), 'nlink': info.nlink.str(),
		'mtime': info.mtime.str(), 'ctime': info.ctime.str()})
}

fn audit_pins(spec AuditSpec, profile_path string, deadline u64) !map[string]string {
	mut pins := {
		audit_checker: audit_pinned(audit_checker, audit_checker_sha256, deadline)!
		audit_source: audit_pinned(audit_source, audit_source_sha256, deadline)!
		spec.manifest: audit_pinned(spec.manifest, spec.manifest_sha256, deadline)!
		'root_identity': audit_root_identity(spec.root)!
	}
	for path in [audit_checker, audit_source, spec.manifest] {
		pins['mode:' + path] = os.lstat(path)!.mode.str()
	}
	for path in [@FILE, os.executable(), profile_path] {
		require(path == os.real_path(path) && os.lstat(path)!.get_filetype() == .regular,
			'canonical ordinary audit owner/profile input required')!
		pins[path] = hash_bounded(path, deadline)!
		pins['mode:' + path] = os.lstat(path)!.mode.str()
	}
	return pins
}

fn audit_completion(status int, output string) ! {
	require(status == 0, 'original audit child exited nonzero')!
	require(output == audit_marker, 'original audit exact marker differs')!
}

fn audit_equal(before map[string]string, after map[string]string) ! {
	require(before == after, 'audit fixed inputs changed')!
}

fn audit_tail(started u64, sampled u64, now u64) ! {
	observation_timing(sampled, sampled, now)!
	require(now >= started && now - started <= 300 * u64(time.second), 'audit total 300-second deadline exceeded')!
}

fn audit_integer(raw string) !u64 {
	require(raw != '' && raw.len <= 20, 'invalid audit timing integer')!
	mut value := u64(0)
	for byte in raw.bytes() {
		require(byte >= `0` && byte <= `9`, 'invalid audit timing integer')!
		digit := u64(byte - `0`)
		require(value <= (u64(18446744073709551615) - digit) / 10, 'audit timing integer overflow')!
		value = value * 10 + digit
	}
	return value
}

fn audit_watch(profile Profile, state string, started u64) !Watch {
	receipt := json2.decode[map[string]string](os.read_file(state + '/supervisor.json')!, strict: true)!
	require(receipt['failure'] == '' && receipt['owner_status'] == '0'
		&& receipt['cleanup'] == 'waitpid(-1,WNOHANG)=-1;errno=ECHILD', 'audit child receipt is not successful')!
	samples := audit_integer(receipt['samples'])!
	require(samples > 0 && samples < 1000000, 'audit sample count invalid')!
	return Watch{state: state, profile: profile, started: started,
		last_budget: audit_integer(receipt['last_sample_start_ns'])!,
		last_finish: audit_integer(receipt['last_sample_finish_ns'])!,
		max_gap: audit_integer(receipt['max_start_gap_ns'])!,
		max_window: audit_integer(receipt['max_sample_window_ns'])!,
		samples: int(samples), journal_bytes: audit_integer(receipt['journal_bytes'])!}
}

fn audit_owned(which string, state string, profile_path string) ! {
	started := time.sys_mono_now()
	deadline := started + 300 * u64(time.second)
	spec := fixed_audit(which)!
	require(profile_path == os.real_path(profile_path)
		&& os.lstat(profile_path)!.get_filetype() == .regular && os.file_size(profile_path) <= 65536,
		'canonical ordinary audit profile of at most 64 KiB required')!
	text := os.read_file(profile_path)!
	p := json2.decode[AuditProfile](text, strict: true)!
	require(text == json2.encode(p) + '\n', 'audit profile must use canonical typed encoding')!
	profile := audit_admission(p, spec, state)!
	admission := budget(profile, state, true)!
	os.mkdir(state)!
	audit_output(state + '/profile.json', text)!
	audit_output(state + '/budget-before.log', admission)!
	before := audit_pins(spec, profile_path, deadline)!
	require(before[profile_path] == sha256.hexhash(text), 'audit profile changed before pinning')!
	audit_output(state + '/inputs-before.json', json2.encode(before) + '\n')!
	observation_timing(started, started, time.sys_mono_now())!
	now := time.sys_mono_now()
	require(now < deadline, 'audit total deadline expired before child')!
	remaining := (deadline - now) / u64(time.second)
	require(remaining > 0 && remaining <= 300, 'audit total deadline expired before child')!
	mut failure := ''
	status := supervise_core(Profile{...profile, timeout_seconds: int(remaining)}, state,
		audit_argv(spec), started, 0) or { failure = err.msg(); -1 }
	after := audit_pins(spec, profile_path, deadline) or {
		if failure == '' { failure = err.msg() }
		map[string]string{}
	}
	audit_output(state + '/inputs-after.json', json2.encode(after) + '\n')!
	audit_equal(before, after) or { if failure == '' { failure = err.msg() } }
	audit_completion(status, os.read_file(state + '/command.log')!) or { if failure == '' { failure = err.msg() } }
	if failure != '' { return error(failure) }
	mut watch := audit_watch(profile, state, started)!
	budget_sample(mut watch)!
	audit_output(state + '/audit.json', json2.encode({
		'verdict': 'PASS'
		'which': which
		'actual_child_status': status.str()
		'checker_sha256': before[audit_checker]
		'checker_source_sha256': before[audit_source]
		'manifest_sha256': before[spec.manifest]
		'inputs_sha256': sha256.hexhash(json2.encode(before) + '\n')
		'phase_start_ns': started.str()
		'last_sample_start_ns': watch.last_budget.str()
		'last_sample_finish_ns': watch.last_finish.str()
		'samples': watch.samples.str()
		'max_start_gap_ns': watch.max_gap.str()
		'max_sample_window_ns': watch.max_window.str()
		'cleanup': 'waitpid(-1,WNOHANG)=-1;errno=ECHILD; original group absent'
	}) + '\n')!
	audit_tail(started, watch.last_budget, time.sys_mono_now())!
	println('PERF ORIGINAL AUDIT PASS ' + which)
}

fn digest_text(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn prepare_arguments(p PrepareProfile) []string {
	return ['new=' + p.desktop, '--scenarios=ops,churn,cache,idle,apps,drag', '--settle=3',
		'--seconds=5', '--rounds=1', '--mem=3072', '--timeout=2400']
}

fn prepare_argv(p PrepareProfile) []string {
	return [p.adapter, 'prepare', p.directory, p.base, p.kernel, p.prepared_state,
		...prepare_arguments(p), '--base-manifest-sha256=' + p.base_manifest_sha256]
}

fn prepare_validated(p PrepareProfile, state string) !Profile {
	fresh(state)!; fresh(p.prepared_state)!
	require(!inside(state, p.prepared_state) && !inside(p.prepared_state, state), 'preparation outputs must be separate')!
	require(p.directory == os.real_path(p.directory) && os.is_dir(p.directory), 'canonical source directory required')!
	require(p.arch in ['x86_64', 'aarch64'], 'unsupported preparation architecture')!
	require(p.base == os.real_path(p.base) && (if p.arch == 'aarch64' { os.is_file(p.base) } else { os.is_dir(p.base) }), 'canonical base directory/archive required')!
	require(os.lstat(p.base)!.mode == p.base_mode && digest_text(p.base_manifest_sha256), 'base mode and manifest pin required')!
	if p.arch == 'aarch64' { require(hash(p.base)! == p.base_manifest_sha256, 'base archive digest mismatch')! }
	require(p.timeout_seconds >= 120 && p.timeout_seconds <= 1800, 'preparation deadline must be 120..1800 seconds')!
	require(p.log_limit_bytes > 0 && p.log_limit_bytes <= 32 * 1024 * 1024, 'log limit must be 1..32 MiB')!
	require(p.charged_limit_kib >= 524288 && p.charged_limit_kib <= 4718592, 'charged limit must be 512 MiB..4.5 GiB')!
	for pair in [[p.adapter, p.adapter_sha256], [p.kernel, p.kernel_sha256], [p.desktop, p.desktop_sha256]] {
		path := pair[0]; pin := pair[1]
		require(path == os.real_path(path) && os.is_file(path) && digest_text(pin), 'canonical pinned adapter/kernel/desktop required')!
		require(hash(path)! == pin, 'preparation input digest mismatch: ' + path)!
	}
	mut executables := [p.adapter, p.compiler, p.qemu, p.cc, p.readelf, p.mkfs]
	if p.arch == 'aarch64' { executables << [p.mformat, p.mmd, p.mcopy] } else { executables << p.xorriso }
	for path in executables {
		require(path == os.real_path(path) && os.is_file(path) && os.is_executable(path), 'canonical executable preparation tool required: ' + path)!
	}
	require(p.firmware == os.real_path(p.firmware) && os.is_file(p.firmware), 'canonical firmware required')!
	for path in [p.limine, p.sdk] { require(path == os.real_path(path) && os.is_dir(path), 'canonical preparation tool directory required')! }
	require(p.linker.starts_with('/') && os.base(p.linker) == 'ld.lld' && os.is_executable(p.linker)
		&& os.is_file(os.real_path(p.linker)), 'absolute selected ld.lld driver required')!
	for path in [p.sysroot, p.gcc] {
		require(path != '' && path == os.real_path(path) && os.is_dir(path), 'canonical build directory required')!
	}
	if p.arch == 'aarch64' {
		require(p.xorriso == '', 'ARM preparation does not select xorriso')!
		require(p.firmware_vars == os.real_path(p.firmware_vars) && os.is_file(p.firmware_vars)
			&& p.firmware_vars != p.firmware, 'separate canonical ARM firmware variables required')!
		require(inside(p.gcc, p.sysroot), 'ARM GCC directory must be inside sysroot')!
		require(os.is_file(p.limine + '/BOOTAA64.EFI'), 'ARM Limine loader required')!
	} else { require(os.base(p.xorriso) == 'xorriso', 'selected xorriso filename required')! }
	require(p.input_roots.len > 0 && p.charged_roots.len > 0, 'declared input and charged roots required')!
	literal_roots := if p.arch == 'aarch64' { [p.sysroot] } else { [p.sysroot, p.gcc] }
	for root in p.input_roots {
		resolved := os.real_path(root)
		require(!inside(resolved, p.base) && !inside(p.base, resolved), 'base must use its literal adapter manifest, not the host input inventory')!
		for literal in literal_roots {
			require(!inside(resolved, literal) && !inside(literal, resolved),
				'build directories must use their literal input inventory')!
		}
	}
	for index, root in p.charged_roots {
		require(root == os.real_path(root) && os.is_dir(root), 'canonical charged root required')!
		for other in p.charged_roots[..index] { require(!inside(root, other) && !inside(other, root), 'overlapping charged roots')! }
	}
	for output in [state, p.prepared_state] {
		require(p.charged_roots.any(inside(output, it)), 'preparation output must be covered by a charged root')!
		for root in [p.directory, p.base, os.dir(p.compiler), ...p.input_roots] {
			require(root.starts_with('/') && (os.exists(root) || os.is_link(root)), 'preparation input root missing')!
			resolved := os.real_path(root)
			require(!inside(output, resolved) && !inside(resolved, output), 'preparation output overlaps an input tree')!
		}
		for literal in literal_roots {
			require(!inside(output, literal) && !inside(literal, output),
				if p.arch == 'aarch64' { 'preparation output overlaps ARM sysroot' } else { 'preparation output overlaps x86 build directory' })!
		}
	}
	return Profile{adapter: p.adapter, directory: p.directory, timeout_seconds: p.timeout_seconds,
		log_limit_bytes: p.log_limit_bytes, charged_limit_kib: p.charged_limit_kib,
		charged_roots: p.charged_roots, input_roots: p.input_roots}
}

fn prepare_environment(p PrepareProfile, state string) ! {
	for key, _ in os.environ() { if key !in ['HOME', 'USER', 'LOGNAME'] { os.unsetenv(key) } }
	for key, value in {
		'PATH': '/usr/bin:/bin:/usr/sbin:/sbin:' + (if p.arch == 'x86_64' { os.dir(p.xorriso) + ':' + os.dir(p.cc) } else { os.dir(p.cc) })
		'DEVELOPER_DIR': '/Library/Developer/CommandLineTools'
		'SDKROOT': p.sdk
		'V': p.compiler
		'VEXE': p.compiler
		'VINIX_V_COMPILER': p.compiler
		'V_MACOS_V3_CALLER_VEXE': p.compiler
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1'
		'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0'
		'V_MACOS_V3_NO_FALLBACK': '1'
		'V_MACOS_V3_CALLER_NO_FALLBACK': '1'
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1'
		'VTMP': state + '/tmp'
		'TMPDIR': state + '/tmp'
		'VMODULES': state + '/modules'
		'V3CACHE': state + '/cache'
		'XDG_CACHE_HOME': state + '/cache'
		'VINIX_PERF_READELF': p.readelf
		'VINIX_PERF_MKFS': p.mkfs
	} { os.setenv(key, value, true) }
	if p.arch == 'aarch64' {
		for key, value in {
			'VINIX_QEMU_AARCH64': p.qemu
			'VINIX_OVMF_CODE_AARCH64': p.firmware
			'VINIX_OVMF_VARS_AARCH64': p.firmware_vars
			'CC_AARCH64': p.cc
			'VINIX_AARCH64_SYSROOT': p.sysroot
			'VINIX_PERF_ARM_GCC': p.gcc
			'VINIX_PERF_ARM_LINKER': p.linker
			'VINIX_PERF_ARM_MFORMAT': p.mformat
			'VINIX_PERF_ARM_MMD': p.mmd
			'VINIX_PERF_ARM_MCOPY': p.mcopy
			'VINIX_LIMINE_BOOTAA64': os.real_path(p.limine + '/BOOTAA64.EFI')
		} { os.setenv(key, value, true) }
	} else {
		for key, value in {
			'VINIX_QEMU_X86_64': p.qemu
			'VINIX_OVMF_CODE_X86_64': p.firmware
			'CC_AMD64': p.cc
			'VINIX_PERF_X86_SYSROOT': p.sysroot
			'VINIX_PERF_X86_GCC': p.gcc
			'VINIX_PERF_X86_LINKER': p.linker
			'VINIX_PLAIN_ISO_LIMINE': p.limine
			'VINIX_PERF_X86_APFS_CLONE': '1'
		} { os.setenv(key, value, true) }
		require(os.real_path(os.find_abs_path_of_executable('xorriso')!) == p.xorriso, 'selected xorriso differs from fixed PATH')!
	}
}

fn prepare_paths(p PrepareProfile, profile_path string) ![]string {
	mut paths := p.input_roots.clone()
	for directory in ['tests/desktop-perf', 'tests/hardware-platform/hwhost', 'tests/hardware-platform/plainiso',
		'tests/linuxkpi/hosttest', 'tools/hosttest', 'tools/sourcecommand', 'tools/qmpclient'] { paths << p.directory + '/' + directory }
	clang := '/Library/Developer/CommandLineTools/usr/bin/clang'
	resource := command([clang, '-print-resource-dir'])!.trim_space()
	paths << [p.adapter, p.kernel, p.desktop, os.dir(p.compiler), p.qemu, p.firmware, p.cc, p.readelf, p.mkfs, p.linker,
		p.sdk + '/SDKSettings.json', p.sdk + '/SDKSettings.plist',
		'/bin/cp', '/usr/bin/tar', '/bin/df', '/usr/bin/du', '/usr/bin/xcrun', clang,
		'/Library/Developer/CommandLineTools/usr/bin/ld', resource + '/include', os.executable(), @FILE, profile_path]
	if p.arch == 'aarch64' {
		// The whole selected sysroot, including headers and all library search
		// directories, is inventoried. It is read in place, never copied.
		paths << [p.base, p.firmware_vars, p.mformat, p.mmd, p.mcopy, p.limine + '/BOOTAA64.EFI']
	} else { paths << [p.xorriso, p.limine + '/BOOTX64.EFI', p.limine + '/limine-uefi-cd.bin'] }
	return paths
}

fn prepared_checked(p PrepareProfile, profile Profile, state string, before map[string]string) !string {
	path := p.prepared_state + '/prepared.json'
	prepared := json2.decode[PreparedView](os.read_file(path)!)!
	require(prepared.root == p.directory && prepared.base == p.base
		&& prepared.arguments == prepare_arguments(p), 'prepared roots or fixed arguments differ')!
	require(prepared.arch == p.arch, 'prepared architecture differs')!
	require(prepared.storage == (if p.arch == 'aarch64' { 'archive-overlay' } else { 'apfs-clone' }), 'prepared storage mode differs')!
	require(prepared.base_manifest == p.base_manifest_sha256, 'prepared base manifest differs')!
	if p.arch == 'aarch64' {
		require(prepared.sysroot == p.sysroot && prepared.firmware == p.firmware, 'prepared ARM selected paths differ')!
		arm_prepared(prepared, p.prepared_state)!
		require(hash(p.base)! == p.base_manifest_sha256 && os.read_file(p.prepared_state + '/base-before.tsv')!
			== 'file\t' + p.base_manifest_sha256 + '\t' + p.base_mode.str() + '\t' + p.base + '\n', 'prepared base archive differs')!
	} else {
		require(prepared.sysroot == p.sysroot && prepared.gcc == p.gcc, 'prepared x86 selected paths differ')!
		x86_prepared(prepared, p.prepared_state)!
		require(hash(p.prepared_state + '/base-before.tsv')! == p.base_manifest_sha256, 'prepared base manifest differs')!
	}
	require(digest_text(prepared.staged_manifest)
		&& hash(p.prepared_state + '/staged-before.tsv')! == prepared.staged_manifest, 'prepared staged manifest differs')!
	require(prepared.command.len > 0 && prepared.command[0] == p.qemu, 'prepared QEMU differs')!
	for pair in [[p.adapter, p.adapter_sha256], [p.kernel, p.kernel_sha256], [p.desktop, p.desktop_sha256]] {
		input := pair[0]; pin := pair[1]
		require(prepared.inputs[input] == pin, 'prepared selected input pin differs')!
	}
	for input, pin in prepared.inputs {
		if !inside(input, p.prepared_state) {
			// Source walks retain a tools/hosttest alias-file key; the host
			// inventory binds its literal parent link and canonical referent.
			require(before[input] == pin || before[os.real_path(input)] == pin, 'prepared external input absent from approved map: ' + input)!
		}
	}
	require(os.lstat(p.base)!.mode == p.base_mode, 'base root mode changed')!
	prepared_sha := hash(path)!
	validated(Profile{...profile, prepared_state: p.prepared_state, prepared_sha256: prepared_sha, timeout_seconds: 2520}, state)!
	return prepared_sha
}

fn prepare_owned(state string, profile_path string, admission_only bool) ! {
	require(profile_path == os.real_path(profile_path) && os.is_file(profile_path), 'canonical preparation profile required')!
	profile_text := os.read_file(profile_path)!
	p := json2.decode[PrepareProfile](profile_text)!
	profile := prepare_validated(p, state)!
	admission := budget(profile, state, true)!
	// Fixed tool selection applies to both admission and execution. Private
	// caches are outputs, never inherited compiler/module cache inputs.
	prepare_environment(p, state)!
	paths := prepare_paths(p, profile_path)!
	for path in paths {
		resolved := os.real_path(path)
		for output in [state, p.prepared_state] {
			require(!inside(output, resolved) && !inside(resolved, output), 'preparation output overlaps a selected input')!
		}
	}
	before := prepare_inputs(p, paths)!
	require(before[profile_path] == sha256.sum(profile_text.bytes()).hex(), 'profile changed before inventory')!
	// The approved digest excludes the profile itself: adding that digest to
	// the profile would otherwise require a cryptographic fixed point.
	mut selected := before.clone()
	selected.delete(profile_path); selected.delete('mode:' + profile_path)
	selected_text := json2.encode(selected) + '\n'
	selected_sha := sha256.sum(selected_text.bytes()).hex()
	if !admission_only || p.inputs_sha256 != '' {
		require(digest_text(p.inputs_sha256) && p.inputs_sha256 == selected_sha, 'approved preparation input map differs')!
	}
	os.mkdir(state)!
	os.write_file(state + '/profile.json', profile_text)!
	os.write_file(state + '/budget-before.log', admission)!
	os.write_file(state + '/inputs-before.json', json2.encode(before) + '\n')!
	os.write_file(state + '/selected-inputs.json', selected_text)!
	os.write_file(state + '/argv.json', json2.encode(prepare_argv(p)) + '\n')!
	if admission_only {
		os.write_file(state + '/admission.json', json2.encode({
			'inputs_sha256': selected_sha
			'profile_sha256': sha256.sum(profile_text.bytes()).hex()
			'scope': if p.arch == 'aarch64' { 'read-only ARM archive and selected input admission; no staging or VM execution' } else { 'read-only selected input admission; base manifest pin recorded, not scanned; no staging or VM execution' }
		}) + '\n')!
		println('PERF FOREGROUND PREPARE ADMISSION ' + selected_sha)
		return
	}
	for name in ['tmp', 'modules', 'cache'] { os.mkdir(state + '/' + name)! }
	mut failure := ''
	status := supervise(profile, state, prepare_argv(p)) or { failure = err.msg(); -1 }
	after := prepare_inputs(p, paths) or {
		os.write_file(state + '/inputs-after-error.txt', err.msg() + '\n')!
		if failure == '' { failure = err.msg() }
		map[string]string{}
	}
	os.write_file(state + '/inputs-after.json', json2.encode(after) + '\n')!
	os.write_file(state + '/budget-after.log', budget(profile, state, false)!)!
	if failure != '' { return error(failure) }
	require(before == after, 'preparation input identity changed')!
	require(status == 0, 'adapter prepare exited ' + status.str())!
	prepared_sha := prepared_checked(p, profile, state, before)!
	os.write_file(state + '/preparation.json', json2.encode({
		'verdict': 'PASS'
		'prepared_sha256': prepared_sha
		'inputs_sha256': selected_sha
		'profile_sha256': sha256.sum(profile_text.bytes()).hex()
		'scope': 'fixed maintained ' + p.arch + ' prepare under foreground owner and live charged-root budget; no VM execution'
	}) + '\n')!
	println('PERF FOREGROUND PREPARE PASS ' + prepared_sha)
}

fn validated(profile Profile, state string) !PreparedView {
	require(profile.adapter.starts_with('/') && os.is_file(profile.adapter), 'absolute adapter required')!
	require(profile.prepared_state == os.real_path(profile.prepared_state) && os.is_dir(profile.prepared_state), 'canonical prepared state required')!
	require(profile.directory == os.real_path(profile.directory) && os.is_dir(profile.directory), 'canonical working directory required')!
	require(profile.timeout_seconds >= 1800 && profile.timeout_seconds <= 7200, 'outer deadline must be 1800..7200 seconds')!
	require(profile.log_limit_bytes > 0 && profile.log_limit_bytes <= 32 * 1024 * 1024, 'log limit must be 1..32 MiB')!
	require(profile.charged_limit_kib >= 524288 && profile.charged_limit_kib <= 4718592, 'charged limit must be 512 MiB..4.5 GiB')!
	require(profile.input_roots.len > 0 && profile.charged_roots.len > 0, 'declared input and charged roots required')!
	for index, root in profile.charged_roots {
		require(root == os.real_path(root) && os.is_dir(root), 'canonical charged root required')!
		for other in profile.charged_roots[..index] { require(!inside(root, other) && !inside(other, root), 'overlapping charged roots')! }
	}
	require(profile.charged_roots.any(inside(profile.prepared_state, it)), 'prepared runtime must be covered by a charged root')!
	for root in profile.input_roots {
		require(root.starts_with('/') && (os.exists(root) || os.is_link(root)) && !inside(state, os.real_path(root)), 'input root missing or contains output state')!
	}
	receipt := profile.prepared_state + '/prepared.json'
	require(hash(receipt)! == profile.prepared_sha256, 'prepared receipt digest mismatch')!
	p := json2.decode[PreparedView](os.read_file(receipt)!)!
	mutable_paths(p, profile.prepared_state)!
	if p.arch == 'aarch64' {
		arm_prepared(p, profile.prepared_state)!
		for root in profile.input_roots {
			resolved := os.real_path(root)
			require(!inside(resolved, p.sysroot) && !inside(p.sysroot, resolved), 'ARM sysroot must use its literal input inventory')!
		}
		require(!inside(state, p.sysroot) && !inside(p.sysroot, state), 'runtime output overlaps ARM sysroot')!
	} else if x86_closure_present(p) {
		x86_prepared(p, profile.prepared_state)!
		for literal in prepared_literal_roots(p) {
			for root in profile.input_roots {
				resolved := os.real_path(root)
				require(!inside(resolved, literal) && !inside(literal, resolved),
					'x86 build directories must use their literal input inventory')!
			}
			require(!inside(state, literal) && !inside(literal, state), 'runtime output overlaps x86 build directory')!
		}
	}
	require(!inside(state, p.root) && !inside(state, profile.prepared_state), 'supervisor state must be external to source and prepared state')!
	require(p.inputs[profile.adapter] == hash(profile.adapter)!, 'adapter must match prepared input pin')!
	plan := perfrunner.parse(p.arguments, p.root, p.root + '/tests/desktop-perf', '')!
	require(plan.scenarios.len == 6 && ['ops', 'churn', 'cache', 'idle', 'apps', 'drag'].all(it in plan.scenarios), 'all six performance scenarios required')!
	require(plan.timeout + 60 <= profile.timeout_seconds, 'outer deadline must include adapter timeout and 60 seconds cleanup')!
	require(p.command.len > 0 && p.command[0].starts_with('/'), 'absolute prepared QEMU required')!
	mut mux := false
	for index in 0 .. p.command.len - 1 { if p.command[index] == '-serial' && p.command[index + 1] == 'mon:stdio' { mux = true } }
	require(mux, 'prepared QEMU requires foreground serial monitor')!
	require(!os.exists(profile.prepared_state + '/results'), 'prepared adapter already executed')!
	require(!os.exists(profile.prepared_state + '/after-inputs.json'), 'stale adapter input receipt exists')!
	return p
}

fn mutable_paths(p PreparedView, state string) ![]string {
	require(p.arch in ['x86_64', 'aarch64'], 'unsupported prepared architecture')!
	mut names := ['root.ext2']
	if p.arch == 'aarch64' {
		require(p.storage == 'archive-overlay', 'ARM prepared storage differs')!
		names << 'vars.fd'
	}
	paths := names.map(state + '/' + it)
	for path in paths { require(path in p.inputs, 'prepared mutable disk pin missing')! }
	return paths
}

fn completed(profile Profile, p PreparedView) ! {
	require(os.read_file(profile.prepared_state + '/results/status')! == '0\n', 'adapter completion receipt missing')!
	after := json2.decode[map[string]string](os.read_file(profile.prepared_state + '/after-inputs.json')!)!
	mut expected := p.inputs.clone()
	for disk in mutable_paths(p, profile.prepared_state)! { expected[disk] = hash(disk)! }
	require(after == expected, 'adapter input verification receipt differs')!
	serial := os.read_file(profile.prepared_state + '/results/serial.log')!
	require(serial.split_into_lines().any(it.trim_space() == perfreport.done), 'guest completion marker missing')!
}

fn run(state string, profile_path string) !int {
	fresh(state)!
	profile_text := os.read_file(profile_path)!
	profile := json2.decode[Profile](profile_text)!
	p := validated(profile, state)!
	admission := budget(profile, state, true)!
	os.mkdir(state)!
	os.write_file(state + '/budget-before.log', admission)!
	os.write_file(state + '/profile.json', profile_text)!
	mut paths := profile.input_roots.clone()
	paths << [profile_path, profile.adapter, profile.prepared_state + '/prepared.json', p.command[0], os.executable(), @FILE]
	mutable := mutable_paths(p, profile.prepared_state)!
	for path, _ in p.inputs { if path !in mutable { paths << path } }
	before := runtime_inputs(p, paths)!
	require(before[profile_path] == sha256.sum(profile_text.bytes()).hex(), 'profile changed before inventory')!
	os.write_file(state + '/inputs-before.json', json2.encode(before) + '\n')!
	status := supervise(profile, state, [profile.adapter, 'run', profile.prepared_state, profile.prepared_sha256]) or {
		after := runtime_inputs(p, paths) or { map[string]string{} }
		os.write_file(state + '/inputs-after.json', json2.encode(after) + '\n')!
		return err
	}
	after := runtime_inputs(p, paths)!
	os.write_file(state + '/inputs-after.json', json2.encode(after) + '\n')!
	require(before == after, 'declared input identity changed')!
	os.write_file(state + '/budget-after.log', budget(profile, state, false)!)!
	require(status == 0, 'adapter exited ' + status.str())!
	completed(profile, p)!
	os.write_file(state + '/result.json', json2.encode({
		'verdict': 'PASS'
		'prepared_sha256': profile.prepared_sha256
		'inputs_sha256': hash(state + '/inputs-before.json')!
		'scope': 'maintained ' + p.arch + ' prepared adapter; its own successful shutdown and input verification receipts required; no arbitrary escaped-descendant guarantee'
	}) + '\n')!
	println('PERF FOREGROUND PASS ' + hash(state + '/result.json')!)
	return 0
}

fn fixture(kind string) {
	match kind {
		'ok' { println('fixture complete') }
		'quiet' { time.sleep(2200 * time.millisecond); println('fixture complete') }
		'journal-failure' {
			os.rm('budgets.jsonl') or { exit(26) }
			os.mkdir('budgets.jsonl') or { exit(27) }
			for { time.sleep(10 * time.millisecond) }
		}
		'nonzero' { eprintln('fixture refused'); exit(23) }
		'timeout' { for { time.sleep(10 * time.millisecond) } }
		'output' { for { println('x'.repeat(8192)); time.sleep(1 * time.millisecond) } }
		'signal' { C.kill(C.getppid(), C.SIGTERM); for { time.sleep(10 * time.millisecond) } }
		'descendant' {
			child := C.fork()
			if child < 0 { exit(24) }
			if child == 0 { for { time.sleep(10 * time.millisecond) } }
			println('same-group descendant ' + child.str())
		}
		else { exit(25) }
	}
}

fn fake_profile(profile Profile, prepared PreparedView) !Profile {
	path := profile.prepared_state + '/prepared.json'
	os.write_file(path, json2.encode(prepared) + '\n')!
	return Profile{...profile, prepared_sha256: hash(path)!}
}

fn refuses(profile Profile, state string, expected string) ! {
	validated(profile, state) or { require(err.msg().contains(expected), 'different profile refusal: ' + err.msg())!; return }
	return error('profile control accepted: ' + expected)
}

fn completion_refuses(profile Profile, p PreparedView, expected string) ! {
	completed(profile, p) or { require(err.msg().contains(expected), 'different completion refusal: ' + err.msg())!; return }
	return error('completion control accepted: ' + expected)
}

fn prepare_refuses(p PrepareProfile, state string, expected string) ! {
	prepare_validated(p, state) or { require(err.msg().contains(expected), 'different prepare refusal: ' + err.msg())!; return }
	return error('prepare control accepted: ' + expected)
}

struct TimingCase {
	previous u64
	start u64
	finish u64
	failure string
}

fn observation_controls(profile Profile, state string) !string {
	bound := observation_bound
	mut passed := 0
	for item in [
		TimingCase{0, 1, 1, ''},
		TimingCase{1, bound + 1, bound + 1, ''},
		TimingCase{1, 1, bound + 1, ''},
		TimingCase{1, bound + 2, bound + 2, 'observation start gap exceeds five seconds'},
		TimingCase{1, 1, bound + 2, 'observation window exceeds five seconds'},
		TimingCase{2, 1, 2, 'observation clock moved backwards'},
		TimingCase{1, 2, 1, 'observation clock moved backwards'},
	] {
		mut failure := ''
		observation_timing(item.previous, item.start, item.finish) or { failure = err.msg() }
		require(failure == item.failure, 'different observation timing result')!
		passed++
	}
	for item in [[observation_log_limit, u64(0)], [observation_log_limit + 1, u64(0)],
		[observation_log_limit, u64(1)]] {
		mut failure := ''
		observation_capacity(item[0], item[1]) or { failure = err.msg() }
		require(failure == if item[0] == observation_log_limit && item[1] == 0 { '' }
			else { 'observation journal exceeds 32 MiB' }, 'different journal bound result')!
		passed++
	}
	observation_capacity(0, observation_row_limit)!
	passed++
	mut row_failure := ''
	observation_capacity(0, observation_row_limit + 1) or { row_failure = err.msg() }
	require(row_failure == 'observation row exceeds 256 KiB', 'observation row cap differs')!
	passed++
	for item in [[524288, 0], [0, 524288], [524289, 0], [0, 524289]] {
		mut failure := ''
		usage_within(item[0], item[1], 524288) or { failure = err.msg() }
		expected := if item[0] > 524288 { 'allocated charged-root budget exceeded' }
			else if item[1] > 524288 { 'apparent charged-root budget exceeded' } else { '' }
		require(failure == expected, 'different dual budget result')!
		passed++
	}
	require(usage_total('1\t/one\n2\t/two\n')! == 3, 'du totals differ')!
	passed++
	mut failure := ''
	usage_total('1\n') or { failure = err.msg(); i64(0) }
	require(failure == 'unexpected du output', 'malformed du output accepted')!
	passed++
	sparse_root := state + '/sparse'; os.mkdir(sparse_root)!
	sparse := sparse_root + '/unallocated'; os.write_file(sparse, '')!
	// Keep this real fixture below the outer qualifier's unchanged 512 MiB cap.
	os.truncate(sparse, u64(65) << 20)!
	sparse_profile := Profile{...profile, charged_roots: [sparse_root]}
	reading := budget_read(sparse_profile, sparse_root)!
	os.write_file(state + '/sparse-budget.log', reading.raw)!
	failure = ''
	usage_within(reading.allocated_kib, reading.apparent_kib, 65536) or { failure = err.msg() }
	os.rm(sparse)!
	require(failure == 'apparent charged-root budget exceeded' && reading.allocated_kib < 65536,
		'sparse apparent budget refusal differs')!
	failure = ''
	budget_admit(BudgetReading{...reading, apparent_kib: 524288 - observation_reserve_kib + 1},
		sparse_profile, false) or { failure = err.msg() }
	require(failure == 'apparent charged-root budget exceeded', 'full-budget reserved-tail refusal differs')!
	passed++
	quiet := state + '/quiet'; os.mkdir(quiet)!
	require(supervise(Profile{...profile, timeout_seconds: 5}, quiet,
		[os.executable(), '--fixture', 'quiet'])! == 0, 'quiet child failed')!
	receipt := json2.decode[map[string]string](os.read_file(quiet + '/supervisor.json')!)!
	require(receipt['samples'].int() >= 3 && receipt['max_start_gap_ns'].u64() <= observation_bound
		&& receipt['max_sample_window_ns'].u64() <= observation_bound, 'quiet live observation timing differs')!
	mut samples := 0
	mut prior_start := u64(0)
	mut prior_probe := u64(0)
	for line in os.read_lines(quiet + '/budgets.jsonl')! {
		row := json2.decode[map[string]string](line)!
		observation_timing(row['previous_start_ns'].u64(), row['start_ns'].u64(), row['probes_done_ns'].u64())!
		if samples > 0 {
			require(row['previous_start_ns'].u64() == prior_start
				&& row['previous_finish_ns'].u64() >= prior_probe
				&& row['previous_finish_ns'].u64() <= row['start_ns'].u64(), 'previous completed sample differs')!
			observation_timing(prior_start, prior_start, row['previous_finish_ns'].u64())!
		}
		require(row['raw'].contains('allocated KiB (du -skl):')
			&& row['raw'].contains('apparent KiB (du -skAl):'), 'live dual observation missing')!
		samples++
		prior_start = row['start_ns'].u64()
		prior_probe = row['probes_done_ns'].u64()
	}
	require(samples == receipt['samples'].int(), 'observation journal count differs')!
	require(receipt['last_sample_start_ns'].u64() == prior_start
		&& receipt['last_sample_finish_ns'].u64() >= prior_probe, 'final completed sample differs')!
	observation_timing(prior_start, prior_start, receipt['last_sample_finish_ns'].u64())!
	passed++
	journal_failure := state + '/journal-failure'; os.mkdir(journal_failure)!
	failure = ''
	supervise(Profile{...profile, directory: journal_failure, timeout_seconds: 5}, journal_failure,
		[os.executable(), '--fixture', 'journal-failure']) or { failure = err.msg(); -1 }
	require(failure == 'observation journal changed', 'live journal failure differs: ' + failure)!
	failed_receipt := json2.decode[map[string]string](os.read_file(journal_failure + '/supervisor.json')!)!
	require(failed_receipt['cleanup'] == 'waitpid(-1,WNOHANG)=-1;errno=ECHILD'
		&& failed_receipt['failure'] == failure, 'journal refusal cleanup differs')!
	passed++
	require(passed == 21, 'observation control count differs')!
	return 'PASS twenty-one observation controls including live cadence, journal refusal and sparse apparent-cap refusal'
}

fn prepare_controls(state string, compiler string) !string {
	root := state + '/prepare-source'; base := state + '/prepare-base'; output := state + '/prepare-output'
	prepared := state + '/prepare-staged'
	os.mkdir(root)!; os.mkdir(base)!
	os.mkdir(state + '/prepare-sysroot')!; os.mkdir(state + '/prepare-gcc')!
	// The driver alias must retain the ELF spelling even in a host fixture.
	os.symlink(os.executable(), state + '/ld.lld')!
	xorriso := state + '/xorriso'; os.cp(os.executable(), xorriso)!; os.chmod(xorriso, 0o755)!
	pin := hash(os.executable())!
	p := PrepareProfile{adapter: os.executable(), adapter_sha256: pin, directory: root, base: base,
		base_mode: os.lstat(base)!.mode, base_manifest_sha256: '0'.repeat(64), kernel: os.executable(),
		kernel_sha256: pin, desktop: os.executable(), desktop_sha256: pin, prepared_state: prepared,
		compiler: compiler, qemu: os.executable(), firmware: xorriso, cc: os.executable(), readelf: os.executable(),
		mkfs: os.executable(), xorriso: xorriso, limine: root, sdk: root,
		sysroot: state + '/prepare-sysroot', gcc: state + '/prepare-gcc', linker: state + '/ld.lld',
		charged_roots: [state], input_roots: [root]}
	prepare_validated(p, output)!
	require(prepare_argv(p) == [p.adapter, 'prepare', root, base, p.kernel, prepared,
		'new=' + p.desktop, '--scenarios=ops,churn,cache,idle,apps,drag', '--settle=3', '--seconds=5',
		'--rounds=1', '--mem=3072', '--timeout=2400', '--base-manifest-sha256=' + p.base_manifest_sha256], 'fixed prepare argv differs')!
	os.mkdir(prepared)!
	prepare_refuses(p, output, 'fresh canonical external state')!; os.rmdir(prepared)!
	prepare_refuses(PrepareProfile{...p, prepared_state: output}, output, 'outputs must be separate')!
	prepare_refuses(PrepareProfile{...p, charged_roots: [root]}, output, 'covered by a charged root')!
	prepare_refuses(p, root + '/unexpected-output', 'overlaps an input tree')!
	prepare_refuses(PrepareProfile{...p, kernel_sha256: '1'.repeat(64)}, output, 'input digest mismatch')!
	prepare_refuses(PrepareProfile{...p, base_manifest_sha256: 'invalid'}, output, 'base mode and manifest pin')!
	require(!os.exists(output) && !os.exists(prepared), 'prepare admission control staged output')!
	return 'PASS eight prepare controls including six refusals; fixed argv and fresh charged output admission only; no adapter execution'
}

fn x86_owner_controls(state string, compiler string) !string {
	work := state + '/x86-owner'; os.mkdir(work)!
	root := work + '/source'; base := work + '/base'; sysroot := work + '/sysroot'; gcc := work + '/gcc'
	for path in [root, base, sysroot, gcc, work + '/staged'] { os.mkdir(path)! }
	xorriso := work + '/xorriso'; os.cp(os.executable(), xorriso)!; os.chmod(xorriso, 0o755)!
	os.symlink(os.executable(), work + '/ld.lld')!
	os.symlink(sysroot, work + '/sysroot-alias')!
	pin := hash(os.executable())!
	p := PrepareProfile{adapter: os.executable(), adapter_sha256: pin, directory: root, base: base,
		base_mode: os.lstat(base)!.mode, base_manifest_sha256: '0'.repeat(64), kernel: os.executable(),
		kernel_sha256: pin, desktop: os.executable(), desktop_sha256: pin, prepared_state: work + '/new-staged',
		compiler: compiler, qemu: os.executable(), firmware: xorriso, cc: os.executable(), readelf: os.executable(),
		mkfs: os.executable(), xorriso: xorriso, limine: root, sdk: root, sysroot: sysroot, gcc: gcc,
		linker: work + '/ld.lld', charged_roots: [work], input_roots: [root]}
	output := work + '/output'
	prepare_validated(p, output)!
	mut count := 1
	prepare_refuses(PrepareProfile{...p, sysroot: ''}, output, 'canonical build directory')!; count++
	prepare_refuses(PrepareProfile{...p, gcc: ''}, output, 'canonical build directory')!; count++
	prepare_refuses(PrepareProfile{...p, sysroot: work + '/sysroot-alias'}, output, 'canonical build directory')!; count++
	prepare_refuses(PrepareProfile{...p, linker: os.executable()}, output, 'ld.lld driver')!; count++
	prepare_refuses(PrepareProfile{...p, input_roots: [sysroot]}, output, 'literal input inventory')!; count++
	prepare_refuses(PrepareProfile{...p, input_roots: [gcc]}, output, 'literal input inventory')!; count++
	prepare_refuses(p, sysroot + '/output', 'overlaps x86 build directory')!; count++
	prepare_refuses(p, gcc + '/output', 'overlaps x86 build directory')!; count++
	require(!x86_closure_present(PreparedView{}), 'historical empty closure no longer admitted')!; count++
	staged := work + '/staged'
	os.write_file(staged + '/sysroot-before.tsv', 'sysroot fixture\n')!
	os.write_file(staged + '/gcc-before.tsv', 'gcc fixture\n')!
	prepared := PreparedView{sysroot: sysroot, gcc: gcc,
		sysroot_manifest: hash(staged + '/sysroot-before.tsv')!, gcc_manifest: hash(staged + '/gcc-before.tsv')!}
	x86_prepared(prepared, staged)!; count++
	mut failure := ''
	partial := PreparedView{...prepared, gcc: ''}
	require(x86_closure_present(partial), 'partial x86 closure bypasses validation')!
	x86_prepared(partial, staged) or { failure = err.msg() }
	require(failure.contains('canonical prepared x86'), 'partial x86 closure accepted')!; count++
	failure = ''
	x86_prepared(PreparedView{...prepared, gcc_manifest: '0'.repeat(64)}, staged) or { failure = err.msg() }
	require(failure == 'prepared x86 literal manifest differs', 'altered x86 manifest accepted')!; count++
	for path in [sysroot + '/loader', gcc + '/loader'] { os.symlink('/lib/libc.so', path)! }
	paths := [root, sysroot + '/loader', gcc + '/loader']
	before := runtime_inputs(prepared, paths)!
	for path in [sysroot + '/loader', gcc + '/loader'] {
		require(before['literal-link:' + path] == '/lib/libc.so' && 'resolved:' + path !in before,
			'x86 guest link was host-resolved')!
	}
	count++
	os.rm(gcc + '/loader')!; os.symlink('/other-gcc', gcc + '/loader')!
	second := runtime_inputs(prepared, paths)!
	require(before != second, 'changed GCC literal link accepted')!; count++
	os.rm(sysroot + '/loader')!; os.symlink('/other-sysroot', sysroot + '/loader')!
	require(second != runtime_inputs(prepared, paths)!, 'changed sysroot literal link accepted')!; count++
	require(count == 16 && !os.exists(output) && !os.exists(p.prepared_state), 'x86 owner control count or output differs')!
	return 'PASS sixteen x86 closure owner controls; no adapter or guest executed'
}

fn audit_controls(state string, profile Profile) !string {
	mut count := 0
	frame := fixed_audit('frame')!
	atomic_spec := fixed_audit('atomic')!
	require(audit_argv(frame) == [audit_checker, 'check',
		'/Users/alex/Library/Caches/vinix-codex/section14/frame-peer-baseline-fresh-20261026',
		'/Users/alex/Library/Caches/vinix-codex/section14/frame-peer-baseline-fresh-20261026-seal-01/complete/inventory.json'], 'fixed frame argv differs')!; count++
	require(audit_argv(atomic_spec) == [audit_checker, 'check',
		'/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-fresh-20261026',
		'/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-fresh-20261026-seal-01/complete/inventory.json'], 'fixed atomic argv differs')!; count++
	mut failure := ''
	fixed_audit('/arbitrary') or { failure = err.msg(); AuditSpec{} }
	require(failure == 'audit requires fixed frame or atomic selection', 'arbitrary audit selection accepted')!; count++
	for item in [audit_marker, 'FRAME-PAGE COMPLETE STATE CHECK PASS', audit_marker + audit_marker] {
		failure = ''; audit_completion(0, item) or { failure = err.msg() }
		require(failure == if item == audit_marker { '' } else { 'original audit exact marker differs' }, 'audit marker control differs')!
		count++
	}
	failure = ''; audit_completion(1, audit_marker) or { failure = err.msg() }
	require(failure == 'original audit child exited nonzero', 'nonzero audit accepted')!; count++
	fixture := state + '/audit-input'; os.write_file(fixture, 'fixture manifest')!
	audit_pinned(fixture, sha256.hexhash('fixture manifest'), time.sys_mono_now() + u64(time.second))!; count++
	failure = ''; audit_pinned(fixture, '0'.repeat(64), time.sys_mono_now() + u64(time.second)) or { failure = err.msg(); '' }
	require(failure.contains('fixed audit input digest differs'), 'wrong audit manifest accepted')!; count++
	audit_equal({'manifest': 'one'}, {'manifest': 'one'})!; count++
	failure = ''; audit_equal({'manifest': 'one'}, {'manifest': 'two'}) or { failure = err.msg() }
	require(failure == 'audit fixed inputs changed', 'changed audit pins accepted')!; count++
	p := AuditProfile{charged_roots: [state]}
	output := state + '/audit-admission'
	audit_admission(p, frame, output)!; count++
	failure = ''; audit_admission(AuditProfile{...p, format: 2}, frame, output) or { failure = err.msg(); Profile{} }
	require(failure == 'audit profile format must be 1', 'unknown audit format accepted')!; count++
	failure = ''; audit_admission(AuditProfile{...p, charged_roots: []}, frame, output) or { failure = err.msg(); Profile{} }
	require(failure == 'audit charged roots required', 'empty audit roots accepted')!; count++
	os.mkdir(state + '/audit-sub')!
	failure = ''; audit_admission(AuditProfile{...p, charged_roots: [state, state + '/audit-sub']}, frame, output) or { failure = err.msg(); Profile{} }
	require(failure == 'overlapping audit charged roots', 'overlapping audit roots accepted')!; count++
	os.mkdir(output)!
	failure = ''; audit_admission(p, frame, output) or { failure = err.msg(); Profile{} }
	require(failure == 'fresh canonical external state required', 'stale audit state accepted')!; count++
	os.write_file(output + '/keep', 'unchanged existing state')!
	existing_before := inputs([output])!
	profile_path := state + '/audit-profile.json'
	os.write_file(profile_path, json2.encode(p) + '\n')!
	stale_driver := state + '/audit-stale-driver'; os.mkdir(stale_driver)!
	require(supervise(Profile{...profile, timeout_seconds: 5}, stale_driver,
		[os.executable(), 'audit', 'frame', output, profile_path])! == 1, 'stale audit CLI did not refuse')!
	require(inputs([output])! == existing_before, 'stale audit CLI changed existing state')!; count++
	owner_root := os.real_path(@DIR + '/../..')
	failure = ''; audit_admission(AuditProfile{charged_roots: [owner_root]}, frame,
		owner_root + '/audit-must-not-exist') or { failure = err.msg(); Profile{} }
	require(failure == 'audit output overlaps fixed input', 'audit output inside owner source accepted')!; count++
	audit_tail(1, 300 * u64(time.second) + 1, 300 * u64(time.second) + 1)!; count++
	failure = ''; audit_tail(1, 300 * u64(time.second) + 2, 300 * u64(time.second) + 2) or { failure = err.msg() }
	require(failure == 'audit total 300-second deadline exceeded', 'late audit wall accepted')!; count++
	failure = ''; audit_tail(1, 1, observation_bound + 2) or { failure = err.msg() }
	require(failure == 'observation window exceeds five seconds', 'late audit tail accepted')!; count++
	require(audit_integer('18446744073709551615')! == u64(18446744073709551615), 'audit integer boundary differs')!; count++
	for raw in ['', '18446744073709551616'] {
		failure = ''; audit_integer(raw) or { failure = err.msg(); u64(0) }
		require(failure != '', 'invalid audit timing integer accepted')!; count++
	}
	child := state + '/audit-timeout'; os.mkdir(child)!
	failure = ''
	supervise_core(Profile{...profile, timeout_seconds: 1}, child,
		[os.executable(), '--fixture', 'timeout'], time.sys_mono_now(), 0) or { failure = err.msg(); -1 }
	require(failure == 'command timed out', 'audit zero-grace refusal differs: ' + failure)!
	receipt := json2.decode[map[string]string](os.read_file(child + '/supervisor.json')!)!
	require(receipt['cleanup'] == 'waitpid(-1,WNOHANG)=-1;errno=ECHILD', 'audit zero-grace child remains')!; count++
	require(count == 25, 'audit control count differs')!
	return 'PASS twenty-five fixed audit controls; no original bundle or guest executed'
}

fn profile_controls(state string) !string {
	root := state + '/fake-source'; prepared := state + '/fake-prepared'; output := state + '/fake-output'
	os.mkdir(root)!; os.mkdir(prepared)!
	os.write_file(prepared + '/root.ext2', 'fixture disk')!
	p := PreparedView{
		root: root
		arguments: ['fixture=' + os.executable(), '--scenarios=ops,churn,cache,idle,apps,drag', '--timeout=1800']
		command: [os.executable(), '-serial', 'mon:stdio']
		inputs: {os.executable(): hash(os.executable())!, prepared + '/root.ext2': hash(prepared + '/root.ext2')!}
	}
	base := Profile{adapter: os.executable(), prepared_state: prepared, directory: root, timeout_seconds: 1860,
		log_limit_bytes: 65536, charged_roots: [prepared], input_roots: [root]}
	valid := fake_profile(base, p)!
	validated(valid, output)!
	missing := PreparedView{...p, arguments: ['fixture=' + os.executable(), '--scenarios=ops,churn,cache,idle,apps', '--timeout=1800']}
	refuses(fake_profile(base, missing)!, output, 'six performance scenarios')!
	plain := PreparedView{...p, command: [os.executable(), '-serial', 'stdio']}
	refuses(fake_profile(base, plain)!, output, 'foreground serial monitor')!
	mut pins := p.inputs.clone(); pins[os.executable()] = 'wrong'
	refuses(fake_profile(base, PreparedView{...p, inputs: pins})!, output, 'prepared input pin')!
	restored := fake_profile(base, p)!
	refuses(Profile{...restored, charged_roots: [root]}, output, 'covered by a charged root')!
	os.write_file(prepared + '/after-inputs.json', '{}')!
	refuses(restored, output, 'stale adapter input receipt')!
	os.mkdir(prepared + '/results')!
	os.write_file(prepared + '/results/status', '0\n')!
	os.write_file(prepared + '/results/serial.log', perfreport.done + '\n')!
	completion_refuses(restored, p, 'input verification receipt differs')!
	os.write_file(prepared + '/after-inputs.json', json2.encode(p.inputs) + '\n')!
	completed(restored, p)!
	os.write_file(prepared + '/results/serial.log', 'almost ' + perfreport.done + '\n')!
	completion_refuses(restored, p, 'completion marker missing')!
	os.write_file(prepared + '/results/status', '23\n')!
	completion_refuses(restored, p, 'completion receipt missing')!
	return 'PASS ten profile/completion controls; fake prepared documents only; no adapter or QEMU execution'
}

// Separate ARM controls preserve the historical x86 twenty-four-case receipt.
fn armcheck(state string, compiler string) ! {
	fresh(state)!
	os.mkdir(state)!
	root := state + '/source'; sysroot := state + '/sysroot'; staged := state + '/prepared'; output := state + '/output'
	for path in [root, sysroot, staged, sysroot + '/gcc'] { os.mkdir(path)! }
	base := state + '/base.tar'; os.write_file(base, 'fixture archive')!
	firmware := state + '/firmware'; variables := state + '/variables'
	os.write_file(firmware, 'firmware')!; os.write_file(variables, 'variables')!
	os.write_file(root + '/BOOTAA64.EFI', 'fixture loader')!
	os.symlink(os.executable(), state + '/ld.lld')!
	pin := hash(os.executable())!
	preparation := PrepareProfile{arch: 'aarch64', adapter: os.executable(), adapter_sha256: pin,
		directory: root, base: base, base_mode: os.lstat(base)!.mode, base_manifest_sha256: hash(base)!,
		kernel: os.executable(), kernel_sha256: pin, desktop: os.executable(), desktop_sha256: pin,
		prepared_state: state + '/new-prepared', compiler: compiler, qemu: os.executable(), firmware: firmware,
		firmware_vars: variables, cc: os.executable(), readelf: os.executable(), mkfs: os.executable(),
		limine: root, sdk: root, sysroot: sysroot, gcc: sysroot + '/gcc', linker: state + '/ld.lld',
		mformat: os.executable(), mmd: os.executable(), mcopy: os.executable(), charged_roots: [state], input_roots: [root]}
	prepare_validated(preparation, output)!
	require(prepare_argv(preparation)[2..6] == [root, base, preparation.kernel, preparation.prepared_state], 'ARM fixed prepare argv differs')!
	mut checks := ['valid fixed ARM preparation admission']
	prepare_refuses(PrepareProfile{...preparation, base_manifest_sha256: '0'.repeat(64)}, output, 'archive digest mismatch')!
	checks << 'refused changed archive'
	prepare_refuses(PrepareProfile{...preparation, firmware_vars: firmware}, output, 'separate canonical ARM firmware variables')!
	checks << 'refused shared firmware code and variables'
	prepare_refuses(PrepareProfile{...preparation, gcc: root}, output, 'GCC directory must be inside')!
	checks << 'refused external GCC directory'
	prepare_refuses(PrepareProfile{...preparation, xorriso: os.executable()}, output, 'does not select xorriso')!
	checks << 'refused x86-only preparation tool'
	prepare_refuses(PrepareProfile{...preparation, input_roots: [sysroot]}, output, 'literal input inventory')!
	checks << 'refused host resolution of guest sysroot'
	prepare_refuses(preparation, sysroot + '/output', 'overlaps ARM sysroot')!
	checks << 'refused output inside sysroot'
	for name in ['root.ext2', 'vars.fd', 'boot.img'] { os.write_file(staged + '/' + name, name)! }
	os.write_file(staged + '/sysroot-before.tsv', 'fixture manifest\n')!
	socket := '/tmp/vinix-perf-arm-' + sha256.sum(staged.bytes()).hex()[..16] + '.qmp'
	p := PreparedView{arch: 'aarch64', root: root, storage: 'archive-overlay', sysroot: sysroot,
		sysroot_manifest: hash(staged + '/sysroot-before.tsv')!, firmware: firmware, socket: socket,
		arguments: ['new=' + os.executable(), '--scenarios=ops,churn,cache,idle,apps,drag', '--timeout=1800'],
		command: arm_command(os.executable(), firmware, staged, socket),
		inputs: {os.executable(): pin, firmware: hash(firmware)!, staged + '/boot.img': hash(staged + '/boot.img')!,
			staged + '/root.ext2': hash(staged + '/root.ext2')!, staged + '/vars.fd': hash(staged + '/vars.fd')!}}
	profile := Profile{adapter: os.executable(), prepared_state: staged, directory: root, timeout_seconds: 1860,
		log_limit_bytes: 65536, charged_roots: [staged], input_roots: [root]}
	validated(fake_profile(profile, p)!, output)!
	checks << 'valid fixed ARM runtime admission'
	mut wrong_command := p.command.clone(); wrong_command[wrong_command.index('virtio-blk-pci,drive=vinix-boot')] = 'virtio-blk-device,drive=vinix-boot'
	refuses(fake_profile(profile, PreparedView{...p, command: wrong_command})!, output, 'fixed prepared ARM QEMU command differs')!
	checks << 'refused second MMIO block device'
	mut missing := p.inputs.clone(); missing.delete(staged + '/vars.fd')
	refuses(fake_profile(profile, PreparedView{...p, inputs: missing})!, output, 'mutable disk pin missing')!
	checks << 'refused absent variables pin'
	refuses(fake_profile(profile, PreparedView{...p, storage: 'apfs-clone'})!, output, 'ARM prepared storage differs')!
	checks << 'refused ARM storage mismatch'
	refuses(fake_profile(profile, PreparedView{...p, arch: 'unknown'})!, output, 'unsupported prepared architecture')!
	checks << 'refused unknown architecture'
	valid := fake_profile(profile, p)!
	os.mkdir(staged + '/results')!
	os.write_file(staged + '/results/status', '0\n')!; os.write_file(staged + '/results/serial.log', perfreport.done + '\n')!
	mut after := p.inputs.clone()
	for name in ['root.ext2', 'vars.fd'] { os.write_file(staged + '/' + name, 'changed ' + name)!; after[staged + '/' + name] = hash(staged + '/' + name)! }
	os.write_file(staged + '/after-inputs.json', json2.encode(after) + '\n')!; completed(valid, p)!
	checks << 'accepted both fixed mutable outputs'
	os.write_file(staged + '/boot.img', 'changed immutable boot image')!; after[staged + '/boot.img'] = hash(staged + '/boot.img')!
	os.write_file(staged + '/after-inputs.json', json2.encode(after) + '\n')!
	completion_refuses(valid, p, 'input verification receipt differs')!
	checks << 'refused mutable boot image'
	os.symlink('/lib/libc.so', sysroot + '/loader')!
	before := runtime_inputs(p, [root])!
	require(before['literal-link:' + sysroot + '/loader'] == '/lib/libc.so'
		&& 'resolved:' + sysroot + '/loader' !in before, 'guest link was host-resolved')!
	checks << 'literal guest absolute link without host resolution'
	os.rm(sysroot + '/loader')!; os.symlink('/other', sysroot + '/loader')!
	require(runtime_inputs(p, [root])! != before, 'changed sysroot link accepted')!
	checks << 'changed sysroot link changes owner inventory'
	require(checks.len == 16 && !os.exists(output) && !os.exists(preparation.prepared_state), 'ARM control count or output differs')!
	os.write_file(state + '/result.json', json2.encode(checks) + '\n')!
	println('PERF FOREGROUND ARM HOST PASS sixteen controls; no adapter or guest executed')
}

fn selfcheck(state string, compiler string) ! {
	fresh(state)!
	require(compiler.starts_with('/') && os.is_file(compiler), 'absolute complete V executable required')!
	mut profile := Profile{directory: os.real_path(os.dir(state)), timeout_seconds: 2, log_limit_bytes: 65536}
	admission := budget(profile, state, true)!
	os.mkdir(state)!
	profile = Profile{...profile, charged_roots: [state]}
	os.write_file(state + '/budget-before.log', admission)!
	root := os.real_path(@DIR + '/../..')
	paths := [os.executable(), os.dir(compiler), root + '/tools', root + '/tests/desktop-perf', root + '/tests/hardware-platform/hwhost']
	before := inputs(paths)!
	os.write_file(state + '/inputs-before.json', json2.encode(before) + '\n')!
	for directory in ['tools', 'tests/desktop-perf', 'tests/hardware-platform/hwhost'] {
		os.mkdir_all(os.dir(state + '/source/' + directory))!
		os.cp_all(root + '/' + directory, state + '/source/' + directory, false)!
	}
	mut checks := map[string]string{}
	checks['profile_controls'] = profile_controls(state)!
	checks['prepare_controls'] = prepare_controls(state, compiler)!
	checks['observation_controls'] = observation_controls(profile, state)!
	checks['x86_closure_controls'] = x86_owner_controls(state, compiler)!
	checks['audit_controls'] = audit_controls(state, profile)!
	for kind in ['ok', 'nonzero', 'timeout', 'output', 'signal', 'descendant'] {
		work := state + '/' + kind; os.mkdir(work)!
		started := time.sys_mono_now()
		mut refused := ''
		status := supervise(profile, work, [os.executable(), '--fixture', kind]) or { refused = err.msg(); -1 }
		checks[kind] = 'status=' + status.str() + ';refusal=' + refused
		os.write_file(state + '/controls.json', json2.encode(checks) + '\n')!
		expected := match kind { 'timeout', 'descendant' { 'command timed out' } 'output' { 'command output exceeds limit' } 'signal' { 'command interrupted' } else { '' } }
		require(refused == expected, kind + ' refusal differs: ' + refused)!
		if expected == '' { require(status == if kind == 'nonzero' { 23 } else { 0 }, kind + ' status differs')! }
		require(time.sys_mono_now() - started < 10 * u64(time.second), kind + ' cleanup exceeded wall bound')!
		require(os.file_size(work + '/command.log') <= u64(profile.log_limit_bytes), kind + ' retained output exceeds hard limit')!
		if kind == 'nonzero' { require(os.read_file(work + '/command.log')! == 'fixture refused\n', 'combined pipe lost stderr')! }
		os.write_file(work + '/budget-after.log', budget(profile, state, false)!)!
	}
	checks['scope'] = 'host fixtures exercise actual SDK spawn, observer, TERM grace, group retirement and sole i32 reap; no guest executed'
	after := inputs(paths)!
	os.write_file(state + '/inputs-after.json', json2.encode(after) + '\n')!
	require(before == after, 'host control input identity changed')!
	checks['inputs_sha256'] = hash(state + '/inputs-before.json')!
	checks['verdict'] = 'PASS forty-five historical owner controls, sixteen x86 closure controls and twenty-five fixed audit controls'
	os.write_file(state + '/qualification.json', json2.encode(checks) + '\n')!
	println('PERF FOREGROUND HOST PASS ' + hash(state + '/qualification.json')!)
}

fn limitcheck(state string) ! {
	fresh(state)!
	os.mkdir(state)!
	mut checks := map[string]string{}
	for limit in [524288, 2097152, 2097153, 4718592] {
		profile := Profile{charged_limit_kib: limit, charged_roots: [state]}
		checks[limit.str()] = budget(profile, state, true)!
	}
	for limit in [524287, 4718593] {
		profile := Profile{charged_limit_kib: limit, charged_roots: [state]}
		budget(profile, state, true) or {
			require(err.msg() == 'charged limit must be 512 MiB..4.5 GiB', 'different limit refusal')!
			checks[limit.str()] = err.msg()
			continue
		}
		return error('out-of-range charged limit accepted')
	}
	os.write_file(state + '/result.json', json2.encode(checks) + '\n')!
	println('PERF FOREGROUND LIMIT PASS six admission boundaries')
}

fn qualify(state string, compiler string, mode string) ! {
	adapter := mode in ['qualify-adapter', 'qualify-arm-adapter']
	arm := mode == 'qualify-arm-adapter'
	arm_owner := mode == 'qualify-arm-owner'
	fresh(state)!
	require(compiler == os.real_path(compiler) && os.is_file(compiler), 'canonical complete V executable required')!
	root := os.real_path(@DIR + '/../..')
	require(!inside(state, root) && !inside(root, state), 'qualifier state must be external to source')!
	mut profile := Profile{directory: root, timeout_seconds: 120, log_limit_bytes: 4 * 1024 * 1024, charged_roots: [root]}
	admission := budget(profile, state, true)!
	os.mkdir(state)!
	profile = Profile{...profile, charged_roots: [root, state]}
	os.write_file(state + '/budget-before.log', admission)!
	os.cp(os.executable(), state + '/bootstrap')!
	for name in ['tmp', 'modules', 'cache'] { os.mkdir(state + '/' + name)! }
	for key, _ in os.environ() { if key !in ['HOME', 'USER', 'LOGNAME'] { os.unsetenv(key) } }
	for key, value in {
		'PATH': '/usr/bin:/bin:/usr/sbin:/sbin'
		'DEVELOPER_DIR': '/Library/Developer/CommandLineTools'
		'V': compiler
		'VEXE': compiler
		'V_MACOS_V3_CALLER_VEXE': compiler
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1'
		'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0'
		'V_MACOS_V3_NO_FALLBACK': '1'
		'V_MACOS_V3_CALLER_NO_FALLBACK': '1'
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1'
		'VTMP': state + '/tmp'
		'TMPDIR': state + '/tmp'
		'VMODULES': state + '/modules'
		'V3CACHE': state + '/cache'
		'XDG_CACHE_HOME': state + '/cache'
	} { os.setenv(key, value, true) }
	clang := command(['/usr/bin/xcrun', '--find', 'clang'])!.trim_space()
	resource := command([clang, '-print-resource-dir'])!.trim_space()
	sdk := command(['/usr/bin/xcrun', '--show-sdk-path'])!.trim_space()
	os.setenv('SDKROOT', sdk, true)
	mut paths := [os.dir(compiler), root + '/tools', root + '/tests/desktop-perf', root + '/tests/hardware-platform/hwhost',
		os.executable(), clang, '/Library/Developer/CommandLineTools/usr/bin/ld', resource + '/include',
		sdk + '/SDKSettings.json', sdk + '/SDKSettings.plist', '/usr/bin/xcrun', '/bin/df', '/usr/bin/du']
	if adapter { paths << [root + '/tests/hardware-platform/plainiso', root + '/tests/linuxkpi/hosttest'] }
	before := inputs(paths)!
	os.write_file(state + '/inputs-before.json', json2.encode(before) + '\n')!
	if adapter {
		mut copies := Inventory{}
		deadline := time.sys_mono_now() + 120 * u64(time.second)
		for directory in ['tools', 'tests/desktop-perf', 'tests/hardware-platform/hwhost', 'tests/hardware-platform/plainiso', 'tests/linuxkpi/hosttest'] {
			os.mkdir_all(os.dir(state + '/source/' + directory))!
			preserve_source(root + '/' + directory, state + '/source/' + directory, 0, deadline, mut copies)!
		}
	}
	mut results := map[string]string{}
	target := if arm { 'run-arm' } else if adapter { 'run-x86' } else { 'foreground-supervise' }
	for kind in ['normal', 'production'] {
		work := state + '/' + kind; os.mkdir(work)!
		build := work + '/build'; os.mkdir(build)!
		mut argv := [compiler, '-enable-globals', '-nocache', '-keepc', '-cc', clang, '-path',
			'@vlib|@vmodules|' + root + '/tools|' + root + '/tests/desktop-perf|' + root + '/tests/hardware-platform|' + root + '/tests/linuxkpi',
			'-o', work + '/' + target]
		if kind == 'production' { argv << '-prod' }
		argv << root + '/tests/desktop-perf/' + target + '.v'
		require(supervise(profile, build, argv)! == 0, kind + ' compile failed')!
		control := work + '/driver'; os.mkdir(control)!
		mut control_argv := [work + '/' + target, 'selfcheck', work + '/controls']
		if !adapter { control_argv << compiler }
		require(supervise(profile, control, control_argv)! == 0, kind + ' controls failed')!
		results[kind + ':binary_sha256'] = hash(work + '/' + target)!
		if arm {
			checks := json2.decode[[]string](os.read_file(work + '/controls/result.json')!)!
			require(checks.len == 18, 'ARM adapter control receipt count differs')!
			results[kind + ':selfcheck_sha256'] = hash(work + '/controls/result.json')!
		} else if adapter {
			require(os.read_file(work + '/controls/result')!.starts_with('PASS 37 checks including 22 refusals:'), 'adapter control receipt differs')!
			results[kind + ':selfcheck_sha256'] = hash(work + '/controls/result')!
			clone_driver := work + '/clone-driver'; os.mkdir(clone_driver)!
			require(supervise(profile, clone_driver, [work + '/' + target, 'clonecheck', work + '/clone-controls'])! == 0, kind + ' clone controls failed')!
			clone_checks := json2.decode[[]string](os.read_file(work + '/clone-controls/result.json')!)!
			require(clone_checks.len == 18, 'adapter clone receipt count differs')!
			results[kind + ':clonecheck_sha256'] = hash(work + '/clone-controls/result.json')!
		} else {
			results[kind + ':qualification_sha256'] = hash(work + '/controls/qualification.json')!
			if arm_owner {
				arm_driver := work + '/arm-driver'; os.mkdir(arm_driver)!
				require(supervise(profile, arm_driver, [work + '/' + target, 'armcheck', work + '/arm-controls', compiler])! == 0, kind + ' ARM owner controls failed')!
				checks := json2.decode[[]string](os.read_file(work + '/arm-controls/result.json')!)!
				require(checks.len == 16, 'ARM owner control receipt count differs')!
				results[kind + ':armcheck_sha256'] = hash(work + '/arm-controls/result.json')!
			}
		}
		os.write_file(state + '/progress.json', json2.encode(results) + '\n')!
	}
	after := inputs(paths)!
	os.write_file(state + '/inputs-after.json', json2.encode(after) + '\n')!
	require(before == after, 'build/control input identity changed')!
	os.write_file(state + '/budget-after.log', budget(profile, state, false)!)!
	results['inputs_sha256'] = hash(state + '/inputs-before.json')!
	results['verdict'] = if arm { 'PASS normal and production; eighteen ARM adapter controls each; no guest execution' } else if arm_owner { 'PASS normal and production; eighty-six owner and sixteen ARM owner controls each; no guest execution' } else if adapter { 'PASS normal and production; 37 selfcheck and 18 clone controls each; no guest execution' } else { 'PASS normal and production; eighty-six controls each; no guest execution' }
	results['scope'] = 'selected complete compiler, maintained sources and recorded host compiler/SDK metadata; installed loader and SDK dependency closure is not hermetic'
	os.write_file(state + '/qualification.json', json2.encode(results) + '\n')!
	println('PERF FOREGROUND QUALIFIED ' + hash(state + '/qualification.json')!)
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--fixture' { fixture(os.args[2]); return }
	if os.args.len == 5 && os.args[1] == 'audit' {
		audit_owned(os.args[2], os.args[3], os.args[4]) or {
			eprintln(err); exit(1)
		}; return
	}
	if os.args.len == 4 && os.args[1] == 'selfcheck' {
		selfcheck(os.args[2], os.args[3]) or { eprintln(err); exit(1) }; return
	}
	if os.args.len == 4 && os.args[1] == 'armcheck' {
		armcheck(os.args[2], os.args[3]) or { eprintln(err); exit(1) }; return
	}
	if os.args.len == 3 && os.args[1] == 'limitcheck' {
		limitcheck(os.args[2]) or { eprintln(err); exit(1) }; return
	}
	if os.args.len == 4 && os.args[1] in ['qualify', 'qualify-adapter', 'qualify-arm-adapter', 'qualify-arm-owner'] {
		qualify(os.args[2], os.args[3], os.args[1]) or { eprintln(err); exit(1) }; return
	}
	if os.args.len == 4 && os.args[1] in ['admit-prepare', 'prepare'] {
		prepare_owned(os.args[2], os.args[3], os.args[1] == 'admit-prepare') or {
			if os.is_dir(os.args[2]) { os.write_file(os.args[2] + '/failure.txt', err.msg() + '\n') or {} }
			eprintln(err); exit(1)
		}; return
	}
	if os.args.len == 4 && os.args[1] == 'run' {
		status := run(os.args[2], os.args[3]) or {
			if os.is_dir(os.args[2]) { os.write_file(os.args[2] + '/failure.txt', err.msg() + '\n') or {} }
			eprintln(err); exit(1)
		}; exit(status)
	}
	eprintln('usage: foreground-supervise run|admit-prepare|prepare NEW-STATE PROFILE.json\n       foreground-supervise audit frame|atomic NEW-STATE PROFILE.json\n       foreground-supervise selfcheck|armcheck|qualify|qualify-adapter|qualify-arm-adapter|qualify-arm-owner NEW-STATE COMPLETE-V\n       foreground-supervise limitcheck NEW-STATE')
	exit(2)
}
