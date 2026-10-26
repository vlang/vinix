// SPDX-License-Identifier: GPL-2.0-or-later
// Host lifecycle for one audited, credential-free diagnostic guest.
module main

import crypto.sha256
import json2
import net
import net.unix
import os
import strconv
import time

#include <signal.h>
#include <errno.h>
#include <fcntl.h>
#include <CommonCrypto/CommonDigest.h>

fn C.kill(int, int) int
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const repo = '/Users/alex/code/vinix'
const qemu = repo + '/build/qemu-horizontal/bin/qemu-system-aarch64'
const firmware = '/opt/homebrew/share/qemu/edk2-aarch64-code.fd'
const source = $embed_file(@FILE).to_string()

struct Ownership {
	pid     int
	command string
	started string
}

struct Stage {
	format                int
	staged_boot_sha256    string
	staged_efivars_sha256 string
}

struct Execution {
	argv   []string
	code   int
	stdout string
	stderr string
}

struct StopReceipt {
	pid           int
	signal        string
	requested_utc string
}

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := C.CC_SHA256_CTX{}
	mut bytes := []u8{len: 1024 * 1024}
	if C.CC_SHA256_Init(unsafe { &digest }) != 1 { return error('SHA256 initialization') }
	for {
		n := file.read(mut bytes) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		if C.CC_SHA256_Update(unsafe { &digest }, bytes.data, u32(n)) != 1 {
			return error('SHA256 update')
		}
	}
	mut result := [32]u8{}
	if C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &digest }) != 1 {
		return error('SHA256 finalization')
	}
	return result[..].hex()
}

fn hash_self_test(root string) ! {
	path := root + '/sha256-input'
	defer { os.rm(path) or {} }
	for input, expected in {
		'': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
		'abc': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
	} {
		os.write_file(path, input)!
		assert hash(path)! == expected
	}
	mut bytes := []u8{len: 2 * 1024 * 1024 + 65}
	for i in 0 .. bytes.len { bytes[i] = u8((i * 29 + 11) % 251) }
	for size in [55, 56, 63, 64, 65, 1024 * 1024 - 1, 1024 * 1024, 1024 * 1024 + 1, bytes.len] {
		os.write_file_array(path, bytes[..size])!
		assert hash(path)! == sha256.sum(bytes[..size]).hex()
	}
	println('HOST-SHA256 SELF-TEST PASS known-vectors block-padding streaming-boundaries V-reference')
}

fn execute(argv []string) !Execution {
	mut process := os.new_process(argv[0])
	process.set_args(argv[1..])
	process.set_stdin_path('/dev/null')
	process.set_redirect_stdio()
	process.run()
	defer { process.close() }
	mut stdout := ''
	mut stderr := ''
	deadline := time.sys_mono_now() + 15 * time.second
	for {
		stdout += process.stdout_read()
		stderr += process.stderr_read()
		if stdout.len + stderr.len > 1024 * 1024 || time.sys_mono_now() >= deadline {
			process.signal_kill()
			process.wait()
			return error('command output/deadline limit')
		}
		if !process.is_alive() { break }
		time.sleep(10 * time.millisecond)
	}
	process.wait()
	for {
		out := process.stdout_read()
		err := process.stderr_read()
		stdout += out
		stderr += err
		if stdout.len + stderr.len > 1024 * 1024 {
			return error('command output limit')
		}
		if out == '' && err == '' { break }
	}
	return Execution{argv, process.code, stdout, stderr}
}

fn checked(argv []string) !string {
	result := execute(argv)!
	if result.code != 0 { return error('command failed: ' + argv[0] + ': ' + result.stderr) }
	return result.stdout.trim_space()
}

fn canonical_root(path string) !string {
	absolute := os.abs_path(path)
	if !os.is_dir(absolute) || os.real_path(absolute) != absolute || absolute.contains_any(' \t\r\n,\x00') {
		return error('canonical directory without whitespace/comma required')
	}
	if absolute == repo || absolute.starts_with(repo + '/') {
		return error('external staged directory required')
	}
	if !os.is_file(absolute + '/stage.json') { return error('browser stage receipt required') }
	return absolute
}

fn qmp_check(root string) ! {
	if (root + '/qmp.sock').len >= 104 {
		return error('QMP Unix socket path must be shorter than 104 bytes')
	}
}

fn identity(pid int) !Ownership {
	if pid <= 1 { return error('invalid process ID') }
	return Ownership{pid, checked(['/bin/ps', '-ww', '-p', pid.str(), '-o', 'command='])!, checked([
		'/bin/ps',
		'-p',
		pid.str(),
		'-o',
		'lstart=',
	])!}
}

