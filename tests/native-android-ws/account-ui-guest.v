// SPDX-License-Identifier: GPL-2.0-or-later
// Root-only real desktop helper diagnostic, invoked from a GUI terminal.
// No Android Activity, account, credential or Google sign-in operations.
module main

import crypto.sha256
import encoding.base64
import json2
import net as _
import os
import time

#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

$if linux {
	#include <sys/prctl.h>
	#include <sys/wait.h>
}

fn C.prctl(int, u64, u64, u64, u64) int
fn C.waitpid(int, &int, int) int
const bundle_root = '/opt/vinix-account-ui'
const result_root = bundle_root + '/results'
const controller_path = bundle_root + '/bin/account-ui-controller'
const helper_path = bundle_root + '/bin/vinix-android-account-ui'
const controller_sha = '5c5d6415f3e97cb2369187a7aa373aca019ae1e085298daf4551789739851f18'
const helper_sha = 'eff0ee8da211772f2549a5b39fdb2739cbb746db44e859bc25bd56b854fbd989'
const source_revision = 'c5fc9065af1e624002eaff6e2f927ce79858a06e'
const pass_marker = 'ACCOUNT-UI-CONTROLLER-PASS ready handoff seals frame lifetime-eof single-use'
const prefix = 'VINIX-ACCOUNT-UI-RESULTS-1 '
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
	kind          string
	source_revision string
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
	scope         string = 'Real desktop helper and root UI controller only; no Android Activity, account, credential or Google sign-in proof.'
	started_utc   string
	serial_device string = '/dev/console'
	guest_sha256  string
mut:
	finished_utc  string
	build_sha256  string
	desktop       DesktopIdentity
	controller    Run
	status        string = 'failed'
	error         string
}

struct Identity {
	pid    int
	parent int
	start  string
}

struct Peer {
	pid i32
	uid u32
	gid u32
}

struct PathIdentity {
	path string
	dev u64
	inode u64
	uid u32
	gid u32
	mode u32
	kind string
}

struct DesktopIdentity {
	process Identity
	uid u32
	gid u32
	executable string
	executable_sha256 string
	window_socket string
	peer Peer
	paths []PathIdentity
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
	if line.len >= 1024 || !line.starts_with(prefix) || !line.ends_with('\n')
		|| line[..line.len - 1].contains_any('\r\n') {
		return error('invalid bounded serial frame')
	}
	// Close an unfinished console message and emit the complete frame in the
	// same write. A partial write is damaged evidence, never a retryable suffix.
	framed := '\n' + line
	n := unsafe { C.write(fd, framed.str, uint(framed.len)) }
	if n != framed.len { return error('single serial-frame write was incomplete') }
}

