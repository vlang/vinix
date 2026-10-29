// SPDX-License-Identifier: GPL-2.0-or-later
// Standalone child-attach / Settings.Global ART regressions. No account IPC.
module main

import crypto.sha256
import encoding.base64
import json2
import os
import time

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pwd.h>
#include <signal.h>
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
fn C.close(i32) i32
fn C.chown(&char, i32, i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.kill(i32, i32) i32
fn C._exit(i32)
fn C.fcntl(i32, i32, ...i32) i32
fn C.open(&char, i32, ...voidptr) i32

// Sealed child-attach + Settings.Global successor; signed fixture identities below.
const framework_sha = 'e7d7d590da1ae5f9eb8f9f27aae0c003a30f10f5d79effc0c63f463f958263fd'
const ready_marker = 'ANDROID-WS-READY backend=vinix-native'
// Existing two-file generic fixture wire format, accepted by the reconstructor.
const serial_prefix = 'VINIX-SERVICE-QUERY-RESULTS-1 '
const log_limit = 4 * 1024 * 1024
const line_limit = 8192
const auth_worker_native_sha = '0ef0acd98c148b9b972f754e5fb1e23683e8dc7d0b56f05d2f0a4c7792206136'

struct FixtureProfile {
	name          string
	apk_sha       string
	framework_sha string
	native_sha    string
	pass_marker   string
	scope         string = 'standalone generic framework contract fixture; Google login and SettingsProvider persistence are not exercised'
}

fn child_attach_profile() FixtureProfile {
	return FixtureProfile{
		name: 'child-attach'
		apk_sha: '27869d74fd03598dda9b75b740cbaf2efcc423ee0c5ff3b2f447d22ade9f999e'
		framework_sha: framework_sha
		pass_marker: 'CHILD-ATTACH-PASS fresh-once repeated-once remove-no-orphan detached-reattach-order params-parent'
	}
}

fn settings_global_profile() FixtureProfile {
	return FixtureProfile{
		name: 'settings-global'
		apk_sha: 'c3e912e4e05c2af28d6d64d1fcb46874136a6164f7e2e19cc5ba1b62d950fedd'
		framework_sha: framework_sha
		pass_marker: 'SETTINGS-GLOBAL-PASS linkage virtual-insert URI exact-string-values zero negative min max repeated-key null-result SQLException SecurityException-identity absent-provider'
	}
}

fn application_restrictions_profile() FixtureProfile {
	return FixtureProfile{
		name: 'application-restrictions'
		apk_sha: '1fcd38978709198743aa9127b14f02bbebbf55e1f4d7793cd03270f3c3c25a07'
		framework_sha: 'd4e8678bf5deda99358defd912e64e4fcba92fec4ad3b87b39fc9f7e9f6ebf32'
		pass_marker: 'APPLICATION-RESTRICTIONS-PASS own-package nonnull empty fresh-bundles missing-string-array mutation-isolation repeated-32'
	}
}

fn authenticator_exception_profile() FixtureProfile {
	return FixtureProfile{
		name: 'authenticator-private-exception'
		apk_sha: 'c4e78b7c46d2d35f63d60bb8d45c3964ede94553f63e3cca9d0bebbcd261a941'
		framework_sha: '0daae54d7755b255ed3335f58d8cafd6da4d03c8c95343ebb0f174d166da6916'
		native_sha: 'cce3eb926d3bc8b2b3c9e9a4f0d42cc4ab6bfdc23b0532beb2c42f5f9b384791'
		pass_marker: 'AUTHENTICATOR-BASE-PASS fourteen-dispatch permission-denied-before-dispatch result error-mapping async-null label default-removal default-cloning default-sessions suggested-false no-account-registration'
	}
}

fn maps_network_profile() FixtureProfile {
	return FixtureProfile{
		name: 'maps-network-observations'
		apk_sha: 'f66dfd858b52c1b7da9c2bac635106cc33a956a425860b86527cdc909e88ad43'
		framework_sha: '0daae54d7755b255ed3335f58d8cafd6da4d03c8c95343ebb0f174d166da6916'
		native_sha: 'cce3eb926d3bc8b2b3c9e9a4f0d42cc4ab6bfdc23b0532beb2c42f5f9b384791'
		pass_marker: 'MAPS-NETWORK-PASS observations-complete'
		scope: 'standalone credential-free network observations; completion does not establish DNS, TCP, TLS or Google login success; validate the finite observation sequence separately'
	}
}

fn authenticator_worker_profile() FixtureProfile {
	base := authenticator_exception_profile()
	return FixtureProfile{
		...base
		name: 'authenticator-worker-private-exception'
		native_sha: auth_worker_native_sha
	}
}

fn maps_network_v2_profile() FixtureProfile {
	base := maps_network_profile()
	return FixtureProfile{
		...base
		name: 'maps-network-tls-v2-observations'
		apk_sha: 'abfa8127b920dd7156d3cdee056a98d725411c6b5b2f8cb081149393c0b9c051'
		native_sha: auth_worker_native_sha
		pass_marker: 'MAPS-NETWORK-V2-PASS observations-complete'
	}
}

struct Configuration {
	runtime   string
	apk       string
	output    string
	uid       u32
	gid       u32
	profile   FixtureProfile
}

struct Receipt {
	kind             string = 'vinix-onboarding-api-runtime-v1'
	created_utc      string
	profile          string
	uid              u32
	gid              u32
	child_pid        i32
	wait_status      i32
	startup_seconds  int = 180
	shutdown_seconds int = 20
	log_limit_bytes  int = log_limit
	input_sha256     map[string]string
	log_sha256       string
	checks           []string
	scope            string = 'standalone generic framework contract fixture; Google login and SettingsProvider persistence are not exercised'
}

struct EvidenceEntry {
	path   string
	kind   string = 'regular'
	mode   u32    = 0o600
	size   u64
	sha256 string
	data   string
}

struct EvidenceArchive {
	version   int = 1
	root_mode u32 = 0o755
	entries   []EvidenceEntry
}

fn require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn canonical(path string) bool {
	return path.starts_with('/') && path.len > 1 && !path.ends_with('/')
		&& !path.contains('\\') && !path.contains('\x00')
		&& path.bytes().all(it >= 32 && it != 127)
		&& path.split('/')[1..].all(it !in ['', '.', '..'])
}

fn digest(path string) !string {
	info := os.lstat(path)!
	require(info.get_filetype() == .regular && info.nlink == 1, 'single-link regular input: ' + path)!
	mut input := os.open(path)!
	defer { input.close() }
	mut hash := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := input.read(mut bytes) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		hash.write(bytes[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn protected_parents(path string) ! {
	require(canonical(path), 'canonical absolute path')!
	parts := path.split('/')
	mut current := '/'
	for part in parts[1..parts.len - 1] {
		current = current.trim_right('/') + '/' + part
		info := os.lstat(current)!
		require(info.get_filetype() == .directory && info.uid == 0 && info.mode & 0o022 == 0
			&& info.mode & 0o001 != 0, 'root-protected, target-traversable ancestors: ' + current)!
	}
}

fn input_pin(path string) !string {
	protected_parents(path)!
	info := os.lstat(path)!
	require(info.uid == 0 && info.mode & 0o022 == 0, 'root-protected input: ' + path)!
	return digest(path)
}

fn owned_directory(path string, config Configuration) ! {
	os.mkdir(path, mode: 0o700)!
	os.chmod(path, 0o700)!
	require(unsafe { C.chown(&char(path.str), int(config.uid), int(config.gid)) } == 0, 'chown fixture directory')!
}

fn health(line string, expected_marker string) ! {
	for bad in ['-FAIL', 'FATAL EXCEPTION', 'JNI DETECTED ERROR', 'JNI exception', 'VerifyError',
		'Exception in thread', 'Abort message:', 'AssertionError', 'NoSuchMethodError',
		'NoSuchFieldError', 'ClassNotFoundException', 'NoClassDefFoundError', 'Exception:', 'Error:',
		'SIGABRT', 'SIGSEGV', 'panic:'] {
		if line.contains(bad) { return error('child failure marker: ' + bad) }
	}
	if (line.contains('CHILD-ATTACH-PASS') || line.contains('SETTINGS-GLOBAL-PASS')
		|| line.contains('APPLICATION-RESTRICTIONS-PASS') || line.contains('AUTHENTICATOR-BASE-PASS')
		|| line.contains('MAPS-NETWORK-PASS') || line.contains('MAPS-NETWORK-V2-PASS')) && line != expected_marker {
		return error('conflicting fixture marker')
	}
}

fn is_ready(line string) bool {
	return line == ready_marker || line.starts_with(ready_marker + ' ')
}

fn check_log(text string, expected_marker string) ! {
	require(text.len <= log_limit && text.ends_with('\n'), 'bounded complete child log')!
	lines := text.split_into_lines()
	require(lines.filter(it == expected_marker).len == 1 && text.count(expected_marker) == 1, 'exact fixture pass once')!
	require(lines.filter(is_ready(it)).len == 1, 'native WS readiness once')!
	for line in lines {
		require(line.len <= line_limit, 'bounded child line')!
		health(line, expected_marker)!
	}
}

fn write_all(fd i32, bytes []u8) ! {
	mut sent := 0
	for sent < bytes.len {
		n := unsafe { C.write(fd, bytes[sent..].data, uint(bytes.len - sent)) }
		if n < 0 && C.errno == C.EINTR { continue }
		require(n > 0, 'output write')!
		sent += int(n)
	}
}

fn pipe() ![2]i32 {
	mut pair := [2]i32{}
	require(C.pipe(&pair[0]) == 0, 'create fixture pipe')!
	for fd in pair {
		if C.fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) < 0 {
			C.close(pair[0])
			C.close(pair[1])
			return error('protect fixture pipe')
		}
	}
	return pair
}

fn spawn_child(config Configuration, input [2]i32, output [2]i32) !i32 {
	// Enumerate before fork; all inherited descriptors except duplicated stdio
	// are closed, including unrelated app/account/browser channels.
	mut inherited := []i32{}
	for name in os.ls('/proc/self/fd')! {
		require(name.len > 0 && name.bytes().all(it >= `0` && it <= `9`), 'numeric /proc/self/fd entry')!
		if name.int() >= 3 { inherited << i32(name.int()) }
	}
	child := C.fork()
	require(child >= 0, 'fork fixture')!
	if child != 0 { return child }
	if C.setpgid(0, 0) != 0 || C.dup2(input[0], 0) < 0
		|| C.dup2(output[1], 1) < 0 || C.dup2(output[1], 2) < 0 {
		C._exit(126)
	}
	for fd in inherited { C.close(fd) }
	environment := ['PATH=/usr/bin:/bin', 'HOME=' + config.output + '/home',
		'VINIX_ANDROID_ROOT=' + config.runtime, 'VINIX_ANDROID_HOME=' + config.output + '/home',
		'VINIX_ANDROID_UID=' + config.uid.str(), 'VINIX_ANDROID_GID=' + config.gid.str(),
		'ANDROID_APP_DATA_DIR=' + config.output + '/data',
		'VINIX_INPUT_FD=0',
		'VINIX_SURFACE_PATH=' + config.output + '/data/probe.surface']
	os.execve(config.runtime + '/usr/bin/run-android', [config.output + '/client.apk', '-l',
		'org/vinix/bootstrap/Main', '-w', '64', '-h', '64'], environment) or { C._exit(127) }
	C._exit(127)
	return i32(-1)
}

fn execute(config Configuration) !i32 {
	for fd in 0 .. 3 { require(C.fcntl(i32(fd), C.F_GETFD) >= 0, 'open controller stdio')! }
	input := pipe()!
	mut input_writer := input[1]
	defer { if input_writer >= 0 { C.close(input_writer) } }
	output := pipe() or {
		C.close(input[0])
		return err
	}
	defer { C.close(output[0]) }
	mut log := os.create(config.output + '/child.log') or {
		C.close(input[0])
		C.close(output[1])
		return err
	}
	defer { log.close() }
	os.chmod(config.output + '/child.log', 0o600)!
	pid := spawn_child(config, input, output) or {
		C.close(input[0])
		C.close(output[1])
		return err
	}
	C.close(input[0])
	C.close(output[1])
	mut reaped := false
	defer {
		if !reaped {
			// The direct child remains unreaped until pipe EOF. Its PID cannot be
			// reused, so failure cleanup owns both this process and its group.
			C.kill(-pid, C.SIGKILL)
			C.kill(pid, C.SIGKILL)
			mut status := i32(0)
			for {
				waited := C.waitpid(pid, &status, 0)
				if waited >= 0 || C.errno != C.EINTR { break }
			}
		}
	}
	flags := C.fcntl(output[0], C.F_GETFL, 0)
	require(flags >= 0 && C.fcntl(output[0], C.F_SETFL, flags | C.O_NONBLOCK) >= 0, 'nonblocking fixture output')!
	mut buffer := [4096]u8{}
	mut line := []u8{cap: line_limit}
	mut total := 0
	mut passed := 0
	mut ready := 0
	mut deadline := time.sys_mono_now() + u64(180 * time.second)
	mut status := i32(0)
	for {
		require(time.sys_mono_now() < deadline, 'fixture startup/shutdown deadline')!
		n := unsafe { C.read(output[0], &buffer[0], buffer.len) }
		if n > 0 {
			total += int(n)
			require(total <= log_limit, 'child output exceeds 4 MiB')!
			write_all(i32(log.fd), buffer[..int(n)])!
			for byte in buffer[..int(n)] {
				if byte != `\n` {
					require(line.len < line_limit, 'child line exceeds 8192 bytes')!
					line << byte
					continue
				}
				text := line.bytestr()
				health(text, config.profile.pass_marker)!
				if text == config.profile.pass_marker { passed++ }
				if is_ready(text) { ready++ }
				require(passed <= 1 && ready <= 1, 'duplicate pass/readiness marker')!
				line.clear()
			}
			if input_writer >= 0 && passed == 1 && ready == 1 {
				C.close(input_writer)
				input_writer = -1
				deadline = time.sys_mono_now() + u64(20 * time.second)
				println('ONBOARDING-API-RUN-STDIN-CLOSED reason=ready-and-pass')
			}
			continue
		}
		if n < 0 { require(C.errno in [C.EAGAIN, C.EWOULDBLOCK, C.EINTR], 'child output read')! }
		if n == 0 {
			waited := C.waitpid(pid, &status, C.WNOHANG)
			require(waited == 0 || waited == pid || (waited < 0 && C.errno == C.EINTR), 'wait for fixture child')!
			if waited == pid {
				reaped = true
				break
			}
		}
		time.sleep(10 * time.millisecond)
	}
	require(line.len == 0 && passed == 1 && ready == 1 && input_writer == -1 && status == 0,
		'exact fixture markers, complete output, stdin shutdown and clean child exit')!
	check_log(os.read_file(config.output + '/child.log')!, config.profile.pass_marker)!
	println('ONBOARDING-API-RUN-EXIT status=' + status.str())
	return pid
}

fn serial_frame(fd i32, frame string) ! {
	require(frame.len < 1024 && frame.ends_with('\n'), 'bounded serial frame')!
	mut n := i64(-1)
	for {
		n = unsafe { C.write(fd, frame.str, uint(frame.len)) }
		if n < 0 && C.errno == C.EINTR { continue }
		break
	}
	require(n == frame.len, 'atomic serial frame')!
}

fn export_evidence(output string) ! {
	mut entries := []EvidenceEntry{}
	for name in ['receipt.json', 'child.log'] {
		path := output + '/' + name
		require(os.file_size(path) <= log_limit, 'bounded evidence file')!
		bytes := os.read_bytes(path)!
		entries << EvidenceEntry{ path: name, size: u64(bytes.len), sha256: sha256.sum(bytes).hex(), data: base64.encode(bytes) }
	}
	payload := json2.encode(EvidenceArchive{ entries: entries })
	require(payload.len <= 6 * 1024 * 1024, 'bounded evidence archive')!
	fd := unsafe { C.open(c'/dev/console', C.O_WRONLY | C.O_NOCTTY | C.O_CLOEXEC) }
	require(fd >= 0, 'open evidence console')!
	defer { C.close(fd) }
	sha := sha256.sum(payload.bytes()).hex()
	shape := sha + ' ' + payload.len.str() + ' ' + ((payload.len + 511) / 512).str() + '\n'
	serial_frame(fd, serial_prefix + 'BEGIN ' + shape)!
	for offset := 0; offset < payload.len; offset += 512 {
		end := if offset + 512 < payload.len { offset + 512 } else { payload.len }
		serial_frame(fd, serial_prefix + 'CHUNK ' + sha + ' ' + (offset / 512).str() + ' ' +
			base64.encode(payload[offset..end].bytes()) + '\n')!
	}
	serial_frame(fd, serial_prefix + 'END ' + shape)!
}

fn selftest() ! {
	mut cases := 0
	profiles := [child_attach_profile(), settings_global_profile(), application_restrictions_profile(), authenticator_exception_profile(), maps_network_profile(), authenticator_worker_profile(), maps_network_v2_profile()]
	require(child_attach_profile().framework_sha == framework_sha
		&& settings_global_profile().framework_sha == framework_sha
		&& application_restrictions_profile().framework_sha != framework_sha, 'exact per-profile framework identities')!
	require(authenticator_exception_profile().framework_sha == '0daae54d7755b255ed3335f58d8cafd6da4d03c8c95343ebb0f174d166da6916'
		&& authenticator_exception_profile().native_sha == 'cce3eb926d3bc8b2b3c9e9a4f0d42cc4ab6bfdc23b0532beb2c42f5f9b384791', 'exact diagnostic runtime identities')!
	require(maps_network_profile().framework_sha == authenticator_exception_profile().framework_sha
		&& maps_network_profile().native_sha == authenticator_exception_profile().native_sha, 'network observations use the same pinned runtime')!
	require(authenticator_worker_profile().native_sha == maps_network_v2_profile().native_sha
		&& authenticator_worker_profile().native_sha != authenticator_exception_profile().native_sha
		&& maps_network_v2_profile().framework_sha == maps_network_profile().framework_sha
		&& maps_network_v2_profile().apk_sha != maps_network_profile().apk_sha, 'worker and TLS-v2 identities are distinct opt-ins')!
	for profile in profiles {
		mut pins := [profile.apk_sha, profile.framework_sha]
		if profile.native_sha != '' { pins << profile.native_sha }
		for pin in pins {
			require(pin.len == 64 && pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)), 'canonical profile SHA256')!
		}
		good := profile.pass_marker + '\n' + ready_marker + '\n'
		check_log(good, profile.pass_marker)!
		for bad in [good + profile.pass_marker + '\n', good + ready_marker + '\n', good.replace(profile.pass_marker, ''),
			good.replace(ready_marker, ''), good.trim_right('\n'),
			good.replace(profile.pass_marker, profile.pass_marker + ' other'), good + 'JNI exception\n',
			good + 'AssertionError\n', good + 'NoSuchFieldError\n', good + 'ClassNotFoundException\n',
			good + 'SIGSEGV\n', good.replace(ready_marker, ready_marker + 'other'),
			good + 'java.lang.IllegalStateException: unexpected\n',
			good + 'x'.repeat(line_limit + 1) + '\n', good + 'x'.repeat(log_limit) + '\n'] {
			mut rejected := false
			check_log(bad, profile.pass_marker) or { rejected = true }
			require(rejected, 'checker accepted invalid log')!
			cases++
		}
		for other in profiles {
			if other.name == profile.name { continue }
			// The worker regression uses the same APK on a different pinned
			// native runtime. Its log marker alone cannot identify that runtime.
			if other.pass_marker == profile.pass_marker {
				require(other.apk_sha == profile.apk_sha && other.framework_sha == profile.framework_sha
					&& other.native_sha != '' && profile.native_sha != '' && other.native_sha != profile.native_sha,
					'shared fixture marker requires distinct pinned native runtimes')!
				continue
			}
			mut rejected := false
			check_log(good, other.pass_marker) or { rejected = true }
			require(rejected, 'checker accepted another profile marker')!
			cases++
			rejected = false
			check_log(good + other.pass_marker + '\n', profile.pass_marker) or { rejected = true }
			require(rejected, 'checker accepted mixed profile markers')!
			cases++
		}
	}
	for path in ['relative', '/', '/a/', '/a//b', '/a/../b', '/a/./b', '/a\\b', '/a\x00b'] {
		require(!canonical(path), 'checker accepted noncanonical path')!
		cases++
	}
	require(canonical('/var/lib/onboarding-api-r1'), 'canonical path rejected')!
	println('ONBOARDING-API-RUN-SELFTEST-PASS rejected=' + cases.str())
}

fn run() ! {
	if os.args.len == 2 && os.args[1] == 'selftest' {
		selftest()!
		return
	}
	mut arguments := os.args[1..]
	require(arguments.len == 6 && arguments[0] in ['--child-attach', '--settings-global', '--application-restrictions', '--authenticator-private-exception', '--maps-network', '--authenticator-worker', '--maps-network-v2'],
		'usage: onboarding-api-run (--child-attach|--settings-global|--application-restrictions|--authenticator-private-exception|--maps-network|--authenticator-worker|--maps-network-v2) RUNTIME APK UID GID FRESH_OUTPUT | selftest')!
	profile := if arguments[0] == '--authenticator-private-exception' { authenticator_exception_profile() }
		else if arguments[0] == '--authenticator-worker' { authenticator_worker_profile() }
		else if arguments[0] == '--maps-network-v2' { maps_network_v2_profile() }
		else if arguments[0] == '--maps-network' { maps_network_profile() }
		else if arguments[0] == '--application-restrictions' { application_restrictions_profile() }
		else if arguments[0] == '--child-attach' { child_attach_profile() } else { settings_global_profile() }
	arguments = arguments[1..]
	require(canonical(arguments[0]), 'canonical runtime path')!
	$if !linux {
		return error('runtime fixture requires Linux/Vinix')
	}
	require(C.getuid() == 0 && C.geteuid() == 0, 'fixture controller requires root')!
	for value in arguments[2..4] {
		require(value.len == 5 && value.bytes().all(it >= `0` && it <= `9`)
			&& value.int() >= 10000 && value.int() <= 19999, 'fixture UID/GID in 10000..19999')!
	}
	config := Configuration{
		runtime:   arguments[0]
		apk:       arguments[1]
		uid:       arguments[2].u32()
		gid:       arguments[3].u32()
		output:    arguments[4]
		profile:   profile
	}
	require(C.getpwuid(config.uid) != unsafe { nil } && C.getgrgid(config.gid) != unsafe { nil }, 'pre-provisioned fixture user/group')!
	protected_parents(config.output)!
	require(!os.exists(config.output) && !os.is_link(config.output), 'fresh fixture output')!
	require(input_pin(config.apk)! == config.profile.apk_sha, 'signed fixture APK pin')!
	framework := config.runtime + '/usr/lib/java/dex/android_translation_layer/api-impl.jar'
	require(input_pin(framework)! == config.profile.framework_sha, 'corrected framework JAR pin')!
	mut inputs := map[string]string{}
	for path in [config.apk, framework, config.runtime + '/usr/bin/run-android',
		config.runtime + '/usr/bin/vinix-android-native', os.executable()] {
		inputs[path] = input_pin(path)!
	}
	if config.profile.native_sha != '' {
		native := config.runtime + '/usr/lib/art/libvinix-android-native.so'
		inputs[native] = input_pin(native)!
		require(inputs[native] == config.profile.native_sha, 'corrected native library pin')!
	}
	os.mkdir(config.output, mode: 0o755)!
	os.chmod(config.output, 0o755)!
	for name in ['data', 'home'] { owned_directory(config.output + '/' + name, config)! }
	os.cp(config.apk, config.output + '/client.apk')!
	os.chmod(config.output + '/client.apk', 0o444)!
	require(digest(config.output + '/client.apk')! == config.profile.apk_sha, 'staged fixture APK pin')!
	println('ONBOARDING-API-RUN-BEGIN profile=' + config.profile.name + ' uid=' + config.uid.str() + ' gid=' + config.gid.str())
	pid := execute(config)!
	for path, pin in inputs { require(input_pin(path)! == pin, 'input unchanged after ART run')! }
	require(digest(config.output + '/client.apk')! == config.profile.apk_sha, 'staged APK unchanged after ART run')!
	log_sha := digest(config.output + '/child.log')!
	receipt := Receipt{
		created_utc:  time.utc().format_rfc3339()
		profile:      config.profile.name
		uid:          config.uid
		gid:          config.gid
		child_pid:    pid
		input_sha256: inputs
		log_sha256:   log_sha
		scope:        config.profile.scope
		checks:       ['exact-pass-once', 'native-ws-ready-once', 'bounded-log-and-lines',
			'live-input-until-pass-and-ready', 'drained-through-eof', 'clean-exit',
			'isolated-unix-identity-data-home-surface', 'standalone-explicit-activity',
			'explicit-environment-no-account-browser-channels', 'closed-inherited-descriptors',
			'unchanged-pinned-inputs']
	}
	os.write_file(config.output + '/receipt.json', json2.encode(receipt, prettify: true))!
	os.chmod(config.output + '/receipt.json', 0o600)!
	export_evidence(config.output)!
	println('ONBOARDING-API-RUN-PASS receipt=' + config.output + '/receipt.json')
}

fn main() {
	run() or {
		eprintln('ONBOARDING-API-RUN-FAIL ' + err.msg())
		exit(1)
	}
}