fn recorded_owner(root string) !Ownership {
	recorded := json2.decode[Ownership](os.read_file(root + '/ownership.json')!)!
	if recorded.pid <= 1 || recorded.started == '' || !recorded.command.starts_with(qemu + ' ')
		|| !recorded.command.contains('unix:' + root + '/qmp.sock,server=on,wait=off')
		|| !recorded.command.ends_with('-pidfile ' + root + '/qemu.pid') {
		return error('invalid recorded guest ownership')
	}
	return recorded
}

// One ps snapshot avoids the command/start-time race when a process exits.
// The immutable ownership receipt remains authoritative after QEMU unlinks its
// transient pidfile; only an initial signal additionally requires that pidfile.
fn process_gone(recorded Ownership) !bool {
	if recorded.pid <= 1 { return error('invalid process ID') }
	result := execute(['/bin/ps', '-ww', '-p', recorded.pid.str(), '-o', 'lstart=,command='])!
	output := result.stdout.trim_space()
	if result.code == 1 && output == '' && result.stderr.trim_space() == '' { return true }
	if result.code != 0 {
		return error('could not inspect guest process: ps exit ' + result.code.str())
	}
	if !output.starts_with(recorded.started + ' ')
		|| output[recorded.started.len..].trim_space() != recorded.command {
		return error('live process ownership differs; refusing signal or disappearance receipt')
	}
	return false
}

fn owned(root string) !Ownership {
	recorded := recorded_owner(root)!
	if strconv.atoi(os.read_file(root + '/qemu.pid')!.trim_space())! != recorded.pid {
		return error('PID receipt differs')
	}
	if process_gone(recorded)! { return error('owned guest is no longer live') }
	return recorded
}

fn write_json(path string, value json2.Any) ! {
	mut file := os.open_file(path, 'wx', 0o600)!
	defer { file.close() }
	file.write_string(json2.encode(value, prettify: true) + '\n')!
}

fn fresh_launch(root string) ! {
	// QEMU interprets %d in -D paths as a filename template.
	if root.contains('%') { return error('literal daemon log path required') }
	for name in ['launch.json', 'launch-result.json', 'ownership.json', 'qemu.pid', 'qmp.sock',
		'serial.log', 'network.pcap', 'qemu.log', 'stop.json', 'gone.json', 'run-source.v', 'runner'] {
		if os.exists(root + '/' + name) || os.is_link(root + '/' + name) {
			return error('guest can be launched once only: ' + name)
		}
	}
}

fn verify_daemon_log(root string, before os.Stat) ! {
	info := os.lstat(root + '/qemu.log')!
	if info.get_filetype() != .regular || info.uid != u32(os.geteuid())
		|| info.nlink != 1 || info.mode & 0o777 != 0o600
		|| info.dev != before.dev || info.inode != before.inode {
		return error('same private single-linked daemon log required')
	}
}

fn create_daemon_log(root string) !os.Stat {
	if root.contains('%') { return error('literal daemon log path required') }
	path := root + '/qemu.log'
	// This pinned V library ignores x in open_file's mode string.
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('cannot exclusively create private daemon log') }
	defer { C.close(fd) }
	before := os.lstat(root + '/qemu.log')!
	verify_daemon_log(root, before)!
	return before
}

fn launch_args(root string) []string {
	return ['-qmp', 'unix:' + root + '/qmp.sock,server=on,wait=off', '-machine', 'virt,gic-version=3',
		'-accel', 'hvf', '-cpu', 'host', '-m', '12288', '-smp', '4', '-object',
		'rng-random,filename=/dev/urandom,id=vinix-rng', '-device', 'virtio-rng-device', '-drive',
		'if=pflash,format=raw,readonly=on,file=' + firmware, '-drive',
		'if=pflash,format=raw,file=' + root + '/efivars.fd', '-drive',
		'format=raw,file=' + root + '/boot.img', '-device', 'virtio-keyboard-device', '-device',
		'virtio-tablet-device', '-device', 'ramfb', '-netdev', 'user,id=net0', '-device',
		'virtio-net-device,netdev=net0', '-object',
		'filter-dump,id=capture,netdev=net0,file=' + root + '/network.pcap', '-display', 'none',
		'-monitor', 'none', '-serial', 'file:' + root + '/serial.log', '-daemonize', '-D',
		root + '/qemu.log', '-pidfile',
		root + '/qemu.pid']
}

