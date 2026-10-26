// SPDX-License-Identifier: GPL-2.0-or-later
// Separate credential-free engine diagnostic; not Google authentication proof.
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

$if linux {
	#include <sys/prctl.h>
	#include <sys/wait.h>
}

fn C.prctl(int, u64, u64, u64, u64) int
fn C.waitpid(int, &int, int) int

const result_root = '/tmp/vinix-browser-probe-results'
const bundle_root = '/opt/vinix-browser-probe'
// Preserve the entire frozen build, including its input sources and receipts.
const authority_path = '/opt/vinix-account-authority-fixture/module/opt/vinix-account-authority-fixture/account-authority-fixture'
const authority_sha = '8b4eacffb316404965280e4056eccb5bcbd8ab545bfdbce5f068f9b247c5c5c2'
const prefix = 'VINIX-BROWSER-RESULTS-1 '
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
	guest_sha256   string
	session_sha256 string
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
	scope         string = 'Separate real WebKit diagnostic; no credentials, Android integration, or Google authentication proof.'
	started_utc   string
	serial_device string = '/dev/console'
	guest_sha256  string
mut:
	finished_utc       string
	build_sha256       string
	addon_files_sha256 string
	browser            Run
	authority          Run
	status             string = 'failed'
	error              string
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
	payload := json2.encode(Archive{ root_mode: os.lstat(root)!.mode & 0o7777, entries: entries })
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
	if argv[0] == authority_path && !output.contains('ACCOUNT-AUTHORITY-PASS ') {
		result.status = 'failed'
		result.error = 'authority PASS marker absent'
	}
	return result
}

fn diagnostics(mut receipt Receipt) ! {
	build := bundle_root + '/build.json'
	addon := bundle_root + '/addon-files.json'
	pins := json2.decode[Pins](os.read_file(build)!)!
	if hash('/proc/self/exe')! != pins.guest_sha256 || hash(bundle_root + '/bin/browser-session')! != pins.session_sha256 {
		return error('guest/session build pin mismatch')
	}
	receipt.build_sha256 = hash(build)!
	receipt.addon_files_sha256 = hash(addon)!
	os.mkdir(result_root + '/inputs')!
	os.cp(build, result_root + '/inputs/build.json')!
	os.cp(addon, result_root + '/inputs/addon-files.json')!
	if os.exists(authority_path) || os.is_link(authority_path) {
		if os.is_link(authority_path) || hash(authority_path)! != authority_sha {
			return error('authority fixture pin mismatch')
		}
		receipt.authority = bounded([authority_path], result_root + '/authority.log', 30) or {
			Run{ status: 'failed', error: err.msg() }
		}
	} else {
		receipt.authority = Run{ status: 'absent-optional' }
	}
	receipt.browser = bounded([bundle_root + '/bin/browser-session', '/opt/vinix-android-aarch64',
		bundle_root + '/runtime', result_root + '/browser'], result_root + '/browser.log', 240)!
	// A hard-killed session cannot run its deferred alias cleanup. Preserve that
	// failure explicitly; never remove aliases this orchestrator did not create.
	for path in ['/usr/bin/xkbcomp', '/usr/libexec/webkitgtk-6.0/WebKitWebProcess',
		'/usr/libexec/webkitgtk-6.0/WebKitNetworkProcess', '/usr/libexec/webkitgtk-6.0/WebKitGPUProcess'] {
		if (os.readlink(path) or { '' }) == bundle_root + '/bin/browser-session' {
			receipt.browser.status = 'failed'
			receipt.browser.error += ' helper alias remains: ' + path
		}
	}
	if receipt.browser.status == 'passed' && receipt.authority.status in ['passed', 'absent-optional'] {
		receipt.status = 'passed'
	}
}

fn self_test() ! {
	root := os.join_path(os.temp_dir(), 'vinix-browser-guest-selftest-' + os.getpid().str())
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
	println('BROWSER-GUEST SELF-TEST PASS deterministic-tree modes binary-content symlink framing')
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
		eprintln('usage: browser-guest [--self-test]')
		exit(2)
	}
	$if !linux {
		eprintln('browser-guest requires the Linux ABI guest')
		exit(2)
	}
	if C.getuid() != 0 || C.geteuid() != 0 {
		eprintln('browser-guest requires guest root')
		exit(2)
	}
	enable_subreaper() or {
		eprintln(err.msg())
		exit(1)
	}
	if unsafe { C.mkdir(result_root.str, 0o700) } != 0 {
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
	println('BROWSER-GUEST exported status=' + receipt.status + ' sha256=' + sha256.sum(payload.bytes()).hex())
	if receipt.status != 'passed' { exit(1) }
}
