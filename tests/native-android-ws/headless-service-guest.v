// SPDX-License-Identifier: GPL-2.0-or-later
// Root-only synthetic lifecycle diagnostic; no account or Google sign-in proof.
module main

import crypto.sha256
import encoding.base64
import json2
import os
import time

#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>
#include <pwd.h>
#include <grp.h>

$if linux {
	#include <sys/prctl.h>
	#include <sys/wait.h>
	#include <sys/mount.h>
}

fn C.prctl(int, u64, u64, u64, u64) int
fn C.waitpid(int, &int, int) int
fn C.getpwuid(u32) voidptr
fn C.getgrgid(u32) voidptr
fn C.mount(&char, &char, &char, u64, voidptr) int

const bundle_root = '/opt/vinix-headless-service'
const result_root = bundle_root + '/results'
const runtime_root = '/opt/vinix-android-aarch64'
const fixture_id = '10010'
const fixture_name = 'vinix-headless-fixture'
const pass_marker = 'HEADLESS-SERVICE-CONTROLLER-PASS pre-runtime-rejection root-channel application-once main-looper delayed-binder EOF-unbind destroy exit-zero'
const prefix = 'VINIX-HEADLESS-RESULTS-1 '
const chunk_bytes = 512
const max_file = 8 * 1024 * 1024
const max_total = 16 * 1024 * 1024
const max_archive = 32 * 1024 * 1024

struct Entry {
	path   string
	kind   string
	mode   u32
	size   u64
	sha256 string
	data   string
	link   string
}

struct Archive {
	version   int = 1
	root_mode u32
	entries   []Entry
}

struct Pins {
	inputs_sha256 map[string]string
}

struct Run {
	argv              []string
	executable_sha256 string
mut:
	status            string = 'not-run'
	exit_code         int    = -1
	timed_out         bool
	error             string
	descendants       int
	cleanup_survivors int
}

struct Receipt {
	scope         string = 'Synthetic headless lifecycle only; no authenticator dispatch, account, token or Google sign-in.'
	started_utc   string
	serial_device string = '/dev/console'
	guest_sha256  string
mut:
	finished_utc  string
	build_sha256  string
	runtime_mount string
	controller    Run
	status        string = 'failed'
	error         string
}

struct Identity {
	pid    int
	parent int
	start  string
}