fn start(root string) ! {
	qmp_check(root)!
	fresh_launch(root)!
	for line in checked(['/bin/ps', '-axo', 'pid=,command='])!.split_into_lines() {
		if line.contains('qemu-system-aarch64 ') && line.contains(' -machine ') {
			return error('another aarch64 QEMU guest is live')
		}
	}
	stage := json2.decode[Stage](os.read_file(root + '/stage.json')!)!
	if stage.format != 1 || hash(root + '/boot.img')! != stage.staged_boot_sha256
		|| hash(root + '/efivars.fd')! != stage.staged_efivars_sha256 {
		return error('staged media changed')
	}
	log_before := create_daemon_log(root)!
	mut argv := [qemu]
	argv << launch_args(root)
	os.write_file(root + '/run-source.v', source)!
	os.cp(os.executable(), root + '/runner')!
	write_json(root + '/launch.json', json2.decode[json2.Any](json2.encode({
		'argv':                 json2.Any(argv)
		'started_utc':          json2.Any(time.utc().str())
		'stage_sha256':         json2.Any(hash(root + '/stage.json')!)
		'qemu_sha256':          json2.Any(hash(qemu)!)
		'firmware_sha256':      json2.Any(hash(firmware)!)
		'runner_sha256':        json2.Any(hash(os.executable())!)
		'runner_source_sha256': json2.Any(sha256.sum(source.bytes()).hex())
		'daemon_stderr_path':   json2.Any(root + '/qemu.log')
		'daemon_stderr_before': json2.decode[json2.Any](json2.encode(log_before))!
		'daemon_stderr_scope':  json2.Any('QEMU -D retains normal daemon stderr; no -d tracing; exit cause requires observed evidence.')
		'scope':                json2.Any('Separate credential-free real-engine diagnostic; no Google authentication proof.')
	}))!)!
	result := execute(argv)!
	write_json(root + '/launch-result.json', json2.decode[json2.Any](json2.encode(result))!)!
	if result.code != 0 { return error('QEMU launch failed: ' + result.stderr) }
	verify_daemon_log(root, log_before)!
	pid := strconv.atoi(os.read_file(root + '/qemu.pid')!.trim_space())!
	write_json(root + '/ownership.json', json2.decode[json2.Any](json2.encode(identity(pid)!))!)!
	println('BROWSER-RUN STARTED pid=' + owned(root)!.pid.str() + ' state=' + root)
}

fn stopped(root string) !bool {
	return process_gone(recorded_owner(root)!)
}

// Observe an already absent guest without attributing an exit status or signal.
// A requested stop has its separate reconciliation path and receipt chain.
fn observe_gone(root string) ! {
	for name in ['stop.json', 'gone.json'] {
		if os.exists(root + '/' + name) || os.is_link(root + '/' + name) {
			return error('read-only disappearance observation requires no ' + name)
		}
	}
	ownership_sha := hash(root + '/ownership.json')!
	owner := recorded_owner(root)!
	if !process_gone(owner)! { return error('owned guest remains live; no signal sent') }
	if hash(root + '/ownership.json')! != ownership_sha {
		return error('guest ownership changed during disappearance observation')
	}
	write_json(root + '/gone.json', json2.decode[json2.Any](json2.encode({
		'pid':              json2.Any(owner.pid)
		'checked_utc':      json2.Any(time.utc().str())
		'check':            json2.Any('one ps snapshot returned exit1 with empty stdout and stderr for recorded owned PID')
		'ownership_sha256': json2.Any(ownership_sha)
		'stop_requested':   json2.Any(false)
		'exit_status':      json2.Any('unknown')
		'cause':            json2.Any('unobserved; this command sent no signal')
	}))!)!
	println('BROWSER-RUN OBSERVED-GONE pid=' + owner.pid.str() + ' exit=unknown cause=unobserved')
}

fn observed_receipt(root string, owner Ownership, ownership_sha string) !string {
	for name in ['ownership.json', 'gone.json'] {
		if os.lstat(root + '/' + name)!.get_filetype() != .regular {
			return error('regular non-symlink receipt required for cleanup: ' + name)
		}
	}
	if os.exists(root + '/stop.json') || os.is_link(root + '/stop.json') {
		return error('cleanup-gone requires an unrequested disappearance')
	}
	text := os.read_file(root + '/gone.json')!
	fields := json2.decode[map[string]json2.Any](text)!
	mut names := fields.keys()
	names.sort()
	if names != ['cause', 'check', 'checked_utc', 'exit_status', 'ownership_sha256', 'pid',
		'stop_requested']
		|| json2.encode(fields['pid']!) != owner.pid.str()
		|| fields['ownership_sha256']!.str() != ownership_sha
		|| fields['checked_utc']!.str() == ''
		|| json2.encode(fields['stop_requested']!) != 'false'
		|| json2.encode(fields['exit_status']!) != '"unknown"'
		|| json2.encode(fields['cause']!) != '"unobserved; this command sent no signal"'
		|| json2.encode(fields['check']!) != '"one ps snapshot returned exit1 with empty stdout and stderr for recorded owned PID"' {
		return error('exact observed-absence receipt required for cleanup')
	}
	return sha256.sum(text.bytes()).hex()
}

