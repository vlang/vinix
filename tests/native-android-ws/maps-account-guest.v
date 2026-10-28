// SPDX-License-Identifier: GPL-2.0-or-later
// Opt-in real Maps/GMS deployment controller, invoked as root from a GUI terminal.
// Readiness is transport evidence only; this never claims Google authentication.
module main

import arena
import accounthandoff
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
	#include <sys/mount.h>
}

fn C.prctl(int, u64, u64, u64, u64) int
fn C.waitpid(int, &int, int) int
fn C.mount(&char, &char, &char, u64, voidptr) int
fn C.dup2(int, int) int

const bundle_root = '/opt/vinix-maps-account'
const result_root = bundle_root + '/results'
const runtime_root = '/opt/vinix-android-aarch64'
const broker_root = '/run/vinix-maps-account'
const controller_path = bundle_root + '/bin/maps-account-guest'
const app_host_path = '/usr/bin/vinix-android-calculator'
// The retained base image's native app host; it is a separate compositor child.
const app_host_pin = '6a48bc4174eccc330606629b99cd266989c80bde894e7ff7beed07f67b45c2c2'
const helper_path = runtime_root + '/usr/bin/vinix-android-account-ui'
const broker_path = runtime_root + '/usr/bin/native-account-broker'
const launcher_path = runtime_root + '/usr/bin/run-android'
const sqlite_path = runtime_root + '/usr/lib/libsqlite3.so.0'
const sqlite_alias = runtime_root + '/usr/lib/libsqlite3.so.3.53.4'
const sqlite_pin = '5a228127ca3ffa0c88bcae0aa5f7ab10e15b383dfb46822c573013105628bbaa'
const registry_path = bundle_root + '/identity.registry'
const maps_apk = bundle_root + '/apks/maps.apk'
const gms_apk = bundle_root + '/apks/gms.apk'
const service_class = 'com.google.android.gms.auth.account.authenticator.GoogleAccountAuthenticatorService'
const account_activity = 'com.google.android.gms.auth.uiflows.addaccount.AccountIntroActivity'
const prefix = 'VINIX-MAPS-ACCOUNT-RESULTS-1 '
const chunk_bytes = 512
const max_file = 16 * 1024 * 1024
const max_total = 48 * 1024 * 1024
const max_archive = 72 * 1024 * 1024

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
	path  string
	dev   u64
	inode u64
	uid   u32
	gid   u32
	mode  u32
	kind  string
}

struct DesktopIdentity {
	process           Identity
	uid               u32
	gid               u32
	executable        string
	executable_sha256 string
	window_socket     string
	peer              Peer
	paths             []PathIdentity
}

struct AppHostIdentity {
	process           Identity
	uid               u32
	gid               u32
	executable        string
	executable_sha256 string
	app_selector      string
}

struct MapsLaunch {
	kind             string = 'vinix-maps-account-launch-v1'
	process          Identity
	app_host         AppHostIdentity
	desktop          Identity
	trace_onboarding bool
	trace_tls        bool
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
	for name in names {
		// ART/app diagnostics may eventually contain account data. Retain those
		// private files in the guest; serial export carries their hashes only.
		if name in ['broker.log', 'maps.log'] { continue }
		snapshot(root, name, mut entries, mut total)!
	}
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
	return proc_identity(pid, text)
}

