// SPDX-License-Identifier: GPL-2.0-or-later
// Opt-in root fixture: real ART/JNI/SQLite and production accountbroker routing.
// Account names and token values belong to the signed synthetic fixture APK.
module main

import accountbroker
import accountuifd
import crypto.sha256
import encoding.base64
import json2
import nativeaccountauth
import os
import time

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.getuid() u32
fn C.geteuid() u32
fn C.getpwuid(u32) voidptr
fn C.getgrgid(u32) voidptr
fn C.fork() i32
fn C.setpgid(i32, i32) i32
fn C.pipe(&i32) i32
fn C.dup2(i32, i32) i32
fn C.open(&char, i32, ...voidptr) i32
fn C.close(i32) i32
fn C.chown(&char, i32, i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.kill(i32, i32) i32
fn C._exit(i32)
fn C.socket(i32, i32, i32) i32
fn C.shutdown(i32, i32) i32
fn C.bind(i32, voidptr, u32) i32
fn C.listen(i32, i32) i32
fn C.accept(i32, voidptr, voidptr) i32
fn C.fcntl(i32, i32, ...i32) i32
fn C.poll(voidptr, uint, i32) i32

const fixture_sha256 = 'e4766dbe14ec5cd4fb64c23d66ecc44becd017f175c4104d27804fb1a0fc12ab'
const fixture_cert_sha256 = '12520d3c4783e80927f029e8d0108b9808e3c17fbb9d69647f10527ffe1308f7'
const fixture_package = 'org.vinix.bootstrap'
const fixture_service = fixture_package + '.TokenCacheService'
const fixture_action = 'android.accounts.AccountAuthenticator'
const fixture_type = 'org.vinix.fixture.account'
const fixture_client = fixture_package + '.TokenCacheClient'
const ready_marker = 'ACCOUNT-TOKEN-CACHE-READY owner null-empty exact-invalidation password-clear'
const client_marker = 'ACCOUNT-TOKEN-CACHE-CLIENT-PASS owner-denied null-type null-token synchronous-broker-ack'
const authenticators_marker = 'ACCOUNT-AUTHENTICATORS-PASS'
const pass_marker = 'ACCOUNT-TOKEN-CACHE-PASS broker-invalidation exact-multiaccount preserved-other-value'
const persist_marker = 'ACCOUNT-TOKEN-CACHE-PERSIST-PASS cleared-token preserved-other-value'
const closed_marker = 'ANDROID-SERVICE-CLOSED unbind destroy'
const runtime_ready = 'ANDROID-SERVICE-READY package=' + fixture_package + ' service=' + fixture_service + ' graphics=absent activity=absent'
const serial_prefix = 'VINIX-ACCOUNT-TOKEN-CACHE-RESULTS-1 '
const chunk_bytes = 512

struct EvidenceEntry {
	path string
	kind string
	mode u32
	size u64
	sha256 string
	data string
}

struct EvidenceArchive {
	version int = 1
	root_mode u32 = 0o755
	entries []EvidenceEntry
}

struct ListenerPoll {
mut:
	fd i32
	events i16
	revents i16
}

struct Configuration {
	runtime string
	apk string
	registry string
	output string
	uid u32
	gid u32
}

struct CaseReceipt {
	name string
	service_pid i32
	client_pid i32
	service_wait_status i32
	client_wait_status i32
	log_sha256 map[string]string
	checks []string
}

struct Receipt {
	kind string = 'vinix-account-token-cache-controller-v1'
	created_utc string
	uid u32
	gid u32
	inputs_sha256 map[string]string
	cases []CaseReceipt
	scope string = 'signed synthetic fixture; real ART/JNI/SQLite and authenticated production broker; no Google account or Google login claim'
}

fn require(ok bool, why string) ! {
	if !ok { return error('account token cache controller: ' + why) }
}

fn canonical(path string) bool {
	return path.starts_with('/') && path.len > 1 && !path.ends_with('/')
		&& !path.contains('\\') && !path.contains('\x00')
		&& path.bytes().all(it >= 32 && it != 127)
		&& path.split('/')[1..].all(it !in ['', '.', '..'])
}

fn digest(path string) !string {
	require(os.lstat(path)!.get_filetype() == .regular, 'regular input: ' + path)!
	mut input := os.open(path)!
	defer { input.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := input.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn protected_output(path string) ! {
	require(canonical(path) && path.len <= 55, 'canonical output path of at most 55 bytes')!
	require(!os.exists(path) && !os.is_link(path), 'fresh output directory')!
	mut current := '/'
	for part in path.split('/')[1..path.split('/').len - 1] {
		current = current.trim_right('/') + '/' + part
		info := os.lstat(current)!
		require(info.get_filetype() == .directory && info.uid == 0 && info.mode & 0o022 == 0
			&& info.mode & 0o001 != 0, 'root-protected, target-traversable output ancestors')!
	}
	os.mkdir(path, mode: 0o755)!
	os.chmod(path, 0o755)!
}

fn export_evidence(root string) ! {
	mut entries := []EvidenceEntry{}
	for directory in ['cache', 'restart'] {
		entries << EvidenceEntry{path: directory, kind: 'directory', mode: 0o755}
	}
	// Only fixed fixture logs and the controller receipt leave the guest. App
	// databases, APKs and data directories are retained in the fresh result root.
	for name in ['receipt.json', 'cache/service.log', 'cache/client.log', 'restart/service.log'] {
		path := root + '/' + name
		text := log_text(path)!
		entries << EvidenceEntry{
			path: name
			kind: 'regular'
			mode: os.lstat(path)!.mode & 0o777
			size: u64(text.len)
			sha256: sha256.sum(text.bytes()).hex()
			data: base64.encode(text.bytes())
		}
	}
	payload := json2.encode(EvidenceArchive{entries: entries})
	require(payload.len <= 9 * 1024 * 1024, 'bounded serial evidence')!
	fd := unsafe { C.open(c'/dev/console', C.O_WRONLY | C.O_NOCTTY | C.O_CLOEXEC) }
	require(fd >= 0, 'open serial evidence console')!
	defer { C.close(fd) }
	payload_sha := sha256.sum(payload.bytes()).hex()
	shape := payload_sha + ' ' + payload.len.str() + ' ' + ((payload.len + chunk_bytes - 1) / chunk_bytes).str() + '\n'
	serial_frame(fd, serial_prefix + 'BEGIN ' + shape)!
	for offset := 0; offset < payload.len; offset += chunk_bytes {
		end := if offset + chunk_bytes < payload.len { offset + chunk_bytes } else { payload.len }
		serial_frame(fd, serial_prefix + 'CHUNK ' + payload_sha + ' ' + (offset / chunk_bytes).str() + ' '
			+ base64.encode(payload[offset..end].bytes()) + '\n')!
	}
	serial_frame(fd, serial_prefix + 'END ' + shape)!
}

fn serial_frame(fd i32, line string) ! {
	require(line.len < 1024 && line.starts_with(serial_prefix) && line.ends_with('\n')
		&& !line[..line.len - 1].contains_any('\r\n'), 'bounded serial frame')!
	framed := '\n' + line
	require(unsafe { C.write(fd, framed.str, uint(framed.len)) } == framed.len, 'single serial frame write')!
}

fn log_text(path string) !string {
	require(os.lstat(path)!.size <= 2 * 1024 * 1024, 'bounded child log: ' + path)!
	return os.read_file(path)
}

fn healthy(text string) bool {
	return !['-FAIL', 'FATAL EXCEPTION', 'JNI DETECTED ERROR', 'VerifyError',
		'Exception in thread', 'Abort message:'].any(text.contains(it))
}

fn exact_marker(text string, marker string) bool {
	return text.split_into_lines().filter(it == marker).len == 1 && text.count(marker) == 1
}

fn client_complete(text string) bool {
	return exact_marker(text, authenticators_marker) && exact_marker(text, client_marker)
}

fn listener(path string) !i32 {
	require(path.len < 104 && !os.exists(path) && !os.is_link(path), 'fresh short listener')!
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	require(fd >= 3, 'create listener')!
	mut ok := false
	defer { if !ok { C.close(fd) } }
	flags, status := C.fcntl(fd, C.F_GETFD), C.fcntl(fd, C.F_GETFL)
	require(flags >= 0 && status >= 0 && C.fcntl(fd, C.F_SETFD, flags | C.FD_CLOEXEC) == 0
		&& C.fcntl(fd, C.F_SETFL, status | C.O_NONBLOCK) == 0, 'protect listener')!
	mut address := C.sockaddr_un{}
	address.sun_family = C.AF_UNIX
	unsafe { C.memcpy(&address.sun_path[0], path.str, uint(path.len)) }
	$if macos { address.sun_len = u8(sizeof(C.sockaddr_un)) }
	require(C.bind(fd, voidptr(&address), u32(sizeof(C.sockaddr_un))) == 0, 'bind listener')!
	os.chmod(path, 0o666)!
	require(C.listen(fd, 32) == 0, 'listen')!
	ok = true
	return fd
}

fn owned_directory(path string, uid u32, gid u32) ! {
	os.mkdir(path, mode: 0o700)!
	os.chmod(path, 0o700)!
	require(unsafe { C.chown(path.str, i32(uid), i32(gid)) } == 0, 'target-owned directory')!
}

fn environment(config Configuration, client bool) {
	for name in ['VINIX_SURFACE_PATH', 'VINIX_INPUT_FD', 'VINIX_ANDROID_AUTHENTICATOR_FD',
		'VINIX_ANDROID_AUTHENTICATOR_TYPE', 'VINIX_ANDROID_WEBVIEW_FD',
		'VINIX_ANDROID_BROWSER_MANIFEST', 'VINIX_ANDROID_BROWSER_ROOT',
		'VINIX_ANDROID_BROWSER_MANIFEST_SHA256', 'VINIX_ANDROID_ACCOUNT_SOCKET',
		'VINIX_ANDROID_WEBVIEW_MANIFEST', 'DISPLAY', 'WAYLAND_DISPLAY', 'LD_PRELOAD', 'LD_LIBRARY_PATH'] {
		os.unsetenv(name)
	}
	os.setenv('VINIX_ANDROID_ROOT', config.runtime, true)
	os.setenv('VINIX_ANDROID_ACCOUNT_REGISTRY', config.registry, true)
	os.setenv('VINIX_ANDROID_UID', config.uid.str(), true)
	os.setenv('VINIX_ANDROID_GID', config.gid.str(), true)
	base := config.output + if client { '/client' } else { '/service' }
	os.setenv('ANDROID_APP_DATA_DIR', base + '-data', true)
	os.setenv('VINIX_ANDROID_HOME', base + '-home', true)
}

fn redirect(log_fd i32, input_fd i32) bool {
	return C.setpgid(0, 0) == 0 && C.dup2(log_fd, 1) == 1 && C.dup2(log_fd, 2) == 2
		&& C.dup2(input_fd, 0) == 0
}

fn spawn_service(config Configuration, channel i32, other i32, socket string, log_fd i32) !i32 {
	child := C.fork()
	require(child >= 0, 'fork service')!
	if child == 0 {
		C.close(other)
		input := unsafe { C.open(c'/dev/null', C.O_RDONLY) }
		if input < 0 || !redirect(log_fd, input) { C._exit(120) }
		C.close(log_fd)
		if input > 2 { C.close(input) }
		environment(config, false)
		nativeaccountauth.inherit_root_channel(int(channel)) or { C._exit(121) }
		os.execvp(config.runtime + '/usr/bin/run-android', [config.apk, '--service-fd', channel.str(),
			'--authenticator-socket', socket]) or { eprintln(err); C._exit(122) }
		C._exit(123)
	}
	return child
}

fn spawn_client(config Configuration, input i32, writer i32, log_fd i32, socket string) !i32 {
	child := C.fork()
	require(child >= 0, 'fork ordinary client')!
	if child == 0 {
		C.close(writer)
		if !redirect(log_fd, input) { C._exit(120) }
		C.close(log_fd)
		if input > 2 { C.close(input) }
		environment(config, true)
		os.setenv('VINIX_SURFACE_PATH', config.output + '/client-data/client.surface', true)
		os.setenv('VINIX_ANDROID_ACCOUNT_SOCKET', socket, true)
		os.execvp(config.runtime + '/usr/bin/run-android', [config.apk, '-l', fixture_client,
			'-w', '64', '-h', '64']) or { eprintln(err); C._exit(122) }
		C._exit(123)
	}
	return child
}

fn wait_clean(pid i32, seconds int) !i32 {
	deadline := time.sys_mono_now() + i64(seconds) * time.second
	mut status := i32(-1)
	for time.sys_mono_now() < deadline {
		waited := C.waitpid(pid, &status, C.WNOHANG)
		require(waited == 0 || waited == pid, 'wait direct child')!
		if waited == pid { return status }
		time.sleep(20 * time.millisecond)
	}
	return error('account token cache controller: child exit deadline')
}

fn kill_unreaped(pid i32) {
	if pid <= 0 { return }
	// Until waitpid reaps this direct child its PID cannot be reused.
	C.kill(-pid, C.SIGKILL)
	C.kill(pid, C.SIGKILL)
	mut status := i32(0)
	C.waitpid(pid, &status, 0)
}

fn write_frame(fd i32) ! {
	frame := ['vinix-android-service-host-v1', fixture_package, fixture_service, fixture_action,
		fixture_sha256].join('\t') + '\n'
	mut offset := 0
	for offset < frame.len {
		mut flags := i32(0)
		$if linux { flags = C.MSG_NOSIGNAL }
		n := unsafe { C.send(fd, frame.str + offset, uint(frame.len - offset), flags) }
		require(n > 0, 'send root-selected service frame')!
		offset += int(n)
	}
}

fn run_case(config Configuration, restart bool) !CaseReceipt {
	name := if restart { 'restart' } else { 'cache' }
	base := config.output + '/' + name
	os.mkdir(base, mode: 0o755)!
	os.chmod(base, 0o755)!
	clients_path, auth_path := base + '/accounts.sock', base + '/authenticator.sock'
	clients := listener(clients_path)!
	defer { C.close(clients); os.rm(clients_path) or {} }
	services := listener(auth_path)!
	defer { C.close(services); os.rm(auth_path) or {} }
	service_log, client_log := base + '/service.log', base + '/client.log'
	mut service_file := os.open_file(service_log, 'wx', 0o644)!
	mut pair := accountuifd.socket_pair()!
	mut lifetime := pair[0]
	service := spawn_service(config, pair[1], pair[0], auth_path, service_file.fd) or {
		C.close(pair[0]); C.close(pair[1]); service_file.close(); return err
	}
	C.close(pair[1])
	service_file.close()
	mut broker := &accountbroker.Broker(unsafe { nil })
	mut service_reaped, client_reaped := false, false
	mut client := i32(-1)
	mut input_writer := i32(-1)
	defer {
		if input_writer >= 0 { C.close(input_writer) }
		if broker != unsafe { nil } { broker.close(); unsafe { free(broker) } }
		if lifetime >= 0 { C.close(lifetime) }
		if !client_reaped { kill_unreaped(client) }
		if !service_reaped { kill_unreaped(service) }
		for path in [service_log, client_log] {
			if !os.exists(path) { continue }
			println('ACCOUNT-TOKEN-CONTROLLER-LOG-BEGIN ' + name + '/' + os.base(path))
			print(log_text(path) or { '<bounded log unavailable>\n' })
			println('ACCOUNT-TOKEN-CONTROLLER-LOG-END ' + name + '/' + os.base(path))
		}
	}
	registry := nativeaccountauth.load(config.registry)!
	entry := registry.verify_service(config.apk, config.uid, config.gid, fixture_service, fixture_action)!
	broker = accountbroker.create(registry, entry, int(service), int(lifetime))!
	lifetime = -1 // broker owns it after successful create
	write_frame(pair[0])!
	mut attached := false
	mut complete := false
	deadline := time.sys_mono_now() + 150 * time.second
	for time.sys_mono_now() < deadline {
		mut ready := [ListenerPoll{fd: clients, events: i16(C.POLLIN)},
			ListenerPoll{fd: services, events: i16(C.POLLIN)}]!
		polled := C.poll(voidptr(&ready[0]), 2, 10)
		require(polled >= 0 || C.errno == C.EINTR, 'listener poll')!
		for index in 0 .. 2 {
			if ready[index].revents & C.POLLIN == 0 { continue }
			fd := C.accept(ready[index].fd, unsafe { nil }, unsafe { nil })
			if fd < 0 { continue }
			if index == 1 {
				broker.attach_service(int(fd)) or { C.close(fd); return err }
				attached = true
			} else {
				broker.accept_client(int(fd)) or { C.close(fd); return err }
			}
		}
		broker.pump(0)!
		service_text := log_text(service_log)!
		require(healthy(service_text), 'service failure')!
		if !restart && attached && client < 0 && exact_marker(service_text, ready_marker)
			&& exact_marker(service_text, runtime_ready) {
			mut pipe := [2]i32{}
			require(C.pipe(&pipe[0]) == 0, 'ordinary client input pipe')!
			mut protected := true
			for fd in pipe { if C.fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) != 0 { protected = false } }
			if !protected { C.close(pipe[0]); C.close(pipe[1]); return error('protect input pipe') }
			input_writer = pipe[1]
			mut file := os.open_file(client_log, 'wx', 0o644) or { C.close(pipe[0]); return err }
			client = spawn_client(config, pipe[0], pipe[1], file.fd, clients_path) or {
				C.close(pipe[0]); file.close(); return err
			}
			C.close(pipe[0])
			file.close()
		}
		if restart {
			complete = attached && exact_marker(service_text, persist_marker)
		} else if client >= 0 {
			client_text := log_text(client_log)!
			require(healthy(client_text), 'ordinary client failure')!
			complete = exact_marker(service_text, ready_marker) && exact_marker(service_text, pass_marker)
				&& client_complete(client_text) && broker.active() == 0
		}
		if complete { break }
		mut status := i32(-1)
		if C.waitpid(service, &status, C.WNOHANG) == service {
			service_reaped = true
			return error('account token cache controller: service exited before completion')
		}
		if client >= 0 && C.waitpid(client, &status, C.WNOHANG) == client {
			client_reaped = true
			return error('account token cache controller: ordinary client exited before completion')
		}
	}
	require(complete, 'cache lifecycle deadline')!
	mut client_status := i32(0)
	if client >= 0 {
		C.close(input_writer)
		input_writer = -1
		client_status = wait_clean(client, 15)!
		client_reaped = true
		client_text := log_text(client_log)!
		require(client_status == 0 && healthy(client_text) && client_complete(client_text), 'client clean exit and exact metadata/cache PASS')!
	}
	// Signal EOF while the authenticator connection remains alive. Closing its
	// stream first could race the normal service unbind/destroy path.
	require(C.shutdown(pair[0], C.SHUT_WR) == 0, 'root lifetime EOF')!
	status := wait_clean(service, 15)!
	service_reaped = true
	broker.close()
	text := log_text(service_log)!
	require(status == 0 && healthy(text) && exact_marker(text, runtime_ready)
		&& exact_marker(text, closed_marker), 'service clean EOF lifecycle')!
	require(if restart {
		exact_marker(text, persist_marker) && !text.contains(ready_marker) && !text.contains(pass_marker)
	} else {
		exact_marker(text, ready_marker) && exact_marker(text, pass_marker) && !text.contains(persist_marker)
	}, 'exact service phase markers')!
	mut logs := {service_log: digest(service_log)!}
	if client >= 0 { logs[client_log] = digest(client_log)! }
	return CaseReceipt{
		name: name
		service_pid: service
		client_pid: client
		service_wait_status: status
		client_wait_status: client_status
		log_sha256: logs
		checks: if restart { ['same-store-restart', 'token-deletion-durable', 'other-value-preserved', 'clean-EOF-exit'] }
			else { ['trusted-authenticator-descriptions', 'owner-null-empty-exact-cache', 'password-clear-purge', 'ordinary-client-owner-denied',
				'kernel-authenticated-broker-invalidation', 'multiaccount-exact-delete', 'clean-client-and-service-exit'] }
	}
}

fn self_test() ! {
	for path in ['/opt/cache/probe', '/root/account-cache-1'] { require(canonical(path), 'canonical valid test')! }
	for path in ['', '/', 'relative', '/x/', '/x//y', '/x/../y', '/x/./y', '/x\\y', '/x\x00y', '/x\ny', '/x\x7fy'] {
		require(!canonical(path), 'canonical invalid test')!
	}
	require(exact_marker(client_marker + '\n', client_marker), 'single marker')!
	for text in [client_marker + '\n' + client_marker + '\n', 'prefix ' + client_marker + '\n'] {
		require(!exact_marker(text, client_marker), 'duplicate or forged marker')!
	}
	client_pass := authenticators_marker + '\n' + client_marker + '\n'
	require(client_complete(client_pass), 'complete metadata and cache result')!
	for text in [client_marker + '\n', authenticators_marker + '\n',
		client_pass + authenticators_marker + '\n', client_pass + client_marker + '\n',
		'prefix ' + authenticators_marker + '\n' + client_marker + '\n'] {
		require(!client_complete(text), 'missing, duplicate or forged client phase')!
	}
	for text in ['ANDROID-WS-FAIL start', 'JNI DETECTED ERROR', 'FATAL EXCEPTION', 'VerifyError'] {
		require(!healthy(text), 'failure rejection')!
	}
	mut pipe := [2]i32{}
	require(C.pipe(&pipe[0]) == 0, 'serial test pipe')!
	defer { C.close(pipe[0]); C.close(pipe[1]) }
	line := serial_prefix + 'BEGIN ' + 'a'.repeat(64) + ' 2 1\n'
	serial_frame(pipe[1], line)!
	mut bytes := []u8{len: 1024}
	n := unsafe { C.read(pipe[0], bytes.data, uint(bytes.len)) }
	require(n == line.len + 1 && bytes[..int(n)].bytestr() == '\n' + line, 'complete atomic serial frame')!
	for malformed in ['', 'invalid\n', serial_prefix + 'line\nextra\n', serial_prefix + 'a'.repeat(1024) + '\n'] {
		if _ := serial_frame(pipe[1], malformed) { return error('malformed serial frame accepted') }
	}
	println('ACCOUNT-TOKEN-CACHE-CONTROLLER-SELFTEST-PASS canonical-paths exact-phase-markers failure-rejection bounded-atomic-serial')
}

fn run() ! {
	$if !linux { return error('account token cache controller requires Linux/Vinix') }
	require(C.getuid() == 0 && C.geteuid() == 0, 'root controller')!
	require(os.args.len == 6, 'usage: account-token-cache-controller RUNTIME_ROOT FIXTURE_APK UID GID FRESH_OUTPUT')!
	runtime, source, uid_text, gid_text, output := os.args[1], os.args[2], os.args[3], os.args[4], os.args[5]
	for value in [uid_text, gid_text] {
		require(value.len == 5 && value.bytes().all(it >= `0` && it <= `9`)
			&& value.int() >= 10000 && value.int() <= 19999, 'fixture UID/GID in 10000..19999')!
	}
	uid, gid := uid_text.u32(), gid_text.u32()
	require(C.getpwuid(uid) != unsafe { nil } && C.getgrgid(gid) != unsafe { nil }, 'pre-provisioned Unix account/group')!
	require(canonical(runtime) && canonical(source), 'canonical runtime and APK')!
	require(digest(source)! == fixture_sha256, 'exact signed synthetic cache APK pin')!
	protected_output(output)!
	apk, registry_path := output + '/fixture.apk', output + '/registry'
	os.cp(source, apk)!
	os.chmod(apk, 0o444)!
	registry := 'vinix-android-account-authority-v1\n' + [fixture_package, uid_text, gid_text, apk,
		fixture_sha256, fixture_cert_sha256, fixture_service + '@' + fixture_action + '@' + fixture_type].join('\t') + '\n'
	os.write_file(registry_path, registry)!
	os.chmod(registry_path, 0o444)!
	for name in ['service-data', 'service-home', 'client-data', 'client-home'] {
		owned_directory(output + '/' + name, uid, gid)!
	}
	mut pins := map[string]string{}
	for path in [runtime + '/usr/bin/run-android', runtime + '/usr/bin/vinix-android-native',
		runtime + '/usr/lib/art/libvinix-android-native.so', runtime + '/usr/lib/libvinix-android-account.so',
		runtime + '/usr/lib/java/dex/android_translation_layer/api-impl.jar', apk, registry_path, os.executable()] {
		pins[path] = digest(path)!
	}
	config := Configuration{runtime, apk, registry_path, output, uid, gid}
	mut cases := []CaseReceipt{}
	cases << run_case(config, false)!
	cases << run_case(config, true)!
	for path, pin in pins { require(digest(path)! == pin, 'input changed: ' + path)! }
	os.write_file(output + '/receipt.json', json2.encode(Receipt{
		created_utc: time.utc().str()
		uid: uid
		gid: gid
		inputs_sha256: pins
		cases: cases
	}, prettify: true) + '\n')!
	export_evidence(output)!
	println('ACCOUNT-TOKEN-CACHE-CONTROLLER-PASS real-ART JNI SQLite authenticated-broker ordinary-client password-clear restart-durability')
	println('ACCOUNT-TOKEN-CACHE-CONTROLLER-RECEIPT ' + digest(output + '/receipt.json')!)
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or { eprintln(err); exit(1) }
		return
	}
	run() or { eprintln(err); exit(1) }
}