fn refused_socket(path string) ! {
	addresses := net.resolve_addrs(path, .unix, .tcp)!
	if addresses.len != 1 { return error('one exact Unix socket address required') }
	address := addresses[0]
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return error('cannot create cleanup socket probe') }
	defer { C.close(fd) }
	net.set_blocking(fd, false)!
	if C.connect(fd, voidptr(&address), address.len()) == 0 {
		return error('QMP socket has an active listener; refusing cleanup')
	}
	if net.error_code() != C.ECONNREFUSED {
		return error('QMP socket probe did not return ECONNREFUSED; refusing cleanup')
	}
}

// Remove only the exact stale socket of an already observed absent guest.
// A separate request survives failures; no signal or exit status is inferred.
fn cleanup_gone(root string) ! {
	for name in ['qmp-cleanup-request.json', 'qmp-cleanup.json', 'qmp-cleanup-source.v',
		'qmp-cleanup-runner'] {
		if os.exists(root + '/' + name) || os.is_link(root + '/' + name) {
			return error('cleanup evidence already exists: ' + name)
		}
	}
	ownership_sha := hash(root + '/ownership.json')!
	owner := recorded_owner(root)!
	gone_sha := observed_receipt(root, owner, ownership_sha)!
	if !process_gone(owner)! { return error('owned guest remains live; no signal sent') }
	path := root + '/qmp.sock'
	before := os.lstat(path)!
	if before.get_filetype() != .socket || before.uid != u32(os.geteuid()) {
		return error('exact non-symlink socket owned by this user required')
	}
	refused_socket(path)!
	os.write_file(root + '/qmp-cleanup-source.v', source)!
	os.cp(os.executable(), root + '/qmp-cleanup-runner')!
	write_json(root + '/qmp-cleanup-request.json', json2.Any({
		'action': json2.Any('unlink exact stale QMP socket after observed guest disappearance')
		'path': json2.Any(path)
		'path_kind': json2.Any('socket; lstat did not follow a symlink')
		'socket_before': json2.decode[json2.Any](json2.encode(before))!
		'pid': json2.Any(owner.pid)
		'ownership_sha256': json2.Any(ownership_sha)
		'gone_sha256': json2.Any(gone_sha)
		'socket_check': json2.Any('nonblocking AF_UNIX connect returned ECONNREFUSED')
		'requested_utc': json2.Any(time.utc().str())
		'runner_sha256': json2.Any(hash(root + '/qmp-cleanup-runner')!)
		'runner_source_sha256': json2.Any(hash(root + '/qmp-cleanup-source.v')!)
		'signal_sent': json2.Any(false)
	}))!
	if !process_gone(owner)! || hash(root + '/ownership.json')! != ownership_sha
		|| observed_receipt(root, owner, ownership_sha)! != gone_sha {
		return error('guest ownership or disappearance changed before cleanup')
	}
	refused_socket(path)!
	current := os.lstat(path)!
	if current != before { return error('QMP socket identity changed before cleanup') }
	os.rm(path)!
	if os.exists(path) || os.is_link(path) { return error('QMP socket remains after cleanup') }
	if hash(root + '/ownership.json')! != ownership_sha
		|| observed_receipt(root, owner, ownership_sha)! != gone_sha {
		return error('guest ownership or disappearance changed during cleanup')
	}
	write_json(root + '/qmp-cleanup.json', json2.Any({
		'path': json2.Any(path)
		'removed': json2.Any(true)
		'completed_utc': json2.Any(time.utc().str())
		'request_sha256': json2.Any(hash(root + '/qmp-cleanup-request.json')!)
		'ownership_sha256': json2.Any(ownership_sha)
		'gone_sha256': json2.Any(gone_sha)
		'signal_sent': json2.Any(false)
	}))!
	println('BROWSER-RUN CLEANED-GONE-QMP pid=' + owner.pid.str() + ' path=' + path + ' signal=none')
}