fn export_serial(payload string) ! {
	fd := C.open(c'/dev/console', C.O_WRONLY | C.O_NOCTTY | C.O_CLOEXEC)
	if fd < 0 { return error('cannot open serial-mirroring /dev/console') }
	defer { C.close(fd) }
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
			child.signal_kill()
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

fn number(text string) !u32 {
	if text == '' || text.len > 10 || (text.len > 1 && text[0] == `0`)
		|| !text.bytes().all(it >= `0` && it <= `9`) || text.u64() > 0xffffffff {
		return error('noncanonical Unix identity')
	}
	return text.u32()
}

fn status_id(text string, label string) !u32 {
	lines := text.split_into_lines().filter(it.starts_with(label + ':'))
	if lines.len != 1 { return error('missing/duplicate process credential: ' + label) }
	fields := lines[0].fields()
	if fields.len != 5 { return error('process credential field count: ' + label) }
	id := number(fields[1])!
	for field in fields[2..] {
		if number(field)! != id { return error('mixed process credentials: ' + label) }
	}
	return id
}

fn window_path(uid u32) string {
	return if uid == 0 { '/run/vinix-session.0/windows' } else {
		'/run/user/' + uid.str() + '/vinix-session.' + uid.str() + '/windows'
	}
}

fn protected(path string, owner u32, private bool, kind os.FileType) !PathIdentity {
	st := os.lstat(path)!
	mask := if private { u32(0o077) } else { u32(0o022) }
	if st.get_filetype() != kind || st.uid != owner || st.mode & mask != 0
		|| st.mode & 0o7000 != 0 {
		return error('unexpected path type/owner/protection: ' + path)
	}
	return PathIdentity{path, st.dev, st.inode, st.uid, st.gid, st.mode, kind.str()}
}

fn window_identity(uid u32) ![]PathIdentity {
	mut paths := []PathIdentity{}
	for path in ['/', '/run'] { paths << protected(path, 0, false, .directory)! }
	if uid != 0 {
		paths << protected('/run/user', 0, false, .directory)!
		paths << protected('/run/user/' + uid.str(), uid, true, .directory)!
	}
	socket := window_path(uid)
	paths << protected(os.dir(socket), uid, true, .directory)!
	paths << protected(socket, uid, true, .socket)!
	if paths[paths.len - 2].mode & 0o777 != 0o700 || paths.last().mode & 0o777 != 0o600 {
		return error('window directory/socket must be 0700/0600')
	}
	return paths
}

fn window_peer(path string) !Peer {
	$if linux {
		fd := C.socket(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_CLOEXEC | C.SOCK_NONBLOCK, 0)
		if fd < 0 { return error('cannot create bounded window identity connection') }
		defer { C.close(fd) }
		mut address := C.sockaddr_un{}
		address.sun_family = C.AF_UNIX
		if path.len == 0 || path.len >= address.sun_path.len { return error('window socket path limit') }
		unsafe { C.memcpy(&address.sun_path[0], path.str, uint(path.len)) }
		if C.connect(fd, voidptr(&address), u32(sizeof(C.sockaddr_un))) != 0 {
			return error('cannot connect immediately to live window server')
		}
		mut peer := Peer{}
		mut size := u32(sizeof(Peer))
		if C.getsockopt(fd, C.SOL_SOCKET, C.SO_PEERCRED, &peer, &size) != 0
			|| size != sizeof(Peer) || peer.pid <= 0 { return error('cannot authenticate window server') }
		return peer
	} $else {
		return error('window peer identity requires Linux ABI')
	}
}

fn account_identity(passwd string, group string, uid u32, gid u32) ! {
	mut users := 0
	for line in passwd.split_into_lines() {
		if line == '' || line.starts_with('#') { continue }
		fields := line.split(':')
		if fields.len != 7 { return error('invalid passwd entry') }
		if number(fields[2])! == uid {
			if fields[0] == '' || number(fields[3])! != gid { return error('desktop passwd identity differs') }
			users++
		}
	}
	mut groups := 0
	for line in group.split_into_lines() {
		if line == '' || line.starts_with('#') { continue }
		fields := line.split(':')
		if fields.len != 4 { return error('invalid group entry') }
		if number(fields[2])! == gid { groups++ }
	}
	if users != 1 || groups != 1 { return error('desktop Unix identity must resolve uniquely') }
}

fn desktop_identity() !DesktopIdentity {
	mut pid := os.getpid()
	mut seen := []int{}
	for _ in 0 .. 64 {
		if pid <= 0 || pid in seen { break }
		seen << pid
		current := identity(pid)!
		comm := os.read_file('/proc/' + pid.str() + '/comm')!.trim_space()
		os.write_file(result_root + '/identity/ancestor-' + pid.str() + '-stat.txt',
			os.read_file('/proc/' + pid.str() + '/stat')!)!
		if comm in ['vinix-desktop', 'vinix-desktop-g', 'vinix-desktop-gp', 'vinix-desktop-gpu'] {
			base := '/proc/' + pid.str()
			executable := os.readlink(base + '/exe')!
			if executable !in ['/usr/bin/vinix-desktop', '/usr/bin/vinix-desktop-gpu'] {
				return error('desktop compositor executable differs')
			}
			protected(executable, 0, false, .regular)!
			status := os.read_file(base + '/status')!
			os.write_file(result_root + '/identity/desktop-status.txt', status)!
			os.write_file(result_root + '/identity/desktop-cmdline', os.read_file(base + '/cmdline')!)!
			uid, gid := status_id(status, 'Uid')!, status_id(status, 'Gid')!
			passwd, group := os.read_file('/etc/passwd')!, os.read_file('/etc/group')!
			os.write_file(result_root + '/identity/passwd', passwd)!
			os.write_file(result_root + '/identity/group', group)!
			account_identity(passwd, group, uid, gid)!
			socket := window_path(uid)
			mut overrides := map[string]string{}
			for entry in os.read_file(base + '/environ')!.split('\x00') {
				for key in ['VINIX_WINDOW_SOCKET', 'VINIX_SESSION_RUNTIME'] {
					if entry.starts_with(key + '=') {
						if key in overrides { return error('duplicate desktop window override') }
						overrides[key] = entry[key.len + 1..]
					}
				}
			}
			os.write_file(result_root + '/identity/window-overrides.json', json2.encode(overrides) + '\n')!
			if (overrides['VINIX_WINDOW_SOCKET'] or { '' }) !in ['', socket]
				|| (overrides['VINIX_SESSION_RUNTIME'] or { '' }) != '' {
				return error('desktop uses a noncanonical window endpoint')
			}
			paths := window_identity(uid)!
			peer := window_peer(socket)!
			if peer.pid != pid || peer.uid != uid || peer.gid != gid || identity(pid)! != current {
				return error('window socket peer differs from GUI terminal compositor ancestor')
			}
			return DesktopIdentity{current, uid, gid, executable, hash(base + '/exe')!, socket, peer, paths}
		}
		pid = current.parent
	}
	return error('invoke from the real desktop GUI terminal; compositor ancestor absent')
}

fn controller_receipt(text string, desktop DesktopIdentity) ! {
	value := json2.decode[map[string]json2.Any](text)!
	mut keys := value.keys()
	keys.sort()
	if keys != ['checks', 'created_utc', 'desktop_gid', 'desktop_uid', 'helper_path',
		'helper_sha256', 'kind', 'scope', 'source_revision', 'window_socket'] {
		return error('controller receipt key set differs')
	}
	for key in ['kind', 'created_utc', 'source_revision', 'helper_path', 'helper_sha256',
		'window_socket', 'scope'] {
		field := value[key]!
		if field !is string { return error('controller receipt string field differs: ' + key) }
	}
	expected_checks := ['real-helper-window-ready', 'WSUI64-session-capability', 'SCM_RIGHTS-two-fds',
		'CLOEXEC', 'sealed-size-VSF1', 'read-only-input-FIFO', 'diagnostic-frame-published',
		'helper-lifetime-EOF-input-close', 'single-use-attachment']
	if value['kind']!.str() != 'vinix-account-ui-controller-v1'
		|| value['source_revision']!.str() != source_revision || value['created_utc']!.str() == ''
		|| value['created_utc']!.str().len > 128
		|| value['helper_path']!.str() != helper_path || value['helper_sha256']!.str() != helper_sha
		|| json2.encode(value['desktop_uid']!) != desktop.uid.str()
		|| json2.encode(value['desktop_gid']!) != desktop.gid.str()
		|| value['window_socket']!.str() != desktop.window_socket
		|| json2.decode[[]string](json2.encode(value['checks']!))! != expected_checks
		|| value['scope']!.str() != 'real desktop helper and root UI controller only; no Android Activity, Google account or sign-in' {
		return error('controller receipt identity/checks/scope differ')
	}
}

fn diagnostics(mut receipt Receipt) ! {
	build := bundle_root + '/guest-inputs.json'
	protected(build, 0, false, .regular)!
	pins := json2.decode[Pins](os.read_file(build)!)!
	expected := {controller_path: controller_sha, helper_path: helper_sha}
	if pins.kind != 'vinix-account-ui-guest-inputs-v1' || pins.source_revision != source_revision
		|| pins.inputs_sha256 != expected { return error('exact account UI guest input pins differ') }
	for path, pin in expected {
		protected(path, 0, false, .regular)!
		if hash(path)! != pin { return error('account UI executable hash differs: ' + path) }
	}
	receipt.build_sha256 = hash(build)!
	os.cp(build, result_root + '/guest-inputs.json')!
	os.mkdir(result_root + '/identity')!
	receipt.desktop = desktop_identity()!
	os.write_file(result_root + '/identity/before.json', json2.encode(receipt.desktop) + '\n')!
	receipt.controller = bounded([controller_path, receipt.desktop.uid.str(), receipt.desktop.gid.str(),
		helper_path, receipt.desktop.window_socket, result_root + '/controller.json', source_revision],
		result_root + '/controller.log', 20)!
	for path, pin in expected {
		protected(path, 0, false, .regular)!
		if hash(path)! != pin { return error('account UI executable changed: ' + path) }
	}
	if hash(build)! != receipt.build_sha256 { return error('guest input metadata changed') }
	base := '/proc/' + receipt.desktop.process.pid.str()
	after_status := os.read_file(base + '/status')!
	os.write_file(result_root + '/identity/after-status.txt', after_status)!
	after_paths := window_identity(receipt.desktop.uid)!
	os.write_file(result_root + '/identity/after-paths.json', json2.encode(after_paths) + '\n')!
	if identity(receipt.desktop.process.pid)! != receipt.desktop.process
		|| status_id(after_status, 'Uid')! != receipt.desktop.uid
		|| status_id(after_status, 'Gid')! != receipt.desktop.gid
		|| after_paths != receipt.desktop.paths
		|| window_peer(receipt.desktop.window_socket)! != receipt.desktop.peer
		|| hash(base + '/exe')! != receipt.desktop.executable_sha256 {
		return error('desktop process or window socket identity changed')
	}
	if receipt.controller.status != 'passed' { return error('controller did not pass with bounded clean exit') }
	controller_receipt(os.read_file(result_root + '/controller.json')!, receipt.desktop)!
	receipt.status = 'passed'
}

fn self_test() ! {
	root := os.join_path(os.temp_dir(), 'vinix-account-ui-guest-selftest-' + os.getpid().str())
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
	serial_path := root + '/framing.log'
	mut serial := os.open_file(serial_path, 'wx', 0o600)!
	begin := header(payload, 'BEGIN')
	chunk := prefix + 'CHUNK ' + sha256.sum(payload.bytes()).hex() + ' 0 ' +
		base64.encode(payload[..if payload.len < chunk_bytes { payload.len } else { chunk_bytes }].bytes()) + '\n'
	end := header(payload, 'END')
	chatter := 'Maps onUnbind without a terminating newline'
	mut expected_serial := ''
	for frame in [begin, chunk, end] {
		serial.write_string(chatter)!
		serial.flush()
		serial_write(serial.fd, frame)!
		expected_serial += chatter + '\n' + frame
	}
	for bad in ['', prefix + 'no newline', prefix + 'two\nlines\n',
		prefix + 'carriage\rreturn\n', 'foreign frame\n', prefix + 'x'.repeat(1024) + '\n'] {
		if _ := serial_write(serial.fd, bad) { return error('invalid serial frame accepted') }
	}
	serial.close()
	assert os.read_file(serial_path)! == expected_serial
	assert expected_serial.split_into_lines().filter(it.starts_with(prefix)).len == 3
	if _ := serial_write(-1, begin) { return error('failed serial write accepted') }
	assert !safe_relative('../escape') && !safe_relative('a//b') && safe_relative('a/b')
	assert number('0')! == 0 && number('1000')! == 1000 && number('4294967295')! == 0xffffffff
	for bad in ['', '00', '+1', '-1', '1x', '4294967296', '99999999999'] {
		if _ := number(bad) { return error('invalid Unix identity accepted') }
	}
	assert status_id('Uid:\t0\t0\t0\t0\nGid:\t1\t1\t1\t1\n', 'Uid')! == 0
	assert status_id('Uid:\t1000\t1000\t1000\t1000\n', 'Uid')! == 1000
	for bad in ['', 'Uid: 0 0 0\n', 'Uid: 0 0 1 0\n', 'Uid: 0 0 0 0\nUid: 0 0 0 0\n'] {
		if _ := status_id(bad, 'Uid') { return error('invalid process credentials accepted') }
	}
	assert window_path(0) == '/run/vinix-session.0/windows'
	assert window_path(1000) == '/run/user/1000/vinix-session.1000/windows'
	passwd := 'root:x:0:0:root:/root:/bin/sh\nuser:x:1000:100:User:/home/user:/bin/sh\n'
	group := 'root:x:0:\nusers:x:100:user\n'
	account_identity(passwd, group, 0, 0)!
	account_identity(passwd, group, 1000, 100)!
	for bad in [passwd + 'duplicate:x:1000:100:x:/x:/bin/sh\n', passwd.replace(':100:User:', ':101:User:'), 'invalid'] {
		if _ := account_identity(bad, group, 1000, 100) { return error('invalid passwd identity accepted') }
	}
	if _ := account_identity(passwd, group + 'duplicate:x:100:\n', 1000, 100) {
		return error('duplicate group identity accepted')
	}
	protected(root, u32(C.getuid()), true, .directory)!
	if _ := protected(root + '/font', u32(C.getuid()), true, .regular) {
		return error('symlink accepted as protected regular file')
	}
	os.chmod(root, 0o777)!
	if _ := protected(root, u32(C.getuid()), true, .directory) {
		return error('writable directory accepted as protected')
	}
	os.chmod(root, 0o700)!
	desktop := DesktopIdentity{ uid: 1000, gid: 100, window_socket: window_path(1000) }
	mut record := map[string]json2.Any{}
	record['kind'] = 'vinix-account-ui-controller-v1'
	record['created_utc'] = '2026-10-26 00:00:00'
	record['source_revision'] = source_revision
	record['helper_path'] = helper_path
	record['helper_sha256'] = helper_sha
	record['desktop_uid'] = desktop.uid
	record['desktop_gid'] = desktop.gid
	record['window_socket'] = desktop.window_socket
	record['checks'] = ['real-helper-window-ready', 'WSUI64-session-capability', 'SCM_RIGHTS-two-fds',
		'CLOEXEC', 'sealed-size-VSF1', 'read-only-input-FIFO', 'diagnostic-frame-published',
		'helper-lifetime-EOF-input-close', 'single-use-attachment'].map(json2.Any(it))
	record['scope'] = 'real desktop helper and root UI controller only; no Android Activity, Google account or sign-in'
	controller_receipt(json2.encode(record), desktop)!
	for key in record.keys() {
		mut bad := record.clone()
		bad[key] = if key == 'created_utc' { '' } else { 'wrong' }
		if _ := controller_receipt(json2.encode(bad), desktop) {
			return error('invalid controller receipt accepted: ' + key)
		}
	}
	record['extra'] = true
	if _ := controller_receipt(json2.encode(record), desktop) { return error('extra receipt key accepted') }
	record.delete('extra')
	record['created_utc'] = json2.null
	if _ := controller_receipt(json2.encode(record), desktop) { return error('null receipt timestamp accepted') }
	println('ACCOUNT-UI-GUEST SELF-TEST PASS deterministic-tree modes binary-content symlink framing chatter-boundary single-write-failure Unix-identity process-credentials protected-paths exact-controller-receipt')
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
		eprintln('usage: account-ui-guest [--self-test]')
		exit(2)
	}
	$if !linux {
		eprintln('account-ui-guest requires the Linux ABI guest')
		exit(2)
	}
	if C.getuid() != 0 || C.geteuid() != 0 || C.getgid() != 0 || C.getegid() != 0 {
		eprintln('account-ui-guest requires guest root')
		exit(2)
	}
	for path in ['/', '/opt', bundle_root, bundle_root + '/bin'] {
		protected(path, 0, false, .directory) or {
			eprintln(err.msg())
			exit(1)
		}
	}
	if os.exists(result_root + '.json') || os.is_link(result_root + '.json') {
		eprintln('refusing existing ' + result_root + '.json')
		exit(1)
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
	println('ACCOUNT-UI-GUEST exported status=' + receipt.status + ' sha256=' + sha256.sum(payload.bytes()).hex())
	if receipt.status != 'passed' { exit(1) }
}