fn proc_identity(pid int, text string) !Identity {
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

fn cleanup_observation(scratch &arena.Arena, known map[int]Identity) !(map[int]Identity, int) {
	scratch.push()
	defer { scratch.pop() }
	mut observed := known.clone()
	discover(mut observed)!
	kill_owned(observed)
	$if linux {
		mut status := 0
		for C.waitpid(-1, &status, 1) > 0 {
		}
	}
	mut survivors := 0
	for pid, previous in observed {
		if pid == os.getpid() { continue }
		current := identity(pid) or { continue }
		if current.start == previous.start { survivors++ }
	}
	return observed, survivors
}

fn cleanup(mut owned map[int]Identity, mut scratch arena.Arena) !int {
	deadline := time.sys_mono_now() + 2 * time.second
	for {
		observed, survivors := cleanup_observation(&scratch, owned) or {
			message := err.msg().clone()
			scratch.reset()
			return error(message)
		}
		for _, item in observed { retain_polled_process(mut owned, item)! }
		scratch.reset()
		if survivors == 0 || time.sys_mono_now() >= deadline { return survivors }
		time.sleep(20 * time.millisecond)
	}
	return error('unreachable cleanup')
}

fn reap_broker(mut child os.Process) {
	deadline := time.sys_mono_now() + 2 * time.second
	for child.is_alive() {
		if time.sys_mono_now() >= deadline { return }
		time.sleep(20 * time.millisecond)
	}
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
	return if uid == 0 {
		'/run/vinix-session.0/windows'
	} else {
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
		if path.len == 0 || path.len >= address.sun_path.len {
			return error('window socket path limit')
		}
		unsafe { C.memcpy(&address.sun_path[0], path.str, uint(path.len)) }
		if C.connect(fd, voidptr(&address), u32(sizeof(C.sockaddr_un))) != 0 {
			return error('cannot connect immediately to live window server')
		}
		mut peer := Peer{}
		mut size := u32(sizeof(Peer))
		if C.getsockopt(fd, C.SOL_SOCKET, C.SO_PEERCRED, &peer, &size) != 0
			|| size != sizeof(Peer) || peer.pid <= 0 {
			return error('cannot authenticate window server')
		}
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
			if fields[0] == '' || number(fields[3])! != gid {
				return error('desktop passwd identity differs')
			}
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

fn check_app_host(host AppHostIdentity, launched Identity, desktop DesktopIdentity) ! {
	if host.process.pid <= 0 || host.process.start == '' || launched.pid <= 0
		|| launched.start == '' || launched.pid == host.process.pid
		|| host.process.pid == desktop.process.pid || launched.pid == desktop.process.pid
		|| launched.parent != host.process.pid || host.process.parent != desktop.process.pid
		|| host.uid != desktop.uid || host.gid != desktop.gid
		|| host.executable !in [app_host_path, '/usr/bin/vinix-desktop']
		|| host.executable_sha256 != app_host_pin
		|| host.app_selector != '--vinix-app=vinix-android-calculator' {
		return error('Maps must be launched by the selected native Android app host')
	}
}

fn app_host_path_target(kind os.FileType, owner u32, link string) !string {
	if owner != 0 { return error('native Android app host path owner differs') }
	if kind == .regular && link == '' { return app_host_path }
	if kind != .symbolic_link || link != 'vinix-desktop' {
		return error('native Android app host path shape differs')
	}
	return '/usr/bin/vinix-desktop'
}

fn app_host_target() !string {
	for path in ['/', '/usr', '/usr/bin'] { protected(path, 0, false, .directory)! }
	st := os.lstat(app_host_path)!
	link := if st.get_filetype() == .symbolic_link { os.readlink(app_host_path)! } else { '' }
	target := app_host_path_target(st.get_filetype(), st.uid, link)!
	protected(target, 0, false, .regular)!
	return target
}

fn app_host_selector(args []string) !string {
	if args.len < 3 || args[0] != app_host_path
		|| args[1] != '--vinix-app=vinix-android-calculator'
		|| args.count(it.starts_with('--vinix-app=')) != 1 {
		return error('native Android app host command differs')
	}
	return args[1]
}

fn app_host_identity(launched Identity, desktop DesktopIdentity) !AppHostIdentity {
	current := identity(launched.parent)!
	base := '/proc/' + current.pid.str()
	target := app_host_target()!
	executable := os.readlink(base + '/exe')!
	if executable !in [app_host_path, target] { return error('native Android app host executable differs') }
	status := os.read_file(base + '/status')!
	args := os.read_file(base + '/cmdline')!.split('\x00')
	host := AppHostIdentity{current, status_id(status, 'Uid')!, status_id(status, 'Gid')!,
		executable, hash(base + '/exe')!, app_host_selector(args)!}
	check_app_host(host, launched, desktop)!
	if identity(launched.pid)! != launched || identity(current.pid)! != current
		|| identity(desktop.process.pid)! != desktop.process || app_host_target()! != target {
		return error('native Android app host ancestry changed')
	}
	return host
}

fn check_fresh_surface(surface string, host Identity, exists bool, symlink bool) ! {
	if surface != '/tmp/vinix-android-' + host.pid.str() + '.surface' {
		return error('surface path differs from selected native Android app host')
	}
	if exists || symlink { return error('fresh native Android app surface required') }
}

struct BrowserPin {
	path   string
	sha256 string
}

struct Build {
	kind              string
	format            int
	runtime_root      string
	maps_uid          int
	gms_uid           int
	inputs_sha256     map[string]string
	browser_manifests map[string]BrowserPin
}

struct Session {
	kind             string = 'vinix-maps-account-session-v1'
	build_sha256     string
	controller       Identity
	broker           Identity
	desktop          DesktopIdentity
	trace_onboarding bool
	trace_tls        bool
}

struct StopRequest {
	kind       string = 'vinix-maps-account-stop-v1'
	controller Identity
	broker     Identity
}

struct AuthInitFailure {
	stage  i32
	code   i32
	detail i32
	loader i32
}

struct AuthInitDiagnostics {
mut:
	failures  []AuthInitFailure
	truncated bool
}

struct AuthPumpFailure {
	stage   i32
	status  i32
	pending i32
}

struct AuthPumpDiagnostics {
mut:
	failures  []AuthPumpFailure
	truncated bool
}

struct AccountHandoffDiagnostics {
mut:
	records   []accounthandoff.HandoffDiagnostic
	truncated bool
}

// Accept canonical decimal i32 values without an overflowing conversion.
fn auth_init_integer(text string) ?i32 {
	if text.len == 0 || text.len > 11 { return none }
	negative := text[0] == `-`
	start := if negative { 1 } else { 0 }
	if start == text.len || (text[start] == `0` && (negative || text.len - start != 1)) {
		return none
	}
	limit := if negative { i64(2147483648) } else { i64(2147483647) }
	mut value := i64(0)
	for index := start; index < text.len; index++ {
		if text[index] < `0` || text[index] > `9` { return none }
		digit := i64(text[index] - `0`)
		if value > (limit - digit) / 10 { return none }
		value = value * 10 + digit
	}
	return i32(if negative { -value } else { value })
}

fn auth_init_line(line string) ?AuthInitFailure {
	if line.len > 128 || !line.ends_with('\n')
		|| !line.starts_with('ANDROID-AUTH-INIT-FAIL stage=') { return none }
	fields := line[..line.len - 1].split(' ')
	if fields.len != 5 || fields[0] != 'ANDROID-AUTH-INIT-FAIL'
		|| !fields[1].starts_with('stage=') || !fields[2].starts_with('code=')
		|| !fields[3].starts_with('detail=') || !fields[4].starts_with('loader=') {
		return none
	}
	stage := auth_init_integer(fields[1][6..]) or { return none }
	code := auth_init_integer(fields[2][5..]) or { return none }
	detail := auth_init_integer(fields[3][7..]) or { return none }
	loader := auth_init_integer(fields[4][7..]) or { return none }
	if stage < 1 || stage > 8 || loader < 0 || loader > 5
		|| (stage != 5 && stage != 6 && loader != 0) {
		return none
	}
	if stage == 4 {
		if detail < 1 || detail > 3 { return none }
	} else if stage == 6 {
		if detail < 1 || detail > 22 { return none }
	} else if detail != 0 {
		return none
	}
	return AuthInitFailure{ stage: stage, code: code, detail: detail, loader: loader }
}

// Only bounded complete lines become public numeric evidence. Unfinished,
// overlong and unrecognized private output is never copied into the receipt.
fn auth_init_diagnostics(output string) AuthInitDiagnostics {
	mut result := AuthInitDiagnostics{}
	mut start := 0
	for index := 0; index < output.len; index++ {
		if output[index] != `\n` { continue }
		if index + 1 - start <= 128 {
			if failure := auth_init_line(output[start..index + 1]) {
				if result.failures.len < 32 {
					result.failures << failure
				} else {
					result.truncated = true
					return result
				}
			}
		}
		start = index + 1
	}
	return result
}

fn browser_init_line(line string) ?AuthInitFailure {
	if line.len > 128 || !line.ends_with('\n')
		|| !line.starts_with('ANDROID-BROWSER-INIT-FAIL stage=') { return none }
	fields := line[..line.len - 1].split(' ')
	if fields.len != 5 || fields[0] != 'ANDROID-BROWSER-INIT-FAIL'
		|| !fields[1].starts_with('stage=') || !fields[2].starts_with('code=')
		|| !fields[3].starts_with('detail=') || !fields[4].starts_with('loader=') {
		return none
	}
	stage := auth_init_integer(fields[1][6..]) or { return none }
	code := auth_init_integer(fields[2][5..]) or { return none }
	detail := auth_init_integer(fields[3][7..]) or { return none }
	loader := auth_init_integer(fields[4][7..]) or { return none }
	if stage < 1 || stage > 7 || loader < 0 || loader > 5
		|| (stage != 5 && stage != 6 && loader != 0) {
		return none
	}
	if stage == 6 {
		if detail < 1 || detail > 4 { return none }
	} else if detail != 0 {
		return none
	}
	return AuthInitFailure{ stage: stage, code: code, detail: detail, loader: loader }
}

// Browser diagnostics use the same public numeric bounds as account diagnostics.
fn browser_init_diagnostics(output string) AuthInitDiagnostics {
	mut result := AuthInitDiagnostics{}
	mut start := 0
	for index := 0; index < output.len; index++ {
		if output[index] != `\n` { continue }
		if index + 1 - start <= 128 {
			if failure := browser_init_line(output[start..index + 1]) {
				if result.failures.len < 32 {
					result.failures << failure
				} else {
					result.truncated = true
					return result
				}
			}
		}
		start = index + 1
	}
	return result
}

fn auth_pump_line(line string) ?AuthPumpFailure {
	if line.len > 128 || !line.ends_with('\n')
		|| !line.starts_with('ANDROID-AUTH-PUMP-FAIL stage=') { return none }
	body := line[..line.len - 1]
	defer { unsafe { body.free() } }
	fields := body.split(' ')
	// The pinned compiler generates a typed free that owns the split strings.
	defer { unsafe { fields.free() } }
	if fields.len != 4 || fields[0] != 'ANDROID-AUTH-PUMP-FAIL'
		|| !fields[1].starts_with('stage=') || !fields[2].starts_with('status=')
		|| !fields[3].starts_with('pending=') { return none }
	stage_text := fields[1][6..]
	status_text := fields[2][7..]
	pending_text := fields[3][8..]
	defer { unsafe { stage_text.free(); status_text.free(); pending_text.free() } }
	stage := auth_init_integer(stage_text) or { return none }
	status := auth_init_integer(status_text) or { return none }
	pending := auth_init_integer(pending_text) or { return none }
	if stage < 1 || stage > 4 || pending < 0 || pending > 1 { return none }
	return AuthPumpFailure{ stage: stage, status: status, pending: pending }
}

// Inspect the byte range before allocating a line. Most broker output is
// private text and must not allocate parser work under the no-GC controller.
fn diagnostic_prefix_at(output string, start int, end int, prefix string) bool {
	if end - start < prefix.len { return false }
	for index, value in prefix {
		if output[start + index] != value { return false }
	}
	return true
}

fn auth_pump_diagnostics(output string) AuthPumpDiagnostics {
	mut result := AuthPumpDiagnostics{}
	mut start := 0
	for index := 0; index < output.len; index++ {
		if output[index] != `\n` { continue }
		if index + 1 - start <= 128
			&& diagnostic_prefix_at(output, start, index, 'ANDROID-AUTH-PUMP-FAIL stage=') {
			line := output[start..index + 1]
			if failure := auth_pump_line(line) {
				if result.failures.len < 32 {
					result.failures << failure
				} else {
					result.truncated = true
					unsafe { line.free() }
					return result
				}
			}
			unsafe { line.free() }
		}
		start = index + 1
	}
	return result
}

// Broker and controller share one strict numeric handoff parser. Only complete
// bounded lines reach it; raw broker output never enters the public receipt.
fn account_handoff_diagnostics(output string) AccountHandoffDiagnostics {
	mut result := AccountHandoffDiagnostics{}
	mut start := 0
	for index := 0; index < output.len; index++ {
		if output[index] != `\n` { continue }
		if index + 1 - start <= 128
			&& diagnostic_prefix_at(output, start, index, 'ANDROID-ACCOUNT-HANDOFF stage=') {
			line := output[start..index]
			if record := accounthandoff.parse_handoff_diagnostic(line) {
				if result.records.len < 32 {
					result.records << record
				} else {
					result.truncated = true
					unsafe { line.free() }
					return result
				}
			}
			unsafe { line.free() }
		}
		start = index + 1
	}
	return result
}

struct Receipt {
	scope            string = 'Real Maps and Google Play Services transport diagnostics. No credentials supplied; broker readiness does not establish Google authentication.'
	started_utc      string
	trace_onboarding bool
	trace_tls        bool
mut:
	finished_utc      string
	status            string = 'failed'
	error             string
	build_sha256      string
	runtime_mount     string
	desktop           DesktopIdentity
	broker            Identity
	service_ready     bool
	broker_exit       int = -1
	cleanup_survivors int
	auth_init         AuthInitDiagnostics
	browser_init      AuthInitDiagnostics
	auth_pump         AuthPumpDiagnostics
	account_handoff   AccountHandoffDiagnostics
}

struct DatabaseUpdate {
	path   string
	before string
	after  string
}

struct InputHardening {
	path   string
	sha256 string
	before PathIdentity
	after  PathIdentity
}

struct SqliteObject {
	identity PathIdentity
	nlink    u64
	size     u64
	sha256   string
}

struct SqliteDealias {
	kind   string = 'vinix-maps-account-sqlite-dealias-v1'
	before []SqliteObject
	after  []SqliteObject
}

fn sqlite_shape(objects []SqliteObject) ! {
	if objects.len != 2 { return error('SQLite alias group must contain exactly two selected paths') }
	for index, path in [sqlite_path, sqlite_alias] {
		item := objects[index]
		if item.identity.path != path || item.identity.kind != 'regular'
			|| item.identity.uid != 0 || item.identity.gid != 0
			|| item.identity.mode & 0o7777 != 0o755 || item.size == 0 || item.size > 32 * 1024 * 1024 {
			return error('SQLite alias group metadata differs: ' + path)
		}
	}
	if objects[0].size != objects[1].size { return error('SQLite alias group sizes differ') }
}

fn sqlite_before(objects []SqliteObject) ! {
	sqlite_shape(objects)!
	for item in objects {
		if item.nlink != 2 || item.sha256 != sqlite_pin {
			return error('SQLite original alias count or digest differs')
		}
	}
	if objects[0].identity.dev != objects[1].identity.dev
		|| objects[0].identity.inode != objects[1].identity.inode {
		return error('SQLite selected aliases do not share the original inode')
	}
}

fn sqlite_after(before []SqliteObject, after []SqliteObject) ! {
	sqlite_before(before)!
	sqlite_shape(after)!
	for item in after {
		if item.nlink != 1 || item.sha256 != sqlite_pin {
			return error('SQLite replacement or preserved alias differs')
		}
	}
	if after[0].identity.dev != before[0].identity.dev
		|| after[0].identity.inode == before[0].identity.inode
		|| after[1].identity != before[1].identity || after[0].size != before[0].size {
		return error('SQLite replacement did not preserve the original alias')
	}
}

fn sqlite_snapshot() ![]SqliteObject {
	protected('/', 0, false, .directory)!
	mut parent := ''
	for part in os.dir(sqlite_path)[1..].split('/') {
		parent += '/' + part
		protected(parent, 0, false, .directory)!
	}
	mut objects := []SqliteObject{}
	for path in [sqlite_path, sqlite_alias] {
		selected := protected(path, 0, false, .regular)!
		st := os.lstat(path)!
		objects << SqliteObject{ identity: selected, nlink: st.nlink, size: st.size }
	}
	// Bound and validate both objects before reading either selected inode.
	sqlite_shape(objects)!
	for index, item in objects {
		objects[index] = SqliteObject{ ...item, sha256: hash(item.identity.path)! }
		if protected(item.identity.path, 0, false, .regular)! != item.identity
			|| os.lstat(item.identity.path)!.nlink != item.nlink
			|| os.lstat(item.identity.path)!.size != item.size {
			return error('SQLite alias group changed during hashing')
		}
	}
	return objects
}

fn exclusive_regular(path string, mode int) !int {
	fd := unsafe { C.open(&char(path.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, mode) }
	if fd < 0 { return error('cannot exclusively create regular file: ' + path) }
	return fd
}

fn copy_stream(source int, target int) ! {
	mut bytes := []u8{len: 65536}
	mut total := 0
	for {
		n := C.read(source, bytes.data, uint(bytes.len))
		if n < 0 && C.errno == C.EINTR { continue }
		if n < 0 { return error('cannot read SQLite copy source') }
		if n == 0 { break }
		total += int(n)
		if total > 32 * 1024 * 1024 { return error('SQLite copy exceeds size bound') }
		mut offset := 0
		for offset < n {
			written := unsafe { C.write(target, &bytes[offset], uint(n - offset)) }
			if written < 0 && C.errno == C.EINTR { continue }
			if written <= 0 { return error('incomplete SQLite copy') }
			offset += int(written)
		}
	}
}

fn dealias_sqlite() ! {
	// This is the one audited baseline hardlink group. Do not admit arbitrary
	// aliases or weaken the single-link invariant used for immutable inputs.
	before := sqlite_snapshot()!
	sqlite_before(before)!
	temporary := sqlite_path + '.maps-account-fresh'
	if os.exists(temporary) || os.is_link(temporary) {
		return error('SQLite replacement temporary already exists')
	}
	source := unsafe { C.open(&char(sqlite_path.str), C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC) }
	if source < 0 { return error('cannot open selected SQLite source') }
	defer { C.close(source) }
	mut selected := C.stat{}
	if C.fstat(source, &selected) != 0 || u64(selected.st_dev) != before[0].identity.dev
		|| u64(selected.st_ino) != before[0].identity.inode || selected.st_nlink != 2 {
		return error('SQLite source changed before copy')
	}
	target := exclusive_regular(temporary, 0o755)!
	mut published := false
	defer {
		C.close(target)
		if !published { os.rm(temporary) or {} }
	}
	copy_stream(source, target)!
	os.chmod(temporary, 0o755)!
	deployment_input(temporary)!
	if os.lstat(temporary)!.gid != 0 || hash(temporary)! != sqlite_pin
		|| os.lstat(temporary)!.size != before[0].size {
		return error('SQLite fresh replacement differs')
	}
	if sqlite_snapshot()! != before { return error('SQLite original group changed before replacement') }
	os.rename(temporary, sqlite_path)!
	published = true
	after := sqlite_snapshot()!
	sqlite_after(before, after)!
	os.write_file(result_root + '/sqlite-dealias.json', json2.encode(SqliteDealias{ before: before, after: after }) + '\n')!
	os.chmod(result_root + '/sqlite-dealias.json', 0o600)!
}

fn canonical_absolute(path string) bool {
	return path.starts_with('/') && safe_relative(path[1..])
}

fn valid_pin(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `a` && it <= `f`) || (it >= `0` && it <= `9`))
}

// Root is the trusted administrator. Existing runtime inodes retain their
// owner-write mode when the kernel's tar implementation overwrites them.
fn deployment_input(path string) !PathIdentity {
	if !canonical_absolute(path) { return error('noncanonical selected input: ' + path) }
	protected('/', 0, false, .directory)!
	mut current := ''
	parts := path[1..].split('/')
	for part in parts[..parts.len - 1] {
		current += '/' + part
		protected(current, 0, false, .directory)!
	}
	selected := protected(path, 0, false, .regular)!
	st := os.lstat(path)!
	if st.nlink != 1 {
		return error('selected input must be single-linked: ' + path)
	}
	return selected
}

fn protected_input(path string) ! {
	selected := deployment_input(path)!
	if selected.mode & 0o222 != 0 {
		return error('selected input must be immutable: ' + path)
	}
}

fn harden_inputs(pins map[string]string) ! {
	// Check the complete selected set, including build.json, before any chmod.
	mut before := map[string]PathIdentity{}
	for path, pin in pins {
		before[path] = deployment_input(path)!
		if hash(path)! != pin { return error('preflight input digest differs: ' + path) }
	}
	mut changes := []InputHardening{}
	for path, pin in pins {
		if deployment_input(path)! != before[path]! || hash(path)! != pin {
			return error('deployment changed after complete hardening preflight: ' + path)
		}
		os.chmod(path, int(before[path]!.mode & 0o777 & ~u32(0o222)))!
		protected_input(path)!
		if hash(path)! != pin { return error('hardened input digest differs: ' + path) }
		changes << InputHardening{path, pin, before[path]!, deployment_input(path)!}
	}
	os.write_file(result_root + '/input-hardening.json', json2.encode(changes) + '\n')!
	os.chmod(result_root + '/input-hardening.json', 0o600)!
}

fn registry_matches(text string, pins map[string]string) ! {
	if !text.ends_with('\n') || text.contains_any('\r\x00') {
		return error('registry framing differs')
	}
	lines := text[..text.len - 1].split('\n')
	if lines.len != 3 || lines[0] != 'vinix-android-account-authority-v1' {
		return error('expected exactly Maps and GMS authority entries')
	}
	mut seen := map[string]bool{}
	for line in lines[1..] {
		fields := line.split('\t')
		if fields.len != 7 || !valid_pin(fields[5]) || fields[0] in seen {
			return error('registry entry differs')
		}
		seen[fields[0]] = true
		if fields[0] == 'com.google.android.apps.maps' {
			if fields[1..5] != ['10012', '10012', maps_apk, pins[maps_apk]!] || fields[6] != '-' {
				return error('Maps authority differs')
			}
		} else if fields[0] == 'com.google.android.gms' {
			if fields[1..5] != ['10013', '10013', gms_apk, pins[gms_apk]!]
				|| fields[6] != service_class + '@android.accounts.AccountAuthenticator@com.google' {
				return error('GMS authenticator authority differs')
			}
		} else {
			return error('unselected package in registry')
		}
	}
	if seen.len != 2 { return error('registry package set differs') }
}

fn required_deployment_inputs(pins map[string]string) ! {
	for path in [controller_path, '/usr/bin/run-android-calculator', maps_apk, gms_apk, registry_path,
		launcher_path, broker_path, helper_path,
		runtime_root + '/usr/lib/art/libvinix-android-native.so',
		runtime_root + '/usr/lib/libvinix-android-account.so',
		runtime_root + '/usr/lib/libvinix-android-browser.so',
		runtime_root + '/usr/lib/libsqlite3.so.0',
		runtime_root + '/usr/lib/java/dex/android_translation_layer/api-impl.jar',
		runtime_root + '/usr/lib/java/dex/android_translation_layer/classes.dex'] {
		if path !in pins {
			return error('required deployment input absent: ' + path)
		}
	}
}

fn build_inputs(harden bool) !Build {
	build_path := bundle_root + '/build.json'
	deployment_input(build_path)!
	if os.lstat(build_path)!.size > 8 * 1024 * 1024 {
		return error('deployment receipt size limit')
	}
	build_pin := hash(build_path)!
	build := json2.decode[Build](os.read_file(build_path)!)!
	if build.kind != 'vinix-maps-account-deployment-v1' || build.format != 1
		|| build.runtime_root != runtime_root || build.maps_uid != 10012 || build.gms_uid != 10013
		|| build.inputs_sha256.len < 14 || build.inputs_sha256.len > 20032 {
		return error('deployment receipt identity differs')
	}
	required_deployment_inputs(build.inputs_sha256)!
	for path, pin in build.inputs_sha256 {
		if !valid_pin(pin) { return error('invalid deployment digest') }
		deployment_input(path)!
		if hash(path)! != pin { return error('deployment input digest differs: ' + path) }
	}
	if build.inputs_sha256[controller_path]! != build.inputs_sha256['/usr/bin/run-android-calculator']! {
		return error('desktop slot is not this selected controller')
	}
	mut principals := build.browser_manifests.keys()
	principals.sort()
	if principals != ['10012', '10013'] {
		return error('both exclusive browser principals required')
	}
	for principal, selected in build.browser_manifests {
		if !valid_pin(selected.sha256) || build.inputs_sha256[selected.path] or { '' } != selected.sha256 {
			return error('browser manifest is not a sealed deployment input')
		}
		line := 'exclusive-principal\t' + principal + '\t' + principal + '\t/var/lib/vinix/apps/' + principal + '/data'
		if os.lstat(selected.path)!.size > 4 * 1024 * 1024 {
			return error('browser manifest size limit')
		}
		text := os.read_file(selected.path)!
		if text.split_into_lines().count(it == line) != 1 {
			return error('browser manifest principal differs')
		}
	}
	registry_matches(os.read_file(registry_path)!, build.inputs_sha256)!
	mut pins := build.inputs_sha256.clone()
	if build_path in pins { return error('deployment receipt must not self-reference its digest') }
	pins[build_path] = build_pin
	if harden {
		harden_inputs(pins)!
	} else {
		for path, pin in pins {
			protected_input(path)!
			if hash(path)! != pin { return error('hardened deployment changed: ' + path) }
		}
	}
	return build
}

fn approved_runtime_mount() !string {
	mut found := ''
	for line in os.read_file('/proc/self/mounts')!.split_into_lines() {
		fields := line.fields()
		if fields.len < 4 || fields[1] != runtime_root { continue }
		if found != '' { return error('duplicate runtime attachment') }
		options := fields[3].split(',')
		for required in ['ro', 'nosuid', 'nodev', 'wxallowed'] {
			if required !in options { return error('runtime attachment lacks ' + required) }
		}
		if 'noexec' in options { return error('runtime attachment forbids execution') }
		found = line
	}
	if found == '' { return error('dedicated runtime attachment absent') }
	return found
}

fn approve_runtime() !string {
	$if linux {
		// Only the selected immutable executable attachment gets the existing
		// kernel W^X exception. Browser policy remains independent.
		for path in ['/lib/ld-musl-aarch64.so.1', '/usr/bin/vinix-android-native'] {
			resolved := os.real_path(runtime_root + path)
			if !resolved.starts_with(runtime_root + '/') || !os.is_file(resolved) {
				return error('runtime executable escapes selected attachment')
			}
		}
		if C.mount(runtime_root.str, runtime_root.str, unsafe { nil }, u64(C.MS_BIND), unsafe { nil }) != 0 {
			return error('cannot attach selected runtime')
		}
		flags := u64(C.MS_BIND | C.MS_REMOUNT | C.MS_RDONLY | C.MS_NOSUID | C.MS_NODEV | C.MS_STRICTATIME)
		if C.mount(c'none', runtime_root.str, unsafe { nil }, flags, c'wxallowed') != 0 {
			return error('cannot apply selected runtime attachment policy')
		}
		return approved_runtime_mount()
	} $else {
		return error('runtime attachment requires Linux ABI')
	}
}

fn prepare_database(path string, group bool) !DatabaseUpdate {
	protected(path, 0, false, .regular)!
	before := os.read_file(path)!
	return prepare_database_text(path, before, group)
}

fn prepare_database_text(path string, before string, group bool) !DatabaseUpdate {
	mut names := map[string]bool{}
	mut ids := map[u32]bool{}
	for line in before.split_into_lines() {
		if line == '' || line.starts_with('#') { continue }
		fields := line.split(':')
		if fields.len != (if group { 4 } else { 7 }) || fields[0] == '' {
			return error('malformed identity database')
		}
		id := number(fields[2])!
		if id in [u32(10012), u32(10013)] || fields[0] in ['vinix-maps-account', 'vinix-gms-account'] {
			return error('selected Maps/GMS Unix identity is already assigned')
		}
		if !group && number(fields[3])! in [u32(10012), u32(10013)] {
			return error('selected Maps/GMS group already used by another account')
		}
		if fields[0] in names || id in ids {
			return error('duplicate identity database name or ID')
		}
		names[fields[0]], ids[id] = true, true
	}
	mut after := before + if before != '' && !before.ends_with('\n') { '\n' } else { '' }
	for id in [10012, 10013] {
		name := if id == 10012 { 'vinix-maps-account' } else { 'vinix-gms-account' }
		after += if group {
			'${name}:x:${id}:\n'
		} else {
			'${name}:x:${id}:${id}:Maps account diagnostic:/var/lib/vinix/apps/${id}/home:/bin/sh\n'
		}
	}
	return DatabaseUpdate{path, before, after}
}

fn selected_processes() ![]Identity {
	mut result := []Identity{}
	names := os.ls('/proc')!
	if names.len > 65536 { return error('proc inventory limit') }
	for name in names {
		if name == '' || !name.bytes().all(it >= `0` && it <= `9`) { continue }
		status := os.read_file('/proc/' + name + '/status') or { continue }
		mut selected := false
		for label in ['Uid:', 'Gid:'] {
			for line in status.split_into_lines().filter(it.starts_with(label)) {
				for value in line.fields()[1..] {
					if number(value) or { continue } in [u32(10012), u32(10013)] { selected = true }
				}
			}
		}
		if selected { result << identity(name.int()) or { continue } }
	}
	return result
}

fn make_root_directory(path string, mode u32) ! {
	if os.exists(path) || os.is_link(path) {
		return error('refuse to reuse selected directory: ' + path)
	}
	os.mkdir(path)!
	os.chmod(path, int(mode))!
	protected(path, 0, false, .directory)!
}

fn provision() ! {
	// Complete both database preflights before either write. This fixture is
	// deliberately single-use on a fresh guest image.
	updates := [prepare_database('/etc/passwd', false)!, prepare_database('/etc/group', true)!]
	if selected_processes()!.len != 0 {
		return error('selected app identity already has a process')
	}
	for path in ['/var', '/var/lib', '/var/lib/vinix', '/var/lib/vinix/apps', '/run'] {
		if !os.exists(path) {
			os.mkdir(path)!
			os.chmod(path, 0o755)!
		}
		protected(path, 0, false, .directory)!
	}
	for id in [10012, 10013] {
		base := '/var/lib/vinix/apps/' + id.str()
		if os.exists(base) || os.is_link(base) {
			return error('selected app private root already exists')
		}
	}
	if os.exists(broker_root) || os.is_link(broker_root) {
		return error('broker root already exists')
	}
	for update in updates {
		if os.read_file(update.path)! != update.before {
			return error('identity database changed after preflight')
		}
	}
	for update in updates {
		os.write_file(update.path, update.after)!
		if os.read_file(update.path)! != update.after {
			return error('identity database append differs')
		}
		os.write_file(result_root + '/identity/' + os.base(update.path) + '-before', update.before)!
		os.write_file(result_root + '/identity/' + os.base(update.path) + '-after', update.after)!
	}
	for id in [10012, 10013] {
		base := '/var/lib/vinix/apps/' + id.str()
		make_root_directory(base, 0o755)!
		for leaf in ['data', 'home'] {
			path := base + '/' + leaf
			os.mkdir(path)!
			os.chown(path, id, id)!
			os.chmod(path, 0o700)!
		}
	}
	make_root_directory(broker_root, 0o755)!
}

fn select_environment(build Build, principal string) ! {
	selected := build.browser_manifests[principal]!
	// Ambient configuration cannot select account or browser authority.
	for key in ['VINIX_ANDROID_WEBVIEW_FD', 'VINIX_ANDROID_AUTHENTICATOR_FD',
		'VINIX_ANDROID_SERVICE_UI_FD', 'VINIX_ANDROID_SERVICE_ROOT_FD',
		'WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS', 'LD_PRELOAD', 'LD_LIBRARY_PATH'] {
		os.unsetenv(key)
	}
	for key, value in {
		'VINIX_ANDROID_ROOT':                    runtime_root
		'VINIX_ANDROID_ACCOUNT_REGISTRY':        registry_path
		'VINIX_ANDROID_ACCOUNT_SOCKET':          broker_root + '/accounts.sock'
		'VINIX_ANDROID_UID':                     principal
		'VINIX_ANDROID_GID':                     principal
		'ANDROID_APP_DATA_DIR':                  '/var/lib/vinix/apps/' + principal + '/data'
		'VINIX_ANDROID_HOME':                    '/var/lib/vinix/apps/' + principal + '/home'
		'VINIX_ANDROID_BROWSER_MANIFEST':        selected.path
		'VINIX_ANDROID_BROWSER_MANIFEST_SHA256': selected.sha256
	} {
		os.setenv(key, value, true)
	}
}

// The desktop builds a closed native-client environment, so terminal exports
// never reach its Maps child. Only the protected live broker session selects
// these diagnostics; unrelated ambient values cannot enable them.
fn select_maps_diagnostics(session Session) {
	for key in ['VINIX_ANDROID_TRACE_TREE', 'VINIX_ANDROID_TRACE_THREADS'] {
		if session.trace_onboarding {
			os.setenv(key, '1', true)
		} else {
			os.unsetenv(key)
		}
	}
	if session.trace_tls {
		os.setenv('VINIX_ANDROID_TRACE_TLS', '1', true)
	} else {
		os.unsetenv('VINIX_ANDROID_TRACE_TLS')
	}
}

struct DiagnosticSelection {
mut:
	trace_onboarding bool
	trace_tls        bool
}

fn broker_diagnostics(args []string) !DiagnosticSelection {
	mut broker := false
	mut selected := DiagnosticSelection{}
	for argument in args {
		match argument {
			'--broker' {
				if broker { return error('duplicate broker option') }
				broker = true
			}
			'--trace-onboarding' {
				if selected.trace_onboarding { return error('duplicate onboarding trace option') }
				selected.trace_onboarding = true
			}
			'--trace-tls' {
				if selected.trace_tls { return error('duplicate TLS trace option') }
				selected.trace_tls = true
			}
			else { return error('unsupported broker option: ' + argument) }
		}
	}
	return selected
}

fn private_result_root() ! {
	protected(bundle_root, 0, false, .directory)!
	make_root_directory(result_root, 0o700)!
	os.mkdir(result_root + '/identity')!
	os.chmod(result_root + '/identity', 0o700)!
}

fn save_receipt(receipt Receipt) ! {
	os.write_file(result_root + '/receipt.json', json2.encode(receipt) + '\n')!
	os.chmod(result_root + '/receipt.json', 0o600)!
}

// Publish a complete receipt so the controller never observes partial JSON.
fn publish_fresh(path string, text string, mode u32) ! {
	if os.exists(path) || os.is_link(path) { return error('selected receipt already exists') }
	pending := path + '.pending'
	mut file := os.open_file(pending, 'wx', int(mode))!
	file.write_string(text) or {
		file.close()
		os.rm(pending) or {}
		return err
	}
	file.close()
	os.rename(pending, path)!
}

fn live_session() !Session {
	protected_input(broker_root + '/session.json')!
	if os.lstat(broker_root + '/session.json')!.size > 1024 * 1024 {
		return error('session receipt size limit')
	}
	session := json2.decode[Session](os.read_file(broker_root + '/session.json')!)!
	if session.kind != 'vinix-maps-account-session-v1' || session.build_sha256 != hash(bundle_root + '/build.json')!
		|| identity(session.controller.pid)! != session.controller || identity(session.broker.pid)! != session.broker {
		return error('selected broker session is not live')
	}
	for pid in [session.controller.pid, session.broker.pid] {
		status := os.read_file('/proc/' + pid.str() + '/status')!
		if status_id(status, 'Uid')! != 0 || status_id(status, 'Gid')! != 0 {
			return error('broker session lost root authority')
		}
	}
	return session
}

fn request_stop() ! {
	protected(result_root, 0, true, .directory)!
	protected_input(bundle_root + '/build.json')!
	session := live_session()!
	publish_fresh(result_root + '/stop-request.json',
		json2.encode(StopRequest{ controller: session.controller, broker: session.broker }) + '\n', 0o600)!
	println('MAPS-ACCOUNT-STOP-REQUESTED controller=' + session.controller.pid.str())
}

fn matching_stop(request StopRequest, controller Identity, broker Identity) bool {
	return request.kind == 'vinix-maps-account-stop-v1'
		&& request.controller == controller && request.broker == broker
}

fn stop_requested(controller Identity, broker Identity) !bool {
	path := result_root + '/stop-request.json'
	if !os.exists(path) && !os.is_link(path) { return false }
	protected(path, 0, true, .regular)!
	if os.lstat(path)!.nlink != 1 || os.lstat(path)!.size > 4096 {
		return error('stop request shape differs')
	}
	request := json2.decode[StopRequest](os.read_file(path)!)!
	if !matching_stop(request, controller, broker) {
		return error('stop request session differs')
	}
	return true
}

fn session_stop_observation(scratch &arena.Arena, controller Identity, broker Identity) !bool {
	scratch.push()
	defer { scratch.pop() }
	if os.exists(result_root + '/maps.log') && os.lstat(result_root + '/maps.log')!.size > max_file {
		return error('Maps diagnostic log limit')
	}
	return stop_requested(controller, broker)
}

fn check_session_stop(mut scratch arena.Arena, controller Identity, broker Identity) !bool {
	stopped := session_stop_observation(&scratch, controller, broker) or {
		message := err.msg().clone()
		scratch.reset()
		return error(message)
	}
	scratch.reset()
	return stopped
}

fn check_maps_launch(launched MapsLaunch, desktop DesktopIdentity) ! {
	if launched.kind != 'vinix-maps-account-launch-v1' || launched.desktop != desktop.process {
		return error('Maps launch receipt compositor differs')
	}
	check_app_host(launched.app_host, launched.process, desktop)!
}

fn retain_receipted_process(mut owned map[int]Identity, current Identity, expected Identity) {
	if expected.pid > 0 && expected.start != '' && current.pid == expected.pid
		&& current.start == expected.start {
		owned[current.pid] = current
	}
}

// Only this function writes process identities retained between polls. Its
// callers have popped the scratch arena, so both map growth and start ticks
// belong to the session rather than to the next arena reset.
fn retain_polled_process(mut owned map[int]Identity, item Identity) ! {
	if previous := owned[item.pid] {
		if previous == item { return }
		replacement := Identity{pid: item.pid, parent: item.parent, start: item.start.clone()}
		unsafe { previous.start.free() }
		owned[item.pid] = replacement
	} else {
		if owned.len >= 4096 { return error('retained process limit') }
		owned[item.pid] = Identity{pid: item.pid, parent: item.parent, start: item.start.clone()}
	}
}

struct ProcessObservation {
	processes map[int]Identity
	failure string
}

fn collect_polled_processes(scratch &arena.Arena, known map[int]Identity,
	desktop DesktopIdentity) ProcessObservation {
	scratch.push()
	defer { scratch.pop() }
	mut observed := known.clone()
	// Finish the independent inventories before exposing the first failure.
	// Cleanup still needs descendants and selected principals if a launch
	// receipt failed validation, just as it did before scratch reclamation.
	mut failure := ''
	track_maps_launch(mut observed, desktop) or { failure = err.msg() }
	discover(mut observed) or { if failure == '' { failure = err.msg() } }
	selected := selected_processes() or {
		if failure == '' { failure = err.msg() }
		[]Identity{}
	}
	for item in selected {
		if item.pid !in observed && observed.len >= 4096 {
			return ProcessObservation{observed, 'retained process limit'}
		}
		observed[item.pid] = item
	}
	return ProcessObservation{processes: observed, failure: failure}
}

fn refresh_polled_processes(mut scratch arena.Arena, mut owned map[int]Identity,
	desktop DesktopIdentity) ! {
	observed := collect_polled_processes(&scratch, owned, desktop)
	defer { scratch.reset() }
	adopt_polled_processes(mut owned, observed)!
}

fn adopt_polled_processes(mut owned map[int]Identity, observed ProcessObservation) ! {
	// Preserve already attested processes even when later validation fails,
	// so the cleanup path still owns a native host whose Maps child has exited.
	for _, item in observed.processes { retain_polled_process(mut owned, item)! }
	if observed.failure != '' { return error(observed.failure.clone()) }
}

fn warm_poll_decoders() ! {
	// json2 lazily stores typed field metadata in process-wide caches. Populate
	// every nested poll type before any decode can allocate in scratch.
	json2.decode[MapsLaunch](json2.encode(MapsLaunch{}))!
	json2.decode[StopRequest](json2.encode(StopRequest{}))!
}

fn broker_service_ready(output []u8) bool {
	ready_prefix := 'ANDROID-ACCOUNT-BROKER-SERVICE package=com.google.android.gms pid='
	mut start := 0
	for index := 0; index <= output.len; index++ {
		if index < output.len && output[index] != `\n` { continue }
		if index - start >= ready_prefix.len {
			mut matches := true
			for offset := 0; offset < ready_prefix.len; offset++ {
				if output[start + offset] != ready_prefix[offset] { matches = false; break }
			}
			if matches { return true }
		}
		start = index + 1
	}
	return false
}

fn append_broker_output(mut child os.Process, mut log os.File, mut output []u8) ! {
	block := child.stdout_read()
	defer { unsafe { block.free() } }
	if block == '' { return }
	if output.len + block.len > max_file { return error('broker diagnostic log limit') }
	log.write_string(block)!
	append_output_block(mut output, block)!
}

fn append_output_block(mut output []u8, block string) ! {
	if output.cap < max_file || output.len + block.len > max_file {
		return error('broker diagnostic buffer limit')
	}
	bytes := block.bytes()
	defer { unsafe { bytes.free() } }
	output << bytes
}

fn track_maps_launch(mut owned map[int]Identity, desktop DesktopIdentity) ! {
	path := result_root + '/maps-launch.json'
	if !os.exists(path) && !os.is_link(path) { return }
	protected(path, 0, true, .regular)!
	if os.lstat(path)!.nlink != 1 || os.lstat(path)!.size > 4096 {
		return error('Maps process receipt shape differs')
	}
	launched := json2.decode[MapsLaunch](os.read_file(path)!)!
	check_maps_launch(launched, desktop)!
	first := launched.app_host.process.pid !in owned
	current := identity(launched.process.pid) or { Identity{} }
	host := identity(launched.app_host.process.pid) or { Identity{} }
	// The root-owned receipt attests both start ticks. Keep each live process
	// independently: the Maps child can exit before the first broker poll,
	// while its native app host remains alive displaying the failed window.
	retain_receipted_process(mut owned, current, launched.process)
	retain_receipted_process(mut owned, host, launched.app_host.process)
	if current.pid == 0 { return }
	if current.start != launched.process.start { return error('Maps launch PID was reused') }
	if current != launched.process || host != launched.app_host.process
		|| identity(desktop.process.pid)! != desktop.process {
		return error('Maps launch app host ancestry changed')
	}
	// Hash the 18 MiB host once at acceptance, not on every 50 ms broker poll.
	if first && app_host_identity(current, desktop)! != launched.app_host {
		return error('Maps launch app host executable or principal changed')
	}
}

fn broker_session(mut receipt Receipt) ! {
	dealias_sqlite()!
	build := build_inputs(true)!
	receipt.build_sha256 = hash(bundle_root + '/build.json')!
	os.cp(bundle_root + '/build.json', result_root + '/build.json')!
	receipt.desktop = desktop_identity()!
	os.write_file(result_root + '/identity/desktop.json', json2.encode(receipt.desktop) + '\n')!
	provision()!
	receipt.runtime_mount = approve_runtime()!
	enable_subreaper()!
	select_environment(build, '10013')!
	warm_poll_decoders()!
	controller := identity(os.getpid())!
	argv := [registry_path, runtime_root, gms_apk, '10013', '10013', service_class,
		'android.accounts.AccountAuthenticator', broker_root, '/var/lib/vinix/apps/10013/data',
		'/var/lib/vinix/apps/10013/home', 'com.google.android.gms', account_activity, '--ui',
		receipt.desktop.uid.str(), receipt.desktop.gid.str(), helper_path,
		receipt.desktop.window_socket]
	os.write_file(result_root + '/broker-argv.json', json2.encode(argv) + '\n')!
	mut log := os.open_file(result_root + '/broker.log', 'wx', 0o600)!
	defer { log.close() }
	mut child := os.new_process(broker_path)
	child.use_pgroup = true
	child.set_args(argv)
	child.set_stdin_path('/dev/null')
	child.set_redirect_stdio_merged()
	child.run()
	if child.pid <= 0 {
		child.close()
		return error('could not start selected broker')
	}
	defer { child.close() }
	receipt.broker = identity(child.pid) or {
		child.signal_pgkill()
		reap_broker(mut child)
		return error('broker identity unavailable after spawn: ' + err.msg())
	}
	mut scratch := arena.new()
	defer { scratch.free() }
	mut owned := map[int]Identity{}
	retain_polled_process(mut owned, controller)!
	retain_polled_process(mut owned, receipt.broker)!
	defer {
		for _, item in owned { unsafe { item.start.free() } }
		unsafe { owned.free() }
	}
	defer {
		refresh_polled_processes(mut scratch, mut owned, receipt.desktop) or {}
		kill_owned(owned)
		reap_broker(mut child)
		receipt.broker_exit = child.code
		receipt.cleanup_survivors = cleanup(mut owned, mut scratch) or { -1 }
		os.rm(broker_root + '/session.json') or {}
	}
	deadline := time.sys_mono_now() + 15 * time.minute
	startup := time.sys_mono_now() + 45 * time.second
	// Reserve once: string concatenation otherwise retains all preceding log
	// prefixes under -gc none. No append may grow or replace this buffer.
	mut output := []u8{cap: max_file}
	defer { unsafe { output.free() } }
	defer {
		text := output.bytestr()
		receipt.auth_init = auth_init_diagnostics(text)
		receipt.browser_init = browser_init_diagnostics(text)
		receipt.auth_pump = auth_pump_diagnostics(text)
		receipt.account_handoff = account_handoff_diagnostics(text)
		unsafe { text.free() }
	}
	for {
		append_broker_output(mut child, mut log, mut output)!
		refresh_polled_processes(mut scratch, mut owned, receipt.desktop)!
		if !receipt.service_ready && broker_service_ready(output) {
			window_identity(receipt.desktop.uid)!
			if window_peer(receipt.desktop.window_socket)! != receipt.desktop.peer
				|| identity(receipt.desktop.process.pid)! != receipt.desktop.process {
				return error('desktop identity changed before service readiness')
			}
			session := Session{
				build_sha256:     receipt.build_sha256
				controller:       identity(os.getpid())!
				broker:           receipt.broker
				desktop:          receipt.desktop
				trace_onboarding: receipt.trace_onboarding
				trace_tls:        receipt.trace_tls
			}
			publish_fresh(broker_root + '/session.json', json2.encode(session) + '\n', 0o444)!
			receipt.service_ready = true
			receipt.status = 'ready-awaiting-user-account-interaction'
			save_receipt(receipt)!
			println('MAPS-ACCOUNT-READY broker=' + child.pid.str() + ' Maps=10012 GMS=10013; open Maps from the desktop Android icon, then its account menu')
		}
		if !child.is_alive() { return error('GMS broker exited; inspect private broker.log') }
		if !receipt.service_ready && time.sys_mono_now() >= startup {
			return error('real GMS authenticator did not attach before deadline')
		}
		if check_session_stop(mut scratch, controller, receipt.broker)! {
			receipt.status = 'user-stopped-no-authentication-claim'
			return
		}
		if time.sys_mono_now() >= deadline {
			receipt.status = 'bounded-session-ended-no-authentication-claim'
			return
		}
		time.sleep(50 * time.millisecond)
	}
}

fn launch_maps() ! {
	build := build_inputs(false)!
	session := live_session()!
	protected(result_root, 0, true, .directory)!
	desktop := desktop_identity()!
	if desktop != session.desktop {
		return error('Maps compositor differs from broker UI compositor')
	}
	approved_runtime_mount()!
	host := app_host_identity(identity(os.getpid())!, desktop)!
	surface := os.getenv('VINIX_SURFACE_PATH')
	check_fresh_surface(surface, host.process, os.exists(surface), os.is_link(surface))!
	// Inspect the inherited descriptor, not its /proc symlink.
	mut pipe := C.stat{}
	if C.fstat(0, &pipe) != 0 || u32(pipe.st_mode) & u32(C.S_IFMT) != u32(C.S_IFIFO) {
		return error('compositor input pipe required')
	}
	for item in selected_processes()! {
		if status_id(os.read_file('/proc/' + item.pid.str() + '/status')!, 'Uid')! == 10012 {
			return error('Maps identity already running')
		}
	}
	select_environment(build, '10012')!
	select_maps_diagnostics(session)
	mut log := os.open_file(result_root + '/maps.log', 'wx', 0o600)!
	if C.dup2(log.fd, 1) != 1 || C.dup2(log.fd, 2) != 2 {
		return error('cannot retain private Maps diagnostics')
	}
	log.close()
	launched := MapsLaunch{
		process: identity(os.getpid())!, app_host: host, desktop: desktop.process
		trace_onboarding: session.trace_onboarding
		trace_tls:        session.trace_tls
	}
	check_maps_launch(launched, desktop)!
	if app_host_identity(launched.process, desktop)! != host {
		return error('Maps app host changed before launch')
	}
	publish_fresh(result_root + '/maps-launch.json', json2.encode(launched) + '\n', 0o600)!
	println('MAPS-ACCOUNT-LAUNCH uid=10012 gid=10012 package=com.google.android.apps.maps')
	if session.trace_onboarding {
		println('MAPS-ACCOUNT-ONBOARDING-TRACE tree=1 threads=1 private-log=maps.log')
	}
	if session.trace_tls { println('MAPS-ACCOUNT-TLS-TRACE private-log=maps.log') }
	os.execvp(launcher_path, [maps_apk])!
}

fn onboarding_trace_self_test() ! {
	for arguments in [ []string{}, ['--broker'] ] {
		if broker_diagnostics(arguments)! != DiagnosticSelection{} { return error('default broker enabled diagnostics') }
	}
	for arguments in [['--trace-onboarding'], ['--broker', '--trace-onboarding'],
		['--trace-onboarding', '--broker']] {
		selected := broker_diagnostics(arguments)!
		if !selected.trace_onboarding || selected.trace_tls { return error('broker onboarding trace opt-in differs') }
	}
	for arguments in [['--trace-tls'], ['--broker', '--trace-tls'], ['--trace-tls', '--broker']] {
		selected := broker_diagnostics(arguments)!
		if !selected.trace_tls || selected.trace_onboarding { return error('broker TLS trace opt-in differs') }
	}
	for arguments in [['--trace-tls', '--trace-onboarding'], ['--broker', '--trace-onboarding', '--trace-tls'],
		['--trace-tls', '--broker', '--trace-onboarding']] {
		selected := broker_diagnostics(arguments)!
		if !selected.trace_tls || !selected.trace_onboarding { return error('independent diagnostics selections lost') }
	}
	for arguments in [['--broker', '--broker'], ['--trace-onboarding', '--trace-onboarding'],
		['--trace-tls', '--trace-tls'], ['--launch', '--trace-onboarding'], ['--launch', '--trace-tls'],
		['--trace-onboarding=1'], ['--trace-tls=1'], ['--trace-TLS'], ['']] {
		if _ := broker_diagnostics(arguments) { return error('invalid trace invocation accepted') }
	}
	keys := ['VINIX_ANDROID_TRACE_TREE', 'VINIX_ANDROID_TRACE_THREADS', 'VINIX_ANDROID_TRACE_TLS']
	mut previous := map[string]string{}
	for key in keys {
		if value := os.getenv_opt(key) { previous[key] = value }
	}
	defer {
		for key in keys {
			if value := previous[key] { os.setenv(key, value, true) } else { os.unsetenv(key) }
		}
	}
	legacy := json2.decode[Session]('{"kind":"vinix-maps-account-session-v1"}')!
	if legacy.trace_onboarding || legacy.trace_tls { return error('legacy session enabled diagnostics') }
	legacy_launch := json2.decode[MapsLaunch]('{}')!
	legacy_receipt := json2.decode[Receipt]('{}')!
	if legacy_launch.trace_tls || legacy_receipt.trace_tls { return error('legacy receipt enabled TLS traces') }
	for selection in [DiagnosticSelection{}, DiagnosticSelection{ trace_onboarding: true },
		DiagnosticSelection{ trace_tls: true }, DiagnosticSelection{ trace_onboarding: true, trace_tls: true }] {
		for key in keys { os.setenv(key, 'ambient-must-not-select-diagnostics', true) }
		session := json2.decode[Session](json2.encode(Session{
			trace_onboarding: selection.trace_onboarding, trace_tls: selection.trace_tls
		}))!
		select_maps_diagnostics(session)
		for key in keys {
			enabled := if key == 'VINIX_ANDROID_TRACE_TLS' { selection.trace_tls } else { selection.trace_onboarding }
			if enabled {
				if os.getenv(key) != '1' { return error('session trace selection did not reach Maps environment') }
			} else if _ := os.getenv_opt(key) {
				return error('ambient Maps trace survived disabled session')
			}
		}
		launch := json2.decode[MapsLaunch](json2.encode(MapsLaunch{
			trace_onboarding: session.trace_onboarding, trace_tls: session.trace_tls
		}))!
		if launch.trace_onboarding != selection.trace_onboarding || launch.trace_tls != selection.trace_tls {
			return error('Maps trace receipt lost session selection')
		}
	}
	root := os.join_path(os.temp_dir(), 'vinix-maps-trace-' + os.getpid().str() + '-' + time.sys_mono_now().str())
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	os.chmod(root, 0o700)!
	for name in ['broker.log', 'maps.log'] { os.write_file(root + '/' + name, 'private-onboarding-and-tls-sentinel')! }
	os.write_file(root + '/receipt.json', json2.encode(Receipt{ trace_onboarding: true, trace_tls: true }))!
	retained := json2.decode[Archive](archive(root)!)!
	if retained.entries.len != 1 || retained.entries[0].path != 'receipt.json'
		|| !json2.decode[Receipt](base64.decode_str(retained.entries[0].data))!.trace_onboarding
		|| !json2.decode[Receipt](base64.decode_str(retained.entries[0].data))!.trace_tls {
		return error('diagnostics escaped private logs or lost public opt-in receipt')
	}
}

fn sqlite_self_test() ! {
	before := [
		SqliteObject{ identity: PathIdentity{path: sqlite_path, dev: 1, inode: 2, mode: 0o100755, kind: 'regular'}, nlink: 2, size: 1234, sha256: sqlite_pin },
		SqliteObject{ identity: PathIdentity{path: sqlite_alias, dev: 1, inode: 2, mode: 0o100755, kind: 'regular'}, nlink: 2, size: 1234, sha256: sqlite_pin },
	]
	sqlite_before(before)!
	if _ := sqlite_before(before[..1]) { return error('incomplete SQLite group accepted') }
	for case in 0 .. 11 {
		mut invalid := before.clone()
		match case {
			0 { invalid[0] = SqliteObject{ ...invalid[0], nlink: 1 } }
			1 { invalid[1] = SqliteObject{ ...invalid[1], nlink: 3 } }
			2 { invalid[0] = SqliteObject{ ...invalid[0], sha256: 'a'.repeat(64) } }
			3 { invalid[1] = SqliteObject{ ...invalid[1], size: 0 } }
			4 { invalid[0] = SqliteObject{ ...invalid[0], size: 32 * 1024 * 1024 + 1 } }
			5 { invalid[0] = SqliteObject{ ...invalid[0], identity: PathIdentity{ ...invalid[0].identity, path: sqlite_alias } } }
			6 { invalid[0] = SqliteObject{ ...invalid[0], identity: PathIdentity{ ...invalid[0].identity, uid: 10012 } } }
			7 { invalid[1] = SqliteObject{ ...invalid[1], identity: PathIdentity{ ...invalid[1].identity, gid: 10013 } } }
			8 { invalid[0] = SqliteObject{ ...invalid[0], identity: PathIdentity{ ...invalid[0].identity, mode: 0o100775 } } }
			9 { invalid[1] = SqliteObject{ ...invalid[1], identity: PathIdentity{ ...invalid[1].identity, inode: 9 } } }
			else { invalid[1] = SqliteObject{ ...invalid[1], identity: PathIdentity{ ...invalid[1].identity, kind: 'symbolic_link' } } }
		}
		if _ := sqlite_before(invalid) { return error('changed SQLite group accepted: ' + case.str()) }
	}
	after := [
		SqliteObject{ ...before[0], nlink: 1, identity: PathIdentity{ ...before[0].identity, inode: 3 } },
		SqliteObject{ ...before[1], nlink: 1 },
	]
	sqlite_after(before, after)!
	for case in 0 .. 4 {
		mut invalid := after.clone()
		match case {
			0 { invalid[0] = SqliteObject{ ...invalid[0], nlink: 2 } }
			1 { invalid[0] = SqliteObject{ ...invalid[0], identity: before[0].identity } }
			2 { invalid[1] = SqliteObject{ ...invalid[1], identity: PathIdentity{ ...invalid[1].identity, inode: 4 } } }
			else { invalid[0] = SqliteObject{ ...invalid[0], sha256: 'b'.repeat(64) } }
		}
		if _ := sqlite_after(before, invalid) { return error('changed SQLite replacement accepted') }
	}
	directory := os.join_path(os.temp_dir(), 'vinix-maps-sqlite-selftest-' + os.getpid().str() + '-' + time.sys_mono_now().str())
	os.mkdir(directory, mode: 0o700)!
	defer { os.rmdir_all(directory) or {} }
	original := directory + '/original'
	alias := directory + '/alias'
	temporary := directory + '/fresh'
	content := 'copy-stream-boundary-test\n'.repeat(4097)
	os.write_file(original, content)!
	os.link(original, alias)!
	original_inode := os.lstat(original)!.inode
	source := unsafe { C.open(&char(original.str), C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC) }
	if source < 0 { return error('self-test source open failed') }
	defer { C.close(source) }
	target := exclusive_regular(temporary, 0o600)!
	copy_stream(source, target) or { C.close(target); return err }
	C.close(target)
	if _ := exclusive_regular(temporary, 0o600) { return error('exclusive SQLite create replaced an existing file') }
	os.symlink(alias, temporary + '-link')!
	if _ := exclusive_regular(temporary + '-link', 0o600) { return error('exclusive SQLite create followed a symlink') }
	if os.read_file(temporary)! != content { return error('bounded fd stream copy differs') }
	os.rename(temporary, original)!
	if os.lstat(original)!.nlink != 1 || os.lstat(alias)!.nlink != 1
		|| os.lstat(alias)!.inode != original_inode || os.lstat(original)!.inode == original_inode
		|| os.read_file(original)! != content || os.read_file(alias)! != content {
		return error('atomic replacement did not preserve hardlink alias')
	}
}

fn protected_directory_self_test() ! {
	root := os.join_path(os.temp_dir(), 'vinix-maps-protected-' + os.getpid().str() + '-' + time.sys_mono_now().str())
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	os.chmod(root, 0o700)!
	owner := u32(C.geteuid())
	protected(root, owner, true, .directory)!
	alias := root + '/run-alias'
	os.symlink(root, alias)!
	if _ := protected(alias, owner, false, .directory) {
		return error('protected directory accepted a symlink alias')
	}
	os.chmod(root, 0o777)!
	if _ := protected(root, owner, false, .directory) {
		return error('protected directory accepted a writable parent')
	}
	os.chmod(root, 0o700)!
}

fn auth_init_self_test() ! {
	for text, expected in {'0': i32(0), '2147483647': i32(2147483647),
		'-2147483648': i32(-2147483648), '-1': i32(-1)} {
		if auth_init_integer(text) or { return error('canonical auth integer rejected') } != expected {
			return error('auth integer changed value')
		}
	}
	for text in ['', '-', '+0', '+1', '-0', '00', '01', '-01', ' 1', '1 ', '1\t',
		'2147483648', '-2147483649', '99999999999999999999999', '1.0', '1\x00'] {
		if _ := auth_init_integer(text) { return error('noncanonical auth integer accepted') }
	}
	for stage in 1 .. 9 {
		detail := if stage in [4, 6] { 1 } else { 0 }
		line := 'ANDROID-AUTH-INIT-FAIL stage=' + stage.str() + ' code=0 detail=' + detail.str() + ' loader=0\n'
		failure := auth_init_line(line) or { return error('valid auth stage rejected') }
		if failure != AuthInitFailure{ stage: i32(stage), detail: i32(detail) } {
			return error('auth stage changed fields')
		}
	}
	for line in [
		'ANDROID-AUTH-INIT-FAIL stage=4 code=-2147483648 detail=3 loader=0\n',
		'ANDROID-AUTH-INIT-FAIL stage=5 code=2147483647 detail=0 loader=5\n',
		'ANDROID-AUTH-INIT-FAIL stage=6 code=-1 detail=22 loader=5\n',
	] {
		if _ := auth_init_line(line) {} else { return error('valid auth range endpoint rejected') }
	}
	valid := 'ANDROID-AUTH-INIT-FAIL stage=6 code=0 detail=22 loader=3\n'
	for bad in [valid.trim_right('\n'), 'prefix ' + valid, '\n' + valid, valid + 'suffix',
		valid.replace('\n', '\r\n'), valid.replace(' code=', '  code='),
		valid.replace(' code=', '\tcode='), valid.replace('stage=6', 'stage=0'),
		valid.replace('stage=6', 'stage=9'), valid.replace('stage=6', 'stage=06'),
		valid.replace('stage=6', 'stage=-6'), valid.replace('code=0', 'code=+0'),
		valid.replace('code=0', 'code=-0'), valid.replace('code=0', 'code=2147483648'),
		valid.replace('code=0', 'code=-2147483649'), valid.replace('detail=22', 'detail=0'),
		valid.replace('detail=22', 'detail=23'), valid.replace('detail=22', 'detail=-1'),
		valid.replace('detail=22', 'detail=022'), valid.replace('loader=3', 'loader=6'),
		valid.replace('loader=3', 'loader=-1'), valid.replace('loader=3', 'loader=03'),
		valid.replace('code=0 ', ''), valid.replace('code=0', 'stage=0'),
		valid.replace('loader=3\n', 'loader=3 email=private@example.invalid\n'),
		valid.replace('loader=3\n', 'loader=3\x00\n'),
		'ANDROID-AUTH-INIT-FAIL stage=4 code=0 detail=0 loader=0\n',
		'ANDROID-AUTH-INIT-FAIL stage=4 code=0 detail=4 loader=0\n',
		'ANDROID-AUTH-INIT-FAIL stage=5 code=0 detail=1 loader=0\n',
		'ANDROID-AUTH-INIT-FAIL stage=1 code=0 detail=0 loader=1\n',
		valid.trim_right('\n') + 'x'.repeat(128) + '\n',
	] {
		if _ := auth_init_line(bad) { return error('malformed/private auth line accepted') }
	}
	if auth_init_diagnostics(valid.trim_right('\n')).failures.len != 0 {
		return error('unterminated auth output accepted')
	}
	private := 'email=private@example.invalid token=private-secret\n'
	mixed := auth_init_diagnostics(private + 'x'.repeat(129) + '\n' + valid + valid.trim_right('\n'))
	if mixed.failures.len != 1 || mixed.truncated || mixed.failures[0].detail != 22 {
		return error('auth scan did not recover from private/overlong lines')
	}
	public := json2.encode(Receipt{ auth_init: mixed })
	if public.contains('private@example.invalid') || public.contains('private-secret')
		|| public.contains('ANDROID-AUTH-INIT-FAIL') {
		return error('raw private auth output entered the receipt')
	}
	mut many := ''
	for code in 0 .. 32 {
		many += 'ANDROID-AUTH-INIT-FAIL stage=1 code=' + code.str() + ' detail=0 loader=0\n'
	}
	full := auth_init_diagnostics(many + private)
	if full.failures.len != 32 || full.truncated || full.failures[0].code != 0
		|| full.failures[31].code != 31 {
		return error('auth cardinality/order differs at the bound')
	}
	over := auth_init_diagnostics(many + valid + private)
	if !over.truncated || over.failures != full.failures {
		return error('auth truncation did not preserve the first 32 complete records')
	}
}

fn browser_init_self_test() ! {
	for stage in 1 .. 8 {
		for detail in 0 .. 6 {
			for loader in 0 .. 7 {
				line := 'ANDROID-BROWSER-INIT-FAIL stage=' + stage.str() + ' code=0 detail=' + detail.str() + ' loader=' + loader.str() + '\n'
				valid := (if stage == 6 { detail >= 1 && detail <= 4 } else { detail == 0 })
					&& loader <= 5 && (stage in [5, 6] || loader == 0)
				if failure := browser_init_line(line) {
					if !valid || failure != AuthInitFailure{ stage: i32(stage), detail: i32(detail), loader: i32(loader) } {
						return error('browser stage/detail/loader combination accepted incorrectly')
					}
				} else if valid {
					return error('valid browser stage/detail/loader combination rejected')
				}
			}
		}
	}
	for code in [i32(-2147483648), i32(-1), i32(0), i32(2147483647)] {
		failure := browser_init_line('ANDROID-BROWSER-INIT-FAIL stage=7 code=' + code.str() + ' detail=0 loader=0\n') or {
			return error('canonical browser code endpoint rejected')
		}
		if failure != AuthInitFailure{ stage: 7, code: code } {
			return error('browser code changed value')
		}
	}
	valid := 'ANDROID-BROWSER-INIT-FAIL stage=6 code=0 detail=4 loader=3\n'
	for bad in [valid.trim_right('\n'), 'prefix ' + valid, '\n' + valid, valid + 'suffix',
		valid.replace('\n', '\r\n'), valid.replace(' code=', '  code='),
		valid.replace(' code=', '\tcode='), valid.replace('stage=6', 'stage=0'),
		valid.replace('stage=6', 'stage=8'), valid.replace('stage=6', 'stage=06'),
		valid.replace('stage=6', 'stage=-6'), valid.replace('code=0', 'code='),
		valid.replace('code=0', 'code=+0'), valid.replace('code=0', 'code=-0'),
		valid.replace('code=0', 'code=00'), valid.replace('code=0', 'code=1.0'),
		valid.replace('code=0', 'code=2147483648'), valid.replace('code=0', 'code=-2147483649'),
		valid.replace('detail=4', 'detail=0'), valid.replace('detail=4', 'detail=5'),
		valid.replace('detail=4', 'detail=-1'), valid.replace('detail=4', 'detail=04'),
		valid.replace('loader=3', 'loader=6'), valid.replace('loader=3', 'loader=-1'),
		valid.replace('loader=3', 'loader=03'), valid.replace('code=0 ', ''),
		valid.replace('code=0', 'stage=0'), valid.replace('detail=4 loader=3', 'loader=3 detail=4'),
		valid.replace('loader=3\n', 'loader=3 email=private@example.invalid\n'),
		valid.replace('loader=3\n', 'loader=3\x00\n'),
		valid.replace('ANDROID-BROWSER-INIT-FAIL', 'ANDROID-AUTH-INIT-FAIL'),
		valid.trim_right('\n') + 'x'.repeat(128) + '\n',
	] {
		if _ := browser_init_line(bad) { return error('malformed/private browser line accepted') }
	}
	if browser_init_diagnostics(valid.trim_right('\n')).failures.len != 0 {
		return error('unterminated browser output accepted')
	}
	private := 'email=private@example.invalid token=private-secret\n'
	auth := 'ANDROID-AUTH-INIT-FAIL stage=6 code=0 detail=4 loader=3\n'
	mixed := browser_init_diagnostics(private + 'x'.repeat(129) + '\n' + auth + valid + valid.trim_right('\n'))
	if mixed.failures.len != 1 || mixed.truncated || mixed.failures[0] != AuthInitFailure{ stage: 6, detail: 4, loader: 3 } {
		return error('browser scan did not recover from private/overlong/auth lines')
	}
	public := json2.encode(Receipt{ browser_init: mixed })
	if public.contains('private@example.invalid') || public.contains('private-secret')
		|| public.contains('ANDROID-BROWSER-INIT-FAIL') || public.contains('ANDROID-AUTH-INIT-FAIL') {
		return error('raw private browser output entered the receipt')
	}
	mut many := ''
	for code in 0 .. 32 {
		many += 'ANDROID-BROWSER-INIT-FAIL stage=1 code=' + code.str() + ' detail=0 loader=0\n'
	}
	full := browser_init_diagnostics(many + private + auth + valid.trim_right('\n'))
	if full.failures.len != 32 || full.truncated || full.failures[0].code != 0
		|| full.failures[31].code != 31 {
		return error('browser cardinality/order differs at the bound')
	}
	over := browser_init_diagnostics(many + valid + private)
	if !over.truncated || over.failures != full.failures {
		return error('browser truncation did not preserve the first 32 complete records')
	}
}

fn auth_pump_self_test() ! {
	for stage in 0 .. 6 {
		for pending in -1 .. 3 {
			for status in [i32(-2147483648), i32(-1), i32(0), i32(1), i32(3), i32(2147483647)] {
				line := 'ANDROID-AUTH-PUMP-FAIL stage=' + stage.str() + ' status=' + status.str() + ' pending=' + pending.str() + '\n'
				valid := stage >= 1 && stage <= 4 && pending >= 0 && pending <= 1
				if failure := auth_pump_line(line) {
					if !valid || failure != AuthPumpFailure{ stage: i32(stage), status: status, pending: i32(pending) } {
						return error('pump stage/status/pending combination accepted incorrectly')
					}
				} else if valid {
					return error('valid pump stage/status/pending combination rejected')
				}
			}
		}
	}
	valid := 'ANDROID-AUTH-PUMP-FAIL stage=4 status=-1 pending=1\n'
	for bad in [valid.trim_right('\n'), 'prefix ' + valid, '\n' + valid, valid + 'suffix',
		valid.replace('\n', '\r\n'), valid.replace(' status=', '  status='),
		valid.replace(' status=', '\tstatus='), valid.replace('stage=4', 'stage=04'),
		valid.replace('stage=4', 'stage=-4'), valid.replace('stage=4', 'stage=+4'),
		valid.replace('status=-1', 'status='), valid.replace('status=-1', 'status=+1'),
		valid.replace('status=-1', 'status=-0'), valid.replace('status=-1', 'status=00'),
		valid.replace('status=-1', 'status=-01'), valid.replace('status=-1', 'status=1.0'),
		valid.replace('status=-1', 'status=2147483648'), valid.replace('status=-1', 'status=-2147483649'),
		valid.replace('pending=1', 'pending=01'), valid.replace('pending=1', 'pending=+1'),
		valid.replace('pending=1', 'pending=-0'), valid.replace('status=-1 ', ''),
		valid.replace('status=-1', 'stage=-1'), valid.replace('status=-1 pending=1', 'pending=1 status=-1'),
		valid.replace('pending=1\n', 'pending=1 email=private@example.invalid\n'),
		valid.replace('pending=1\n', 'pending=1\x00\n'),
		valid.replace('ANDROID-AUTH-PUMP-FAIL', 'ANDROID-AUTH-INIT-FAIL'),
		valid.trim_right('\n') + 'x'.repeat(128) + '\n',
	] {
		if _ := auth_pump_line(bad) { return error('malformed/private pump line accepted') }
	}
	if auth_pump_diagnostics(valid.trim_right('\n')).failures.len != 0 {
		return error('unterminated pump output accepted')
	}
	private := 'email=private@example.invalid token=private-secret\n'
	init := 'ANDROID-AUTH-INIT-FAIL stage=1 code=0 detail=0 loader=0\n'
	mixed := auth_pump_diagnostics(private + 'x'.repeat(129) + '\n' + init + valid + valid.trim_right('\n'))
	if mixed.failures != [AuthPumpFailure{ stage: 4, status: -1, pending: 1 }] || mixed.truncated {
		return error('pump scan did not recover from private/overlong/init lines')
	}
	public := json2.encode(Receipt{ auth_pump: mixed })
	if public.contains('private@example.invalid') || public.contains('private-secret')
		|| public.contains('ANDROID-AUTH-PUMP-FAIL') || public.contains('ANDROID-AUTH-INIT-FAIL') {
		return error('raw private pump output entered the receipt')
	}
	mut many := ''
	for status in 0 .. 32 {
		many += 'ANDROID-AUTH-PUMP-FAIL stage=1 status=' + status.str() + ' pending=0\n'
	}
	full := auth_pump_diagnostics(many + private + init + valid.trim_right('\n'))
	if full.failures.len != 32 || full.truncated || full.failures[0].status != 0
		|| full.failures[31].status != 31 {
		return error('pump cardinality/order differs at the bound')
	}
	over := auth_pump_diagnostics(many + valid + private)
	if !over.truncated || over.failures != full.failures {
		return error('pump truncation did not preserve the first 32 complete records')
	}
}

fn account_handoff_self_test() ! {
	valid := 'ANDROID-ACCOUNT-HANDOFF stage=9 operation=2 event=2 code=-1\n'
	expected := accounthandoff.HandoffDiagnostic{ stage: 9, operation: 2, event: 2, code: -1 }
	for stage in 1 .. 14 {
		for operation in 2 .. 5 {
			line := 'ANDROID-ACCOUNT-HANDOFF stage=' + stage.str() + ' operation=' + operation.str() + ' event=' + (if stage == 9 { '1' } else { '0' }) + ' code=0\n'
			result := account_handoff_diagnostics(line)
			if operation == 3 && stage !in [1, 9] {
				if result.records.len != 0 || result.truncated {
					return error('redemption transport accepted an original-operation milestone')
				}
				continue
			}
			if result.truncated || result.records.len != 1 || result.records[0].stage != stage
				|| result.records[0].operation != operation || result.records[0].code != 0
				|| result.records[0].event != (if stage == 9 { 1 } else { 0 }) {
				return error('valid handoff milestone lost or changed')
			}
		}
	}
	for bad in [valid.trim_right('\n'), 'prefix ' + valid, valid.replace('\n', '\r\n'),
		valid.replace(' operation=', '  operation='), valid.replace(' operation=', '\toperation='),
		valid.replace('stage=9', 'stage=0'), valid.replace('stage=9', 'stage=14'),
		valid.replace('stage=9', 'stage=09'), valid.replace('operation=2', 'operation=1'),
		valid.replace('operation=2', 'operation=5'), valid.replace('event=2', 'event=3'),
		valid.replace('event=2', 'event=0'), valid.replace('code=-1', 'code=0'),
		valid.replace('code=-1', 'code=-2'), valid.replace('code=-1', 'code=10'),
		valid.replace('code=-1', 'code=-0'), valid.replace('code=-1', 'code=+1'),
		valid.replace('code=-1', 'code=01'), valid.replace('code=-1', 'code=2147483648'),
		valid.replace('event=2 code=-1', 'code=-1 event=2'),
		valid.replace('code=-1\n', 'code=-1 email=private@example.invalid\n'),
		valid.replace('code=-1\n', 'code=-1\x00\n'),
		valid.trim_right('\n') + 'x'.repeat(128) + '\n',
	] {
		if account_handoff_diagnostics(bad).records.len != 0 {
			return error('malformed/private handoff output accepted')
		}
	}
	private := 'email=private@example.invalid token=private-secret\n'
	pump := 'ANDROID-AUTH-PUMP-FAIL stage=4 status=-1 pending=1\n'
	mixed := account_handoff_diagnostics(private + 'x'.repeat(129) + '\n' + pump + valid + valid.trim_right('\n'))
	if mixed.records != [expected] || mixed.truncated {
		return error('handoff scan did not recover from private/overlong/pump lines')
	}
	public := json2.encode(Receipt{ account_handoff: mixed })
	if public.contains('private@example.invalid') || public.contains('private-secret')
		|| public.contains('ANDROID-ACCOUNT-HANDOFF') || public.contains('ANDROID-AUTH-PUMP-FAIL') {
		return error('raw private handoff output entered the receipt')
	}
	mut many := ''
	for index in 0 .. 32 {
		many += 'ANDROID-ACCOUNT-HANDOFF stage=' + (index % 8 + 1).str() + ' operation=2 event=0 code=0\n'
	}
	full := account_handoff_diagnostics(many + private + pump + valid.trim_right('\n'))
	if full.records.len != 32 || full.truncated || full.records[0].stage != 1 || full.records[31].stage != 8 {
		return error('handoff cardinality/order differs at the bound')
	}
	over := account_handoff_diagnostics(many + valid + private)
	if !over.truncated || over.records != full.records {
		return error('handoff truncation did not preserve the first 32 complete records')
	}
}

fn required_deployment_inputs_self_test() ! {
	mut complete := map[string]string{}
	for path in [controller_path, '/usr/bin/run-android-calculator', maps_apk, gms_apk,
		registry_path, launcher_path, broker_path, helper_path,
		runtime_root + '/usr/lib/art/libvinix-android-native.so',
		runtime_root + '/usr/lib/libvinix-android-account.so', sqlite_path,
		runtime_root + '/usr/lib/java/dex/android_translation_layer/api-impl.jar',
		runtime_root + '/usr/lib/java/dex/android_translation_layer/classes.dex',
		runtime_root + '/usr/lib/libvinix-android-browser.so'] {
		complete[path] = 'a'.repeat(64)
	}
	required_deployment_inputs(complete)!
	browser := runtime_root + '/usr/lib/libvinix-android-browser.so'
	mut missing := complete.clone()
	missing.delete(browser)
	for replacement in ['', '/usr/lib/libvinix-android-browser.so',
		runtime_root + '/usr/lib/art/libvinix-android-browser.so'] {
		mut invalid := missing.clone()
		if replacement != '' { invalid[replacement] = 'a'.repeat(64) }
		if _ := required_deployment_inputs(invalid) {
			return error('deployment accepted a missing/substituted browser client')
		} else {
			if err.msg() != 'required deployment input absent: ' + browser {
				return error('deployment did not identify the missing browser client')
			}
		}
	}
}

fn app_host_self_test() ! {
	if app_host_path_target(.regular, 0, '')! != app_host_path
		|| app_host_path_target(.symbolic_link, 0, 'vinix-desktop')! != '/usr/bin/vinix-desktop' {
		return error('retained native app host path shapes rejected')
	}
	for link in ['', '/usr/bin/vinix-desktop', '../bin/vinix-desktop', 'vinix-desktop-gpu', 'other'] {
		if _ := app_host_path_target(.symbolic_link, 0, link) {
			return error('unselected app host symlink accepted')
		}
	}
	for kind in [os.FileType.regular, .symbolic_link, .directory] {
		if _ := app_host_path_target(kind, 10012, if kind == .symbolic_link { 'vinix-desktop' } else { '' }) {
			return error('foreign app host path owner accepted')
		}
	}
	if _ := app_host_path_target(.directory, 0, '') { return error('app host directory accepted') }
	desktop := DesktopIdentity{ process: Identity{ pid: 41, parent: 1, start: '100' } }
	host := AppHostIdentity{
		process: Identity{ pid: 42, parent: 41, start: '101' }
		executable: app_host_path
		executable_sha256: app_host_pin
		app_selector: '--vinix-app=vinix-android-calculator'
	}
	process := Identity{ pid: 43, parent: 42, start: '102' }
	check_app_host(host, process, desktop)!
	check_app_host(AppHostIdentity{ ...host, executable: '/usr/bin/vinix-desktop' }, process, desktop)!
	for case in 0 .. 10 {
		invalid := match case {
			0 { AppHostIdentity{ ...host, process: Identity{ ...host.process, parent: 1 } } }
			1 { AppHostIdentity{ ...host, process: Identity{ ...host.process, pid: 41 } } }
			2 { AppHostIdentity{ ...host, process: Identity{ ...host.process, start: '' } } }
			3 { AppHostIdentity{ ...host, uid: 10012 } }
			4 { AppHostIdentity{ ...host, gid: 10013 } }
			5 { AppHostIdentity{ ...host, executable: '/tmp/vinix-android-calculator' } }
			6 { AppHostIdentity{ ...host, executable_sha256: '0'.repeat(64) } }
			7 { AppHostIdentity{ ...host, app_selector: '--vinix-app=vinix-terminal' } }
			8 { AppHostIdentity{ ...host, process: Identity{ ...host.process, pid: 0 } } }
			else { AppHostIdentity{ ...host, executable: '/usr/bin/vinix-desktop-gpu' } }
		}
		if _ := check_app_host(invalid, process, desktop) {
			return error('unselected app host accepted: ' + case.str())
		}
	}
	for invalid in [Identity{ ...process, parent: 41 }, Identity{ ...process, pid: 42 },
		Identity{ ...process, pid: 41 }, Identity{ ...process, pid: 0 }, Identity{ ...process, start: '' }] {
		if _ := check_app_host(host, invalid, desktop) { return error('unbound Maps child accepted') }
	}
	args := [app_host_path, '--vinix-app=vinix-android-calculator', '--request-fd=3', '--response-fd=6']
	app_host_selector(args)!
	for invalid in [
		[app_host_path],
		['/usr/bin/vinix-desktop', args[1], args[2]],
		[app_host_path, '--vinix-app=vinix-terminal', args[2]],
		[app_host_path, args[1], '--vinix-app=vinix-terminal'],
		[app_host_path, args[1], args[1]],
	] {
		if _ := app_host_selector(invalid) { return error('ambiguous app host selector accepted') }
	}
	surface := '/tmp/vinix-android-42.surface'
	check_fresh_surface(surface, host.process, false, false)!
	for invalid in ['/tmp/vinix-android-41.surface', '/tmp/vinix-android-43.surface',
		'/tmp/vinix-android-042.surface', '/tmp/../tmp/vinix-android-42.surface', '', 'vinix-android-42.surface'] {
		if _ := check_fresh_surface(invalid, host.process, false, false) {
			return error('unowned surface path accepted')
		}
	}
	for flags in [[true, false], [false, true], [true, true]] {
		if _ := check_fresh_surface(surface, host.process, flags[0], flags[1]) {
			return error('existing or dangling-symlink surface accepted')
		}
	}
	launch := MapsLaunch{ process: process, app_host: host, desktop: desktop.process }
	check_maps_launch(json2.decode[MapsLaunch](json2.encode(launch))!, desktop)!
	for invalid in [MapsLaunch{ ...launch, kind: 'other' },
		MapsLaunch{ ...launch, desktop: Identity{ ...desktop.process, start: '99' } },
		MapsLaunch{ ...launch, process: Identity{ ...process, parent: 41 } },
		MapsLaunch{ ...launch, app_host: AppHostIdentity{ ...host, process: Identity{ ...host.process, parent: 1 } } }] {
		if _ := check_maps_launch(invalid, desktop) { return error('unbound launch receipt accepted') }
	}
	mut retained := map[int]Identity{}
	retain_receipted_process(mut retained, Identity{}, process)
	retain_receipted_process(mut retained, host.process, host.process)
	if retained.len != 1 || retained[host.process.pid] != host.process {
		return error('early Maps exit lost its live app host cleanup')
	}
	retain_receipted_process(mut retained, Identity{ ...process, parent: 1 }, process)
	if retained[process.pid].parent != 1 { return error('reparented Maps process lost cleanup') }
	for invalid in [Identity{}, Identity{ ...process, pid: 44 }, Identity{ ...process, start: '103' }] {
		mut rejected := map[int]Identity{}
		retain_receipted_process(mut rejected, invalid, process)
		if rejected.len != 0 { return error('unreceipted process retained for cleanup') }
	}
}

// Exercise the production ownership boundary with repeated stat parsing,
// typed Maps JSON decoding, changed start ticks and late validation errors.
// This runs without a guest or app credentials and can be profiled separately.
fn synthetic_poll(scratch &arena.Arena, known map[int]Identity, iteration int,
	launch_json string) !ProcessObservation {
	scratch.push()
	defer { scratch.pop() }
	return synthetic_poll_workload(known, iteration, launch_json)
}

fn synthetic_poll_workload(known map[int]Identity, iteration int, launch_json string) !ProcessObservation {
	mut observed := known.clone()
	launched := json2.decode[MapsLaunch](launch_json)!
	if launched.process.pid != 43 { return error('poll fixture JSON changed') }
	for index in 0 .. 64 {
		start := if index == 0 { (iteration + 100).str() } else { '100' }
		parent := if index == 0 { iteration % 2 + 1 } else { 1 }
		stat := (index + 1).str() + ' (worker with spaces) S ' + parent.str() + ' 0'.repeat(17) + ' ' + start
		item := proc_identity(index + 1, stat)!
		observed[item.pid] = item
	}
	return ProcessObservation{
		processes: observed
		failure: if iteration % 511 == 510 { 'synthetic failure ' + iteration.str() } else { '' }
	}
}

// A deliberately bounded counterfactual: the same parser workload without
// scratch reclamation, matching the previous -gc none polling lifetime.
fn poll_memory_baseline() ! {
	warm_poll_decoders()!
	launch_json := json2.encode(MapsLaunch{process: Identity{pid: 43, parent: 42, start: '102'}})
	mut owned := map[int]Identity{}
	for iteration in 0 .. 4096 {
		owned = synthetic_poll_workload(owned, iteration, launch_json)!.processes
	}
	println('MAPS-ACCOUNT-POLL-MEMORY-BASELINE iterations=4096 processes=${owned.len} reclamation=disabled')
}

fn poll_memory_self_test(iterations int) ! {
	warm_poll_decoders()!
	launch_json := json2.encode(MapsLaunch{process: Identity{pid: 43, parent: 42, start: '102'}})
	defer { unsafe { launch_json.free() } }
	mut scratch := arena.new()
	defer { scratch.free() }
	mut owned := map[int]Identity{}
	defer {
		for _, item in owned { unsafe { item.start.free() } }
		unsafe { owned.free() }
	}
	mut peak_used := 0
	mut peak_capacity := 0
	mut total_scratch := u64(0)
	mut failures := 0
	for iteration in 0 .. iterations {
		observed := synthetic_poll(&scratch, owned, iteration, launch_json) or {
			message := err.msg().clone()
			scratch.reset()
			return error(message)
		}
		mut failure := ''
		adopt_polled_processes(mut owned, observed) or { failure = err.msg() }
		if arena.active() { return error('poll arena remained active after observation') }
		if failure != '' && scratch.owns(failure.str) { return error('scratch error escaped') }
		if scratch.used() > peak_used { peak_used = scratch.used() }
		if scratch.capacity() > peak_capacity { peak_capacity = scratch.capacity() }
		total_scratch += u64(scratch.used())
		for _, item in owned {
			if scratch.owns(item.start.str) { return error('scratch start ticks escaped') }
		}
		scratch.reset()
		if scratch.used() != 0 || scratch.capacity() > 4 * 1024 * 1024
			|| owned.len != 64 || owned[1]!.start.u64() != u64(iteration + 100) {
			return error('poll fixture retained state or arena bound differs')
		}
		// Reuse the released storage before reading retained starts and errors.
		scratch.push()
		poison := []u8{len: 65536, init: u8(0xa5)}
		if poison[0] != 0xa5 { panic('scratch poison changed') }
		scratch.pop()
		for pid, item in owned {
			if item.start.u64() != u64(if pid == 1 { iteration + 100 } else { 100 })
				|| item.parent != if pid == 1 { iteration % 2 + 1 } else { 1 } {
				return error('retained identity changed after arena reuse')
			}
		}
		scratch.reset()
		if iteration % 511 == 510 {
			expected := 'synthetic failure ' + iteration.str()
			if failure != expected { return error('poll error did not survive arena reset') }
			unsafe { expected.free(); failure.free() }
			failures++
		} else if failure != '' {
			return error('unexpected poll fixture failure')
		}
	}
	mut output := []u8{cap: max_file}
	defer { unsafe { output.free() } }
	buffer := output.data
	for block in ['private prefix\nANDROID-ACCOUNT-', 'BROKER-SERVICE package=com.google.android.gms pid=43\n'] {
		append_output_block(mut output, block)!
	}
	if !broker_service_ready(output) || output.data != buffer || output.cap != max_file {
		return error('fragmented readiness or fixed diagnostic buffer differs')
	}
	if broker_service_ready('private ANDROID-ACCOUNT-BROKER-SERVICE package=com.google.android.gms pid=43\n'.bytes()) {
		return error('readiness accepted away from line start')
	}
	println('MAPS-ACCOUNT-POLL-MEMORY-PASS iterations=${iterations} processes=${owned.len} scratch_peak_used=${peak_used} scratch_peak_capacity=${peak_capacity} scratch_total=${total_scratch} copied_errors=${failures} output_capacity=${output.cap}')
}

fn self_test() ! {
	onboarding_trace_self_test()!
	poll_memory_self_test(256)!
	auth_init_self_test()!
	browser_init_self_test()!
	auth_pump_self_test()!
	account_handoff_self_test()!
	required_deployment_inputs_self_test()!
	protected_directory_self_test()!
	sqlite_self_test()!
	app_host_self_test()!
	if !canonical_absolute('/opt/maps/app.apk') || canonical_absolute('/opt/../maps/app.apk')
		|| canonical_absolute('/opt//maps.apk') || canonical_absolute('maps.apk')
		|| valid_pin('A'.repeat(64)) || !valid_pin('a'.repeat(64)) {
		return error('canonical input tests failed')
	}
	if status_id('Uid:\t10012\t10012\t10012\t10012\n', 'Uid')! != 10012 {
		return error('identity parse failed')
	}
	if _ := status_id('Uid:\t10012\t0\t10012\t10012\n', 'Uid') {
		return error('mixed credentials accepted')
	}
	if _ := status_id('Uid:\t010012\t010012\t010012\t010012\n', 'Uid') {
		return error('noncanonical credentials accepted')
	}
	pins := {
		maps_apk: 'a'.repeat(64)
		gms_apk:  'b'.repeat(64)
	}
	registry := 'vinix-android-account-authority-v1\ncom.google.android.apps.maps\t10012\t10012\t' + maps_apk + '\t' + pins[maps_apk]! + '\t' + 'c'.repeat(64) + '\t-\ncom.google.android.gms\t10013\t10013\t' + gms_apk + '\t' + pins[gms_apk]! + '\t' + 'c'.repeat(64) + '\t' + service_class + '@android.accounts.AccountAuthenticator@com.google\n'
	registry_matches(registry, pins)!
	for invalid in [registry.replace('10013', '10012'), registry.replace('@com.google', '@fake'),
		registry + 'extra\n', registry.replace(pins[gms_apk]!, 'd'.repeat(64))] {
		if _ := registry_matches(invalid, pins) { return error('registry mutation accepted') }
	}
	before := '# exact prefix\nroot:x:0:0:root:/root:/bin/sh'
	update := prepare_database_text('/etc/passwd', before, false)!
	if update.before != before || !update.after.starts_with(before + '\n')
		|| update.after.split_into_lines().filter(it.starts_with('vinix-')).len != 2 {
		return error('account append did not retain exact prefix')
	}
	for invalid in [before + '\nother:x:10012:10012:user:/home/u:/bin/sh\n',
		before + '\nother:x:100:10013:user:/home/u:/bin/sh\n',
		before + '\nvinix-gms-account:x:100:100:user:/home/u:/bin/sh\n'] {
		if _ := prepare_database_text('/etc/passwd', invalid, false) {
			return error('identity collision accepted')
		}
	}
	if _ := prepare_database_text('/etc/group', 'root:x:0:\nother:x:10013:\n', true) {
		return error('group collision accepted')
	}
	controller := Identity{ pid: 42, parent: 12, start: '345' }
	broker := Identity{ pid: 43, parent: 42, start: '346' }
	request := StopRequest{ controller: controller, broker: broker }
	if !matching_stop(json2.decode[StopRequest](json2.encode(request))!, controller, broker) {
		return error('stop request binding rejected')
	}
	for invalid in [
		StopRequest{ kind: 'other', controller: controller, broker: broker },
		StopRequest{ controller: Identity{ pid: 42, parent: 12, start: '344' }, broker: broker },
		StopRequest{ controller: controller, broker: Identity{ pid: 43, parent: 42, start: '347' } },
	] {
		if matching_stop(invalid, controller, broker) {
			return error('stale stop request accepted')
		}
	}
	println('MAPS-ACCOUNT-GUEST-SELFTEST-PASS canonical-paths protected-directory-symlink-and-mode-rejection process-credentials registry-principals service-selector APK-pins database-prefix UID-GID-name-collisions stop-session-binding SQLite-exact-hardlink-group exclusive-create bounded-copy atomic-alias-preservation bounded-numeric-auth-diagnostics bounded-numeric-browser-diagnostics bounded-numeric-pump-diagnostics bounded-numeric-account-handoff mandatory-browser-client native-app-host-identity-and-selector fresh-app-host-surface grandchild-launch-receipt-binding independent-session-selected-onboarding-and-TLS-traces private-diagnostic-export-exclusion')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--poll-memory-baseline' {
		poll_memory_baseline() or { eprintln(err); exit(1) }
		return
	}
	if os.args.len == 2 && os.args[1] == '--poll-memory-self-test' {
		poll_memory_self_test(18000) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if C.getuid() != 0 || C.geteuid() != 0 {
		eprintln('Maps account fixture requires real and effective root')
		exit(1)
	}
	if os.args.len == 2 && os.args[1] == '--stop' {
		request_stop() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	launch := os.base(os.args[0]) == 'run-android-calculator' || (os.args.len == 2 && os.args[1] == '--launch')
	if launch {
		launch_maps() or {
			eprintln('MAPS-ACCOUNT-LAUNCH-FAILED ' + err.msg())
			exit(1)
		}
		return
	}
	diagnostics := broker_diagnostics(os.args[1..]) or {
		eprintln('usage: maps-account-guest [--broker [--trace-onboarding] [--trace-tls]|--launch|--stop|--self-test]')
		eprintln(err)
		exit(1)
	}
	private_result_root() or {
		eprintln(err)
		exit(1)
	}
	mut receipt := Receipt{
		started_utc: time.utc().str(), trace_onboarding: diagnostics.trace_onboarding, trace_tls: diagnostics.trace_tls
	}
	broker_session(mut receipt) or {
		receipt.status = 'failed'
		receipt.error = err.msg()
	}
	receipt.finished_utc = time.utc().str()
	save_receipt(receipt) or {
		eprintln(err)
		exit(1)
	}
	mut logs := map[string]string{}
	for name in ['broker.log', 'maps.log'] {
		if os.exists(result_root + '/' + name) {
			logs[name] = hash(result_root + '/' + name) or {
				eprintln(err)
				exit(1)
			}
		}
	}
	os.write_file(result_root + '/private-log-sha256.json', json2.encode(logs) + '\n') or {
		eprintln(err)
		exit(1)
	}
	// Export receipt/identity evidence; native logs remain private in the guest.
	export_serial(archive(result_root) or {
		eprintln(err)
		exit(1)
	}) or {
		eprintln(err)
		exit(1)
	}
	if receipt.status == 'failed' || receipt.cleanup_survivors != 0 {
		eprintln(receipt.error)
		exit(1)
	}
}