fn cleanup_self_test(root string) ! {
	owner_text := os.read_file(root + '/ownership.json')!
	gone_text := os.read_file(root + '/gone.json')!
	path := root + '/qmp.sock'
	if _ := cleanup_gone(root) { return error('missing QMP socket accepted') }
	os.write_file(path, 'regular evidence')!
	if _ := cleanup_gone(root) { return error('regular QMP path accepted') }
	if os.read_file(path)! != 'regular evidence' { return error('regular QMP evidence changed') }
	os.rm(path)!
	os.mkdir(path)!
	if _ := cleanup_gone(root) { return error('directory QMP path accepted') }
	if !os.is_dir(path) { return error('directory QMP evidence changed') }
	os.rmdir(path)!
	mut listener := unix.listen_stream(path)!
	if _ := cleanup_gone(root) { return error('active replacement QMP listener accepted') }
	if os.lstat(path)!.get_filetype() != .socket { return error('active QMP socket changed') }
	// Drain the rejected connection before closing this test listener.
	mut accepted := listener.accept()!
	accepted.close()!
	unix.shutdown(listener.sock.handle)
	if C.close(listener.sock.handle) != 0 { return error('cannot close test QMP listener') }
	os.mv(path, root + '/actual.sock')!
	os.symlink(root + '/actual.sock', path)!
	if _ := cleanup_gone(root) { return error('QMP symlink accepted') }
	if !os.is_link(path) || os.lstat(root + '/actual.sock')!.get_filetype() != .socket {
		return error('symlink QMP evidence changed')
	}
	os.rm(path)!
	os.mv(root + '/actual.sock', path)!
	mut live_owner := json2.decode[Ownership](owner_text)!
	live_identity := identity(os.getpid())!
	live_owner = Ownership{ pid: live_identity.pid, started: live_identity.started, command: live_owner.command }
	os.write_file(root + '/ownership.json', json2.encode(live_owner))!
	mut live_gone := json2.decode[map[string]json2.Any](gone_text)!
	live_gone['pid'] = live_owner.pid
	live_gone['ownership_sha256'] = hash(root + '/ownership.json')!
	os.write_file(root + '/gone.json', json2.encode(live_gone))!
	if _ := cleanup_gone(root) { return error('reused live PID accepted for QMP cleanup') }
	if os.lstat(path)!.get_filetype() != .socket || os.exists(root + '/qmp-cleanup-request.json') {
		return error('live PID caused cleanup mutation')
	}
	os.write_file(root + '/ownership.json', owner_text)!
	os.write_file(root + '/gone.json', gone_text)!
	for action in ['wrong-owner', 'wrong-pid', 'missing-false', 'signal-claim', 'true-stop'] {
		mut fields := json2.decode[map[string]json2.Any](gone_text)!
		match action {
			'wrong-owner' { fields['ownership_sha256'] = '0'.repeat(64) }
			'wrong-pid' { fields['pid'] = os.getpid() }
			'missing-false' { fields.delete('stop_requested') }
			'signal-claim' { fields['signal'] = 'SIGTERM' }
			'true-stop' { fields['stop_requested'] = true }
			else {}
		}
		os.write_file(root + '/gone.json', json2.encode(fields))!
		if _ := cleanup_gone(root) { return error('QMP cleanup accepted ' + action) }
		if os.lstat(path)!.get_filetype() != .socket || os.exists(root + '/qmp-cleanup-request.json') {
			return error('invalid disappearance caused cleanup mutation')
		}
	}
	os.write_file(root + '/gone.json', gone_text)!
	for name in ['ownership.json', 'gone.json'] {
		os.mv(root + '/' + name, root + '/' + name + '.saved')!
		os.symlink(root + '/' + name + '.saved', root + '/' + name)!
		if _ := cleanup_gone(root) { return error('symlink cleanup receipt accepted') }
		os.rm(root + '/' + name)!
		os.mv(root + '/' + name + '.saved', root + '/' + name)!
	}
	os.symlink(root + '/absent-stop', root + '/stop.json')!
	if _ := cleanup_gone(root) { return error('stop symlink accepted for cleanup') }
	os.rm(root + '/stop.json')!
	os.write_file(root + '/qmp-cleanup-request.json', 'previous request')!
	if _ := cleanup_gone(root) { return error('previous cleanup request accepted') }
	if os.read_file(root + '/qmp-cleanup-request.json')! != 'previous request' {
		return error('previous cleanup request changed')
	}
	os.rm(root + '/qmp-cleanup-request.json')!
	os.symlink(root + '/absent-cleanup', root + '/qmp-cleanup.json')!
	if _ := cleanup_gone(root) { return error('cleanup receipt symlink accepted') }
	os.rm(root + '/qmp-cleanup.json')!
	if os.read_file(root + '/ownership.json')! != owner_text || os.read_file(root + '/gone.json')! != gone_text {
		return error('rejected cleanup changed original ownership or disappearance')
	}
	os.write_file(root + '/retained-serial.log', 'unchanged UART evidence\x00exact')!
	before := os.lstat(path)!
	cleanup_gone(root)!
	if os.exists(path) || os.is_link(path) || os.read_file(root + '/ownership.json')! != owner_text
		|| os.read_file(root + '/gone.json')! != gone_text
		|| os.read_file(root + '/retained-serial.log')! != 'unchanged UART evidence\x00exact' {
		return error('cleanup failed to remove only the stale socket')
	}
	request := json2.decode[map[string]json2.Any](os.read_file(root + '/qmp-cleanup-request.json')!)!
	if request['path']!.str() != path || request['signal_sent']!.bool()
		|| request['ownership_sha256']!.str() != hash(root + '/ownership.json')!
		|| request['gone_sha256']!.str() != hash(root + '/gone.json')!
		|| json2.decode[os.Stat](json2.encode(request['socket_before']!))! != before {
		return error('cleanup request receipt differs from observed socket or ownership')
	}
	completion := json2.decode[map[string]json2.Any](os.read_file(root + '/qmp-cleanup.json')!)!
	if !completion['removed']!.bool() || completion['signal_sent']!.bool()
		|| completion['request_sha256']!.str() != hash(root + '/qmp-cleanup-request.json')! {
		return error('cleanup completion receipt differs')
	}
	mut files := os.ls(root)!
	files.sort()
	if files != ['gone.json', 'ownership.json', 'qmp-cleanup-request.json',
		'qmp-cleanup-runner', 'qmp-cleanup-source.v', 'qmp-cleanup.json', 'retained-serial.log'] {
		return error('cleanup changed the exact evidence file allowlist')
	}
	if _ := cleanup_gone(root) { return error('repeated cleanup accepted') }
}