fn hash(path string) !string {
	mut f := os.open(path)!
	defer { f.close() }
	mut digest := sha256.new()
	mut bytes := []u8{len: 65536}
	for {
		n := f.read(mut bytes) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		digest.write(bytes[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn safe_relative(path string) bool {
	return path != '' && path.len <= 4096 && !path.starts_with('/')
		&& !path.contains_any('\x00\n\r\\') && !path.split('/').any(it in ['', '.', '..'])
}

fn snapshot(root string, relative string, mut entries []Entry, mut total []u64) ! {
	if entries.len >= 4096 || !safe_relative(relative) {
		return error('result inventory limit/unsafe path')
	}
	path := root + '/' + relative
	st := os.lstat(path)!
	mode := st.mode & 0o7777
	if mode > 0o777 { return error('result mode is not supported by the strict collector') }
	match st.get_filetype() {
		.directory {
			entries << Entry{ path: relative, kind: 'directory', mode: mode }
			mut names := os.ls(path)!
			names.sort()
			for name in names { snapshot(root, relative + '/' + name, mut entries, mut total)! }
		}
		.regular {
			if st.size > max_file || total[0] + st.size > max_total {
				return error('result size limit')
			}
			bytes := os.read_bytes(path)!
			if u64(bytes.len) != st.size { return error('result changed while reading') }
			total[0] += st.size
			entries << Entry{
				path:   relative
				kind:   'regular'
				mode:   mode
				size:   st.size
				sha256: sha256.sum(bytes).hex()
				data:   base64.encode(bytes)
			}
		}
		.symbolic_link {
			target := os.readlink(path)!
			if target == '' || target.len > 4096 || target.contains('\x00') {
				return error('invalid symlink')
			}
			entries << Entry{ path: relative, kind: 'symlink', mode: mode, link: target }
		}
		else { return error('unsupported result object: ' + relative) }
	}
}

fn archive(root string) !string {
	mut entries := []Entry{}
	mut total := []u64{len: 1}
	mut names := os.ls(root)!
	names.sort()
	for name in names { snapshot(root, name, mut entries, mut total)! }
	mode := os.lstat(root)!.mode & 0o7777
	if mode > 0o777 { return error('result root has a special mode') }
	payload := json2.encode(Archive{ root_mode: mode, entries: entries })
	if payload.len > max_archive { return error('archive size limit') }
	return payload
}

fn header(payload string, kind string) string {
	return prefix + kind + ' ' + sha256.sum(payload.bytes()).hex() + ' ' + payload.len.str() +
		' ' + ((payload.len + chunk_bytes - 1) / chunk_bytes).str() + '\n'
}

fn serial_write(fd int, line string) ! {
	if line.len > 1024 { return error('serial frame limit') }
	mut used := 0
	for used < line.len {
		n := unsafe { C.write(fd, &u8(line.str) + used, uint(line.len - used)) }
		if n <= 0 { return error('serial write failed') }
		used += int(n)
	}
}

fn export_serial(payload string) ! {
	fd := C.open(c'/dev/console', C.O_WRONLY | C.O_NOCTTY | C.O_CLOEXEC)
	if fd < 0 { return error('cannot open serial-mirroring /dev/console') }
	defer { C.close(fd) }
	serial_write(fd, '\n')!
	serial_write(fd, header(payload, 'BEGIN'))!
	digest := sha256.sum(payload.bytes()).hex()
	for offset := 0; offset < payload.len; offset += chunk_bytes {
		end := if offset + chunk_bytes < payload.len { offset + chunk_bytes } else { payload.len }
		serial_write(fd, prefix + 'CHUNK ' + digest + ' ' + (offset / chunk_bytes).str() +
			' ' + base64.encode(payload[offset..end].bytes()) + '\n')!
	}
	serial_write(fd, header(payload, 'END'))!
}

// Start ticks distinguish an observed descendant from a reused PID. Native
// helpers create additional process groups, so track the whole child tree.
fn identity(pid int) !Identity {
	text := os.read_file('/proc/' + pid.str() + '/stat')!
	end := text.last_index(')') or { return error('invalid proc stat') }
	fields := text[end + 1..].fields()
	if fields.len < 20 { return error('short proc stat') }
	return Identity{ pid: pid, parent: fields[1].int(), start: fields[19] }
}

fn discover(mut owned map[int]Identity) ! {
	names := os.ls('/proc')!
	if names.len > 65536 { return error('proc inventory limit') }
	mut current := []Identity{}
	for name in names {
		if name != '' && name.bytes().all(it >= `0` && it <= `9`) {
			item := identity(name.int()) or { continue }
			current << item
		}
	}
	for _ in 0 .. 32 {
		mut added := false
		for item in current {
			if item.pid !in owned && item.parent in owned {
				parent := identity(item.parent) or { continue }
				if parent.start != owned[item.parent].start { continue }
				if owned.len >= 4096 { return error('descendant limit') }
				owned[item.pid] = item
				added = true
			}
		}
		if !added { return }
	}
	return error('descendant depth limit')
}

fn kill_owned(owned map[int]Identity) {
	for pid, previous in owned {
		if pid == os.getpid() { continue }
		current := identity(pid) or { continue }
		if current.start == previous.start { C.kill(pid, 9) }
	}
}

fn enable_subreaper() ! {
	$if linux {
		// Adopt helpers that orphan before /proc polling can observe their parent.
		if C.prctl(36, 1, 0, 0, 0) != 0 { return error('cannot become child subreaper') }
	} $else {
		return error('subreaper requires Linux ABI')
	}
}

fn cleanup(mut owned map[int]Identity) !int {
	deadline := time.sys_mono_now() + 2 * time.second
	for {
		discover(mut owned)!
		kill_owned(owned)
		$if linux {
			mut status := 0
			for C.waitpid(-1, &status, 1) > 0 {
			}
		}
		mut survivors := 0
		for pid, previous in owned {
			if pid == os.getpid() { continue }
			current := identity(pid) or { continue }
			if current.start == previous.start { survivors++ }
		}
		if survivors == 0 || time.sys_mono_now() >= deadline { return survivors }
		time.sleep(20 * time.millisecond)
	}
	return error('unreachable cleanup')
}

fn bounded(argv []string, log_path string, seconds int) !Run {
	mut result := Run{ argv: argv, executable_sha256: hash(argv[0])! }
	mut log := os.open_file(log_path, 'wx', 0o600)!
	defer { log.close() }
	mut child := os.new_process(argv[0])
	child.use_pgroup = true
	child.set_args(argv[1..])
	child.set_stdin_path('/dev/null')
	child.set_redirect_stdio_merged()
	child.run()
	// The subreaper is a non-kill owner. Orphans adopted by it remain visible.
	mut owned := {
		os.getpid(): identity(os.getpid())!
	}
	mut cleaned := false
	defer {
		if !cleaned {
			discover(mut owned) or {}
			kill_owned(owned)
			child.wait()
			cleanup(mut owned) or {}
		}
		child.close()
	}
	if child.pid <= 0 { return error('could not start child') }
	owned[child.pid] = identity(child.pid)!
	deadline := time.sys_mono_now() + u64(seconds) * u64(time.second)
	mut count := 0
	mut output := ''
	for {
		block := child.stdout_read()
		if block != '' {
			count += block.len
			if count > max_file { return error('child log limit') }
			log.write_string(block)!
			output += block
		}
		discover(mut owned)!
		if !child.is_alive() { break }
		if time.sys_mono_now() >= deadline {
			result.timed_out = true
			result.error = 'outer watchdog expired'
			break
		}
		time.sleep(20 * time.millisecond)
	}
	if result.timed_out { kill_owned(owned) }
	child.wait()
	result.cleanup_survivors = cleanup(mut owned)!
	cleaned = true
	for _ in 0 .. 2048 {
		block := child.stdout_read()
		if block == '' { break }
		count += block.len
		if count > max_file { return error('child log limit') }
		log.write_string(block)!
		output += block
	}
	result.exit_code = child.code
	result.descendants = owned.len - 2
	result.status = if !result.timed_out && child.code == 0 && result.cleanup_survivors == 0 {
		'passed'
	} else {
		'failed'
	}
	if result.cleanup_survivors != 0 { result.error += ' child processes survived cleanup' }
	if output.split_into_lines().filter(it == pass_marker).len != 1 {
		result.status = 'failed'
		result.error = 'exact controller PASS marker must occur once'
	}
	return result
}

fn database_after(before string, name string, entry string) !string {
	for line in before.split_into_lines() {
		if line == '' || line.starts_with('#') { continue }
		columns := line.split(':')
		if columns.len < 3 || columns[2] == '' || columns[2].len > 10
			|| !columns[2].bytes().all(it >= `0` && it <= `9`) || columns[2].u64() > u64(0xffffffff) {
			return error('malformed Unix account database')
		}
		if columns[0] == name || columns[2].u64() == fixture_id.u64() {
			return error('dedicated fixture name or numeric ID is already assigned')
		}
	}
	return before + (if before != '' && !before.ends_with('\n') { '\n' } else { '' }) + entry + '\n'
}

fn provision() ! {
	mut before := map[string]string{}
	mut after := map[string]string{}
	for pair in [
		['/etc/passwd',
			fixture_name + ':x:' + fixture_id + ':' + fixture_id + ':Synthetic headless fixture:' + result_root + '/controller/home:/bin/false'],
		['/etc/group', fixture_name + ':x:' + fixture_id + ':'],
	] {
		st := os.lstat(pair[0])!
		if st.get_filetype() != .regular || st.uid != 0 || st.mode & 0o022 != 0 || st.nlink != 1 {
			return error('Unix account database must be a protected root-owned regular file')
		}
		before[pair[0]] = os.read_file(pair[0])!
		after[pair[0]] = database_after(before[pair[0]], fixture_name, pair[1])!
	}
	// Both files are validated before writing either; retain exact original bytes.
	for path, original in before {
		if os.read_file(path)! != original {
			return error('account database changed after preflight')
		}
	}
	for path, original in before {
		os.write_file(result_root + '/inputs/' + os.base(path) + '-before', original)!
		os.write_file(result_root + '/inputs/' + os.base(path) + '-after', after[path])!
		os.write_file(path, after[path])!
		if os.read_file(path)! != after[path] || !after[path].starts_with(original) {
			return error('account database prefix/readback differs')
		}
	}
	if C.getpwuid(fixture_id.u32()) == unsafe { nil } || C.getgrgid(fixture_id.u32()) == unsafe { nil } {
		return error('dedicated fixture Unix identity does not resolve')
	}
}

// The baseline desktop launcher may already have approved this shared runtime.
// A second self-bind would leave two advertised attachments at the same path.
// Validate that existing approval instead of adding another mount over it.
fn approved_runtime_mount(table string) !string {
	mut found := ''
	for line in table.split_into_lines() {
		fields := line.fields()
		if fields.len < 2 || fields[1] != runtime_root { continue }
		if found != '' { return error('duplicate runtime mount entry') }
		if fields.len != 6 || fields[0] != runtime_root {
			return error('runtime mount is not a dedicated self-bind')
		}
		options := fields[3].split(',')
		for option in ['ro', 'nosuid', 'nodev', 'wxallowed'] {
			if option !in options { return error('runtime mount lacks ' + option) }
		}
		if 'noexec' in options || 'rw' in options {
			return error('runtime attachment is not read-only and executable')
		}
		found = line
	}
	return found
}

fn runtime_mount_snapshot(label string) !string {
	table := os.read_file('/proc/self/mounts')!
	os.write_file(result_root + '/runtime-mounts' + label + '.txt', table)!
	os.write_file(result_root + '/runtime-mountinfo' + label + '.txt',
		os.read_file('/proc/self/mountinfo')!)!
	return table
}

fn approve_runtime() !string {
	$if linux {
		before := runtime_mount_snapshot('-before')!
		existing := approved_runtime_mount(before)!
		if existing != '' {
			// Recheck the unique attachment immediately before launching the child.
			current := approved_runtime_mount(runtime_mount_snapshot('')!)!
			if current != existing { return error('runtime mount changed during approval') }
			return current
		}
		if unsafe { C.mount(runtime_root.str, runtime_root.str, nil, u64(C.MS_BIND), nil) } != 0 {
			return error('cannot attach dedicated runtime bind mount')
		}
		runtime_mount_snapshot('-bound')!
		flags := u64(C.MS_BIND | C.MS_REMOUNT | C.MS_RDONLY | C.MS_NOSUID | C.MS_NODEV | C.MS_STRICTATIME)
		if unsafe { C.mount(c'none', runtime_root.str, nil, flags, c'wxallowed') } != 0 {
			return error('cannot authorize dedicated runtime WX attachment')
		}
		found := approved_runtime_mount(runtime_mount_snapshot('')!)!
		if found == '' { return error('runtime mount record absent') }
		return found
	} $else {
		return error('runtime mount requires Linux ABI')
	}
}

fn diagnostics(mut receipt Receipt) ! {
	build := bundle_root + '/guest-inputs.json'
	pins := json2.decode[Pins](os.read_file(build)!)!
	expected := [
		runtime_root + '/usr/lib/java/dex/android_translation_layer/api-impl.jar',
		runtime_root + '/usr/lib/art/libvinix-android-native.so',
		runtime_root + '/usr/bin/vinix-android-native',
		runtime_root + '/usr/bin/run-android',
		bundle_root + '/bin/headless-service-controller',
		bundle_root + '/bin/headless-service-guest',
		bundle_root + '/fixture.apk',
	]
	if pins.inputs_sha256.len != expected.len { return error('expected seven guest input pins') }
	for path, pin in pins.inputs_sha256 {
		if path !in expected || os.lstat(path)!.get_filetype() != .regular || hash(path)! != pin {
			return error('guest input path/type/pin differs: ' + path)
		}
	}
	if pins.inputs_sha256[bundle_root + '/bin/headless-service-guest']! != hash('/proc/self/exe')! {
		return error('guest wrapper identity differs')
	}
	receipt.build_sha256 = hash(build)!
	os.mkdir(result_root + '/inputs')!
	os.cp(build, result_root + '/inputs/guest-inputs.json')!
	for file in ['fixture-build.json', 'native-build.json', 'native-sha256.json', 'framework-build.json',
		'framework-sha256.json'] {
		os.cp(bundle_root + '/' + file, result_root + '/inputs/' + file)!
	}
	provision()!
	receipt.runtime_mount = approve_runtime()!
	receipt.controller = bounded([bundle_root + '/bin/headless-service-controller', runtime_root,
		bundle_root + '/fixture.apk', fixture_id, fixture_id, result_root + '/controller'],
		result_root + '/controller.log', 180)!
	for path, pin in pins.inputs_sha256 {
		if hash(path)! != pin { return error('guest input changed during diagnostic: ' + path) }
	}
	if receipt.controller.status == 'passed' { receipt.status = 'passed' }
}

fn self_test() ! {
	root := os.join_path(os.temp_dir(), 'vinix-headless-guest-selftest-' + os.getpid().str())
	if unsafe { C.mkdir(root.str, 0o700) } != 0 { return error('self-test output exists') }
	defer { os.rmdir_all(root) or {} }
	os.mkdir(root + '/directory')!
	os.write_file(root + '/directory/log', 'exact\x00bytes\n')!
	os.chmod(root + '/directory/log', 0o640)!
	os.symlink('/pinned/runtime/font.pcf.gz', root + '/font')!
	payload := archive(root)!
	decoded := json2.decode[Archive](payload)!
	assert decoded.entries.len == 3 && decoded.entries[1].mode == 0o640
	assert base64.decode(decoded.entries[1].data) == 'exact\x00bytes\n'.bytes()
	assert decoded.entries[2].link == '/pinned/runtime/font.pcf.gz'
	assert archive(root)! == payload && header(payload, 'BEGIN').starts_with(prefix + 'BEGIN ')
	assert !safe_relative('../escape') && !safe_relative('a//b') && safe_relative('a/b')
	before := 'root:x:0:0:root:/root:/bin/sh'
	after := database_after(before, fixture_name, fixture_name + ':x:10010:')!
	assert after.starts_with(before + '\n') && after.ends_with('\n')
	for bad in ['other:x:10010:', 'other:x:0000010010:', fixture_name + ':x:10011:', 'bad:x:',
		'bad:x:4294967296:'] {
		if _ := database_after(bad, fixture_name, 'unused') {
			return error('account collision/malformed database accepted')
		}
	}
	approved := runtime_root + ' ' + runtime_root + ' tmpfs ro,nosuid,nodev,wxallowed,relatime 0 0'
	assert approved_runtime_mount('tmpfs / tmpfs rw 0 0\n')! == ''
	assert approved_runtime_mount('tmpfs / tmpfs rw 0 0\n' + approved + '\n')! == approved
	for bad in [approved + '\n' + approved, approved.replace('ro,', 'rw,'),
		approved.replace('nodev,', ''), approved.replace('wxallowed,', ''),
		approved.replace('relatime', 'relatime,noexec'), approved.replace('ro,', 'ro,rw,'),
		approved.replace(runtime_root + ' ' + runtime_root, '/other ' + runtime_root),
		approved + ' extra', runtime_root + ' ' + runtime_root] {
		if _ := approved_runtime_mount(bad) {
			return error('duplicate/unapproved runtime mount accepted')
		}
	}
	println('HEADLESS-GUEST SELF-TEST PASS deterministic-tree modes binary-content symlink framing account-prefix collisions existing-approved-mount duplicate-mount-rejection')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	if os.args.len != 1 {
		eprintln('usage: headless-service-guest [--self-test]')
		exit(2)
	}
	$if !linux {
		eprintln('headless-service-guest requires the Linux ABI guest')
		exit(2)
	}
	if C.getuid() != 0 || C.geteuid() != 0 {
		eprintln('headless-service-guest requires guest root')
		exit(2)
	}
	enable_subreaper() or {
		eprintln(err.msg())
		exit(1)
	}
	if unsafe { C.mkdir(result_root.str, 0o755) } != 0 {
		eprintln('refusing existing ' + result_root)
		exit(1)
	}
	mut receipt := Receipt{ started_utc: time.utc().str(), guest_sha256: hash('/proc/self/exe') or { '' } }
	diagnostics(mut receipt) or { receipt.error = err.msg() }
	receipt.finished_utc = time.utc().str()
	os.write_file(result_root + '/guest.json', json2.encode(receipt, prettify: true) + '\n') or {
		eprintln(err.msg())
		exit(1)
	}
	payload := archive(result_root) or {
		eprintln('cannot archive results: ' + err.msg())
		exit(1)
	}
	// Exact exported bytes live outside the immutable result tree.
	mut file := os.open_file(result_root + '.json', 'wx', 0o600) or {
		eprintln(err.msg())
		exit(1)
	}
	file.write_string(payload) or {
		eprintln(err.msg())
		exit(1)
	}
	file.close()
	export_serial(payload) or {
		eprintln(err.msg())
		exit(1)
	}
	println('HEADLESS-GUEST exported status=' + receipt.status + ' sha256=' + sha256.sum(payload.bytes()).hex())
	if receipt.status != 'passed' { exit(1) }
}
