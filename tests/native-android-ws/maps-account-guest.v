// SPDX-License-Identifier: GPL-2.0-or-later
// Opt-in real Maps/GMS deployment controller, invoked as root from a GUI terminal.
// Readiness is transport evidence only; this never claims Google authentication.
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
	#include <sys/mount.h>
}

fn C.prctl(int, u64, u64, u64, u64) int
fn C.waitpid(int, &int, int) int
fn C.mount(&char, &char, &char, u64, voidptr) int
fn C.dup2(int, int) int

const bundle_root = '/opt/vinix-maps-account'
const result_root = bundle_root + '/results'
const runtime_root = '/opt/vinix-android-aarch64'
const broker_root = '/var/run/vinix-maps-account'
const controller_path = bundle_root + '/bin/maps-account-guest'
const helper_path = runtime_root + '/usr/bin/vinix-android-account-ui'
const broker_path = runtime_root + '/usr/bin/native-account-broker'
const launcher_path = runtime_root + '/usr/bin/run-android'
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
	kind         string = 'vinix-maps-account-session-v1'
	build_sha256 string
	controller   Identity
	broker       Identity
	desktop      DesktopIdentity
}

struct StopRequest {
	kind       string = 'vinix-maps-account-stop-v1'
	controller Identity
	broker     Identity
}

struct Receipt {
	scope       string = 'Real Maps and Google Play Services transport diagnostics. No credentials supplied; broker readiness does not establish Google authentication.'
	started_utc string
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
		|| build.inputs_sha256.len < 13 || build.inputs_sha256.len > 20032 {
		return error('deployment receipt identity differs')
	}
	for path in [controller_path, '/usr/bin/run-android-calculator', maps_apk, gms_apk, registry_path,
		launcher_path, broker_path, helper_path,
		runtime_root + '/usr/lib/art/libvinix-android-native.so',
		runtime_root + '/usr/lib/libvinix-android-account.so',
		runtime_root + '/usr/lib/libsqlite3.so.0',
		runtime_root + '/usr/lib/java/dex/android_translation_layer/api-impl.jar',
		runtime_root + '/usr/lib/java/dex/android_translation_layer/classes.dex'] {
		if path !in build.inputs_sha256 {
			return error('required deployment input absent: ' + path)
		}
	}
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
	for path in ['/var', '/var/lib', '/var/lib/vinix', '/var/lib/vinix/apps', '/var/run'] {
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

fn track_maps_launch(mut owned map[int]Identity, desktop Identity) ! {
	path := result_root + '/maps-launch.json'
	if !os.exists(path) && !os.is_link(path) { return }
	protected(path, 0, true, .regular)!
	if os.lstat(path)!.nlink != 1 || os.lstat(path)!.size > 4096 {
		return error('Maps process receipt shape differs')
	}
	launched := json2.decode[Identity](os.read_file(path)!)!
	if launched.pid <= 0 || launched.parent != desktop.pid {
		return error('Maps process is not the selected desktop child')
	}
	current := identity(launched.pid) or { return }
	if current.start == launched.start { owned[launched.pid] = launched }
}

fn broker_session(mut receipt Receipt) ! {
	build := build_inputs(true)!
	receipt.build_sha256 = hash(bundle_root + '/build.json')!
	os.cp(bundle_root + '/build.json', result_root + '/build.json')!
	receipt.desktop = desktop_identity()!
	os.write_file(result_root + '/identity/desktop.json', json2.encode(receipt.desktop) + '\n')!
	provision()!
	receipt.runtime_mount = approve_runtime()!
	enable_subreaper()!
	select_environment(build, '10013')!
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
	mut owned := {
		os.getpid(): identity(os.getpid())!
		child.pid:   receipt.broker
	}
	defer {
		track_maps_launch(mut owned, receipt.desktop.process) or {}
		discover(mut owned) or {}
		for item in selected_processes() or { []Identity{} } { owned[item.pid] = item }
		kill_owned(owned)
		reap_broker(mut child)
		receipt.broker_exit = child.code
		receipt.cleanup_survivors = cleanup(mut owned) or { -1 }
		os.rm(broker_root + '/session.json') or {}
	}
	deadline := time.sys_mono_now() + 15 * time.minute
	startup := time.sys_mono_now() + 45 * time.second
	mut output := ''
	for {
		block := child.stdout_read()
		if block != '' {
			if output.len + block.len > max_file { return error('broker diagnostic log limit') }
			log.write_string(block)!
			output += block
		}
		track_maps_launch(mut owned, receipt.desktop.process)!
		discover(mut owned)!
		for item in selected_processes()! { owned[item.pid] = item }
		if !receipt.service_ready && output.split_into_lines().any(it.starts_with('ANDROID-ACCOUNT-BROKER-SERVICE package=com.google.android.gms pid=')) {
			window_identity(receipt.desktop.uid)!
			if window_peer(receipt.desktop.window_socket)! != receipt.desktop.peer
				|| identity(receipt.desktop.process.pid)! != receipt.desktop.process {
				return error('desktop identity changed before service readiness')
			}
			session := Session{
				build_sha256: receipt.build_sha256
				controller:   identity(os.getpid())!
				broker:       receipt.broker
				desktop:      receipt.desktop
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
		if os.exists(result_root + '/maps.log') && os.lstat(result_root + '/maps.log')!.size > max_file {
			return error('Maps diagnostic log limit')
		}
		if stop_requested(owned[os.getpid()]!, receipt.broker)! {
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
	surface := os.getenv('VINIX_SURFACE_PATH')
	if surface != '/tmp/vinix-android-' + desktop.process.pid.str() + '.surface'
		|| os.exists(surface) || os.is_link(surface) {
		return error('fresh compositor surface required')
	}
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
	mut log := os.open_file(result_root + '/maps.log', 'wx', 0o600)!
	if C.dup2(log.fd, 1) != 1 || C.dup2(log.fd, 2) != 2 {
		return error('cannot retain private Maps diagnostics')
	}
	log.close()
	publish_fresh(result_root + '/maps-launch.json', json2.encode(identity(os.getpid())!) + '\n', 0o600)!
	println('MAPS-ACCOUNT-LAUNCH uid=10012 gid=10012 package=com.google.android.apps.maps')
	os.execvp(launcher_path, [maps_apk])!
}

fn self_test() ! {
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
	println('MAPS-ACCOUNT-GUEST-SELFTEST-PASS canonical-paths process-credentials registry-principals service-selector APK-pins database-prefix UID-GID-name-collisions stop-session-binding')
}

fn main() {
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
	if os.args.len > 2 || (os.args.len == 2 && os.args[1] != '--broker') {
		eprintln('usage: maps-account-guest [--broker|--launch|--stop|--self-test]')
		exit(1)
	}
	private_result_root() or {
		eprintln(err)
		exit(1)
	}
	mut receipt := Receipt{ started_utc: time.utc().str() }
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