fn reconcile_stop(root string) ! {
	owner := recorded_owner(root)!
	stop_receipt := json2.decode[StopReceipt](os.read_file(root + '/stop.json')!)!
	if stop_receipt.pid != owner.pid || stop_receipt.signal != 'SIGTERM'
		|| stop_receipt.requested_utc == '' {
		return error('stop receipt differs from recorded guest')
	}
	if os.exists(root + '/gone.json') || os.is_link(root + '/gone.json') {
		return error('disappearance receipt already exists')
	}
	deadline := time.sys_mono_now() + 5 * time.second
	for {
		if stopped(root)! {
			write_json(root + '/gone.json', json2.decode[json2.Any](json2.encode({
				'pid':              json2.Any(owner.pid)
				'checked_utc':      json2.Any(time.utc().str())
				'check':            json2.Any('one ps snapshot returned exit1 with empty stdout and stderr for recorded owned PID')
				'ownership_sha256': json2.Any(hash(root + '/ownership.json')!)
				'stop_sha256':      json2.Any(hash(root + '/stop.json')!)
			}))!)!
			println('BROWSER-RUN STOPPED pid=' + owner.pid.str())
			return
		}
		if time.sys_mono_now() >= deadline {
			return error('owned guest remains after SIGTERM; no further signal sent')
		}
		time.sleep(100 * time.millisecond)
	}
}

fn stop(root string) ! {
	if os.exists(root + '/stop.json') || os.is_link(root + '/stop.json') {
		return error('stop already requested; reconcile-stop sends no additional signal')
	}
	owner := owned(root)!
	if C.kill(owner.pid, C.SIGTERM) != 0 { return error('could not signal owned guest') }
	write_json(root + '/stop.json', json2.decode[json2.Any](json2.encode(StopReceipt{
		pid:           owner.pid
		signal:        'SIGTERM'
		requested_utc: time.utc().str()
	}))!)!
	reconcile_stop(root)!
}

fn daemon_log_self_test(root string) ! {
	fresh_launch(root)!
	if _ := fresh_launch(root + '%d') { return error('QEMU log template accepted') }
	if _ := create_daemon_log(root + '%d') { return error('QEMU log template created') }
	if _ := verify_daemon_log(root, os.Stat{}) { return error('missing daemon log accepted') }
	args := launch_args(root)
	assert args.filter(it == '-D').len == 1 && '-d' !in args
	assert args[args.index('-D') + 1] == root + '/qemu.log'
	assert '-daemonize' in args
	assert args[0..2] == ['-qmp', 'unix:' + root + '/qmp.sock,server=on,wait=off']
	assert args[args.len - 2..] == ['-pidfile', root + '/qemu.pid']
	before := create_daemon_log(root)!
	assert before.size == 0
	if _ := fresh_launch(root) { return error('existing daemon log accepted by launch') }
	if _ := create_daemon_log(root) { return error('existing daemon log overwritten') }
	// A child reopens the production -D destination and redirects real fd 2,
	// matching the reviewed QEMU daemon code without starting a guest.
	fixture := execute([os.executable(), '--self-test-daemon-log', ...args])!
	assert fixture.code == 0 && fixture.stdout == '' && fixture.stderr == ''
	assert os.read_file(root + '/qemu.log')! == 'BROWSER-RUN DAEMON-STDERR-FIXTURE\n'
	verify_daemon_log(root, before)!
	os.chmod(root + '/qemu.log', 0o644)!
	if _ := verify_daemon_log(root, before) { return error('public daemon log accepted') }
	os.chmod(root + '/qemu.log', 0o600)!
	os.link(root + '/qemu.log', root + '/log-hardlink')!
	if _ := verify_daemon_log(root, before) { return error('hard-linked daemon log accepted') }
	os.rm(root + '/log-hardlink')!
	os.mv(root + '/qemu.log', root + '/log-original')!
	create_daemon_log(root)!
	if _ := verify_daemon_log(root, before) { return error('replacement daemon log accepted') }
	os.rm(root + '/qemu.log')!
	os.symlink(root + '/absent-log', root + '/qemu.log')!
	if _ := fresh_launch(root) { return error('dangling daemon log symlink accepted') }
	if _ := create_daemon_log(root) { return error('daemon log symlink overwritten') }
	if _ := verify_daemon_log(root, before) { return error('daemon log symlink accepted') }
	os.rm(root + '/qemu.log')!
	os.mkdir(root + '/qemu.log')!
	if _ := verify_daemon_log(root, before) { return error('daemon log directory accepted') }
	os.rmdir(root + '/qemu.log')!
	os.mv(root + '/log-original', root + '/qemu.log')!
	verify_daemon_log(root, before)!
	os.rm(root + '/qemu.log')!
	if _ := verify_daemon_log(root, before) { return error('removed daemon log accepted') }
	println('DAEMON-STDERR SELF-TEST PASS literal-exact-argv no-debug-tracing exclusive-private-file real-fd2-destination missing-existing-symlink-directory-hardlink-permissions-replacement-rejection')
}

fn self_test() ! {
	qmp_check('/tmp/browser-probe')!
	if _ := qmp_check('/' + 'x'.repeat(103)) { return error('oversized QMP path accepted') }
	if _ := canonical_root(repo) { return error('repository output accepted') }
	if _ := identity(1) { return error('unsafe PID accepted') }
	result := execute(['/bin/ps', '-p', os.getpid().str(), '-o', 'pid='])!
	assert result.code == 0 && result.stdout.trim_space() == os.getpid().str()
	output := execute([os.executable(), '--self-test-output'])!
	assert output.code == 0 && output.stdout == 'o'.repeat(65536) + '\n'
	assert output.stderr == 'e'.repeat(65536) + '\n'
	failed := execute([os.executable(), '--self-test-exit'])!
	assert failed.code == 7 && failed.stdout == '' && failed.stderr == ''
	root := os.join_path(os.temp_dir(), 'vinix-browser-run-selftest-' + os.getpid().str())
	if os.exists(root) || os.is_link(root) { return error('selftest output exists') }
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	daemon_log_self_test(root)!
	hash_self_test(root)!
	os.write_file(root + '/qemu.pid', os.getpid().str())!
	write_json(root + '/ownership.json', json2.decode[json2.Any](json2.encode(identity(os.getpid())!))!)!
	if _ := owned(root) { return error('non-QEMU process accepted as owned guest') }
	if _ := observe_gone(root) { return error('non-QEMU ownership accepted for disappearance') }
	assert !os.exists(root + '/gone.json')
	mut child := os.new_process(os.executable())
	child.set_args(['--self-test-child'])
	child.run()
	defer {
		if child.is_alive() { child.signal_kill() }
		child.wait()
		child.close()
	}
	live := identity(child.pid)!
	os.rm(root + '/qemu.pid')!
	assert !process_gone(live)!
	if _ := process_gone(Ownership{ pid: live.pid, started: live.started, command: live.command + ' changed' }) {
		return error('changed live command accepted')
	}
	child.wait()
	assert process_gone(live)!
	missing := execute(['/bin/ps', '-ww', '-p', child.pid.str(), '-o', 'lstart=,command='])!
	assert missing.code == 1 && missing.stdout.trim_space() == '' && missing.stderr.trim_space() == ''
	assert !os.exists(root + '/qemu.pid')
	os.rm(root + '/ownership.json')!
	fake := Ownership{
		pid:     child.pid
		started: live.started
		command: qemu + ' -qmp unix:' + root + '/qmp.sock,server=on,wait=off -pidfile ' + root + '/qemu.pid'
	}
	write_json(root + '/ownership.json', json2.decode[json2.Any](json2.encode(fake))!)!
	assert stopped(root)!
	if _ := reconcile_stop(root) { return error('missing stop receipt accepted') }
	observe_gone(root)!
	observed := json2.decode[json2.Any](os.read_file(root + '/gone.json')!)!
	assert observed.as_map()['stop_requested']!.bool() == false
	assert observed.as_map()['exit_status']!.str() == 'unknown'
	assert !os.exists(root + '/stop.json')
	if _ := observe_gone(root) { return error('existing disappearance observation accepted') }
	cleanup_self_test(root)!
	os.rm(root + '/gone.json')!
	write_json(root + '/stop.json', json2.decode[json2.Any](json2.encode(StopReceipt{
		pid:           child.pid
		signal:        'SIGTERM'
		requested_utc: time.utc().str()
	}))!)!
	if _ := observe_gone(root) { return error('stop request accepted for read-only disappearance') }
	assert !os.exists(root + '/gone.json')
	reconcile_stop(root)!
	assert os.is_file(root + '/gone.json')
	if _ := reconcile_stop(root) { return error('existing disappearance receipt accepted') }
	println('BROWSER-RUN SELF-TEST PASS qmp-length external-directory unsafe-pid bounded-command complete-output foreign-owner nonzero-exit live-without-pidfile reaped-child absent-ps reconcile-stop observe-gone no-invented-signal stale-socket-cleanup active-socket-rejection exact-cleanup-allowlist')
}

fn main() {
	if os.args.len > 2 && os.args[1] == '--self-test-daemon-log' {
		args := os.args[2..]
		assert args.filter(it == '-D').len == 1 && '-daemonize' in args && '-d' !in args
		mut file := os.open_file(args[args.index('-D') + 1], 'w')!
		if C.dup2(file.fd, 2) != 2 { exit(1) }
		file.close()
		eprintln('BROWSER-RUN DAEMON-STDERR-FIXTURE')
		return
	}
	if os.args.len == 2 && os.args[1] == '--self-test-output' {
		println('o'.repeat(65536))
		eprintln('e'.repeat(65536))
		return
	}
	if os.args.len == 2 && os.args[1] == '--self-test-exit' { exit(7) }
	if os.args.len == 2 && os.args[1] == '--self-test-child' {
		time.sleep(time.second)
		return
	}
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	if os.args.len != 3 || os.args[1] !in ['start', 'status', 'stop', 'reconcile-stop', 'observe-gone', 'cleanup-gone'] {
		eprintln('usage: run start|status|stop|reconcile-stop|observe-gone|cleanup-gone STAGED_EXTERNAL_DIRECTORY')
		exit(2)
	}
	root := canonical_root(os.args[2]) or {
		eprintln(err.msg())
		exit(1)
	}
	match os.args[1] {
		'start' {
			start(root) or {
				eprintln(err.msg())
				exit(1)
			}
		}
		'stop' {
			stop(root) or {
				eprintln(err.msg())
				exit(1)
			}
		}
		'reconcile-stop' {
			reconcile_stop(root) or {
				eprintln(err.msg())
				exit(1)
			}
		}
		'observe-gone' {
			observe_gone(root) or {
				eprintln(err.msg())
				exit(1)
			}
		}
		'cleanup-gone' {
			cleanup_gone(root) or {
				eprintln(err.msg())
				exit(1)
			}
		}
		'status' {
			gone := stopped(root) or {
				eprintln(err.msg())
				exit(1)
			}
			println(if gone {
				'BROWSER-RUN STOPPED'
			} else {
				'BROWSER-RUN LIVE pid=' + recorded_owner(root) or {
					eprintln(err.msg())
					exit(1)
				}.pid.str()
			})
		}
		else {}
	}
}
