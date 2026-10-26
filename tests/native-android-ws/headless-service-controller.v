// SPDX-License-Identifier: GPL-2.0-or-later
// Root Linux/Vinix integration fixture. No credentials or account operations.
module main

import crypto.sha256
import json2
import nativeaccountauth
import os
import time

#include <fcntl.h>
#include <grp.h>
#include <pwd.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.getuid() u32
fn C.geteuid() u32
fn C.getpwuid(u32) voidptr
fn C.getgrgid(u32) voidptr
fn C.fork() i32
fn C.setpgid(i32, i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.dup2(i32, i32) i32
fn C.open(&char, i32, ...voidptr) i32
fn C.close(i32) i32
fn C.chown(&char, i32, i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.kill(i32, i32) i32
fn C._exit(i32)

const fixture_sha256 = '4df9e3cd757b463259c73dc038eb84d149d7ec1461a1889bc8f2d531f6980634'
const fixture_package = 'org.vinix.headless'
const fixture_service = fixture_package + '.ProbeService'
const fixture_action = fixture_package + '.BIND'
const ready_marker = 'HEADLESS-SERVICE-READY application-once main-looper context-order create bind delayed-binder'
const closed_marker = 'HEADLESS-SERVICE-CLOSED unbind destroy main-looper'
const runtime_ready = 'ANDROID-SERVICE-READY package=org.vinix.headless service=org.vinix.headless.ProbeService graphics=absent activity=absent'
const runtime_closed = 'ANDROID-SERVICE-CLOSED unbind destroy'

struct ProbeCase {
	name  string
	frame string
	valid bool
}

struct CaseReceipt {
	name        string
	pid         i32
	wait_status i32
	log_sha256  string
	ready       bool
	closed      bool
}

struct Receipt {
	kind          string = 'vinix-headless-service-controller-v1'
	created_utc   string
	uid           u32
	gid           u32
	inputs_sha256 map[string]string
	cases         []CaseReceipt
	scope         string = 'synthetic lifecycle fixture only; no authenticator dispatch, account, token or Google sign-in'
}

fn require(ok bool, stage string) ! {
	if !ok { return error('headless service controller: ' + stage) }
}

fn digest(path string) !string {
	require(os.lstat(path)!.get_filetype() == .regular, 'regular input: ' + path)!
	mut source := os.open(path)!
	defer { source.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := source.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn protected_output(path string) ! {
	require(path.starts_with('/') && path.len > 1 && !path.ends_with('/')
		&& !path.contains('\\') && !path.contains('\x00')
		&& path.split('/')[1..].all(it != '' && it != '.' && it != '..'), 'canonical output path')!
	require(!os.exists(path), 'fresh output directory')!
	mut parent := '/'
	for name in path.split('/')[1..path.split('/').len - 1] {
		parent = parent.trim_right('/') + '/' + name
		info := os.lstat(parent)!
		require(info.get_filetype() == .directory && info.uid == 0
			&& info.mode & 0o022 == 0, 'root-protected output ancestors')!
	}
	os.mkdir(path, mode: 0o755)!
}

fn read_log(path string) !string {
	require(os.lstat(path)!.size <= 2 * 1024 * 1024, 'bounded child log')!
	return os.read_file(path)
}

fn write_frame(fd i32, frame string) ! {
	mut offset := 0
	for offset < frame.len {
		n := unsafe { C.send(fd, frame.str + offset, uint(frame.len - offset), 0x4000) } // MSG_NOSIGNAL, Linux
		require(n > 0, 'write root launch frame')!
		offset += int(n)
	}
}

fn spawn_child(runtime string, apk string, registry string, output string, uid u32, gid u32, fd i32, other i32, log_fd i32) !i32 {
	child := C.fork()
	require(child >= 0, 'fork child')!
	if child == 0 {
		C.close(other)
		if C.setpgid(0, 0) != 0 || C.dup2(log_fd, 1) != 1 || C.dup2(log_fd, 2) != 2 { C._exit(120) }
		C.close(log_fd)
		input := unsafe { C.open(c'/dev/null', C.O_RDONLY) }
		if input < 0 || C.dup2(input, 0) != 0 { C._exit(121) }
		if input > 2 { C.close(input) }
		for key in ['VINIX_SURFACE_PATH', 'VINIX_INPUT_FD', 'DISPLAY', 'WAYLAND_DISPLAY', 'LD_PRELOAD',
			'LD_LIBRARY_PATH'] {
			os.unsetenv(key)
		}
		os.setenv('VINIX_ANDROID_ROOT', runtime, true)
		os.setenv('VINIX_ANDROID_ACCOUNT_REGISTRY', registry, true)
		os.setenv('VINIX_ANDROID_UID', uid.str(), true)
		os.setenv('VINIX_ANDROID_GID', gid.str(), true)
		os.setenv('ANDROID_APP_DATA_DIR', output + '/data', true)
		os.setenv('VINIX_ANDROID_HOME', output + '/home', true)
		os.execvp(runtime + '/usr/bin/run-android', [apk, '--service-fd', fd.str()]) or {
			eprintln(err)
			C._exit(122)
		}
		C._exit(123)
	}
	return child
}

fn run_case(test ProbeCase, runtime string, apk string, registry string, output string, uid u32, gid u32) !CaseReceipt {
	path := output + '/' + test.name + '.log'
	log_fd := unsafe { C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, 0o644) }
	require(log_fd > 2, 'fresh child log')!
	mut sockets := [2]i32{}
	if C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) != 0 {
		C.close(log_fd)
		return error('headless service controller: socketpair')
	}
	child := spawn_child(runtime, apk, registry, output, uid, gid, sockets[1], sockets[0], log_fd) or {
		C.close(log_fd)
		C.close(sockets[0])
		C.close(sockets[1])
		return err
	}
	C.close(log_fd)
	C.close(sockets[1])
	mut control := sockets[0]
	mut reaped := false
	mut status := i32(-1)
	defer {
		if control >= 0 { C.close(control) }
		if !reaped {
			// This unreaped child owns the process group; its PID cannot be reused.
			C.kill(-child, C.SIGKILL)
			C.kill(child, C.SIGKILL)
			deadline := time.sys_mono_now() + time.second
			for time.sys_mono_now() < deadline {
				if C.waitpid(child, &status, C.WNOHANG) == child { break }
				time.sleep(10 * time.millisecond)
			}
		}
	}
	write_frame(control, test.frame)!
	deadline := time.sys_mono_now() + 120 * time.second
	mut ready := false
	mut closed := false
	for time.sys_mono_now() < deadline {
		text := read_log(path)!
		if test.valid {
			require(!text.contains('-FAIL') && !text.contains('ANDROID-WS-EXIT'), 'child lifecycle failure')!
			if !ready && text.contains(ready_marker + '\n') && text.contains(runtime_ready + '\n') {
				ready = true
				C.close(control)
				control = -1
			}
			closed = text.contains(closed_marker + '\n') && text.contains(runtime_closed + '\n')
		}
		waited := C.waitpid(child, &status, C.WNOHANG)
		require(waited == 0 || waited == child, 'wait child')!
		if waited == child {
			reaped = true
			break
		}
		time.sleep(50 * time.millisecond)
	}
	text := read_log(path)!
	// Mirror exact bounded logs to the serial audit stream, including failures.
	println('HEADLESS-CONTROLLER-LOG-BEGIN ' + test.name)
	print(text)
	println('HEADLESS-CONTROLLER-LOG-END ' + test.name)
	require(reaped, 'child deadline')!
	if test.valid {
		// The final callbacks may run between the last log read and waitpid.
		closed = text.contains(closed_marker + '\n') && text.contains(runtime_closed + '\n')
		require(status == 0 && ready && closed && text.count(ready_marker) == 1
			&& text.count(closed_marker) == 1 && !text.contains('-FAIL'), 'exact lifecycle completion')!
	} else {
		require(status != 0 && text.contains('Android service launch rejected:')
			&& !text.contains(ready_marker) && !text.contains('ANDROID-SERVICE-READY'), 'rejection before runtime entry')!
	}
	return CaseReceipt{test.name, child, status, digest(path)!, ready, closed}
}

fn run() ! {
	$if !linux {
		return error('headless service controller requires Linux/Vinix')
	}
	require(C.getuid() == 0 && C.geteuid() == 0, 'root controller')!
	require(os.args.len == 6, 'usage: headless-service-controller RUNTIME_ROOT FIXTURE_APK UID GID FRESH_OUTPUT')!
	runtime, source, uid_text, gid_text, output := os.args[1], os.args[2], os.args[3], os.args[4], os.args[5]
	for value in [uid_text, gid_text] {
		require(value.len == 5 && value.bytes().all(it >= `0` && it <= `9`)
			&& value.int() >= 10000 && value.int() <= 19999, 'fixture IDs in 10000..19999')!
	}
	uid, gid := uid_text.u32(), gid_text.u32()
	require(C.getpwuid(uid) != unsafe { nil } && C.getgrgid(gid) != unsafe { nil }, 'pre-provisioned fixture Unix account/group')!
	require(os.is_abs_path(runtime) && os.is_abs_path(source), 'absolute runtime and APK paths')!
	require(digest(source)! == fixture_sha256, 'exact synthetic lifecycle APK pin')!
	protected_output(output)!
	apk, registry_path := output + '/fixture.apk', output + '/registry'
	os.cp(source, apk)!
	os.chmod(apk, 0o444)!
	registry_text := 'vinix-android-account-authority-v1\n' + [fixture_package, uid_text, gid_text,
		apk, fixture_sha256, 'b'.repeat(64), fixture_service + '@' + fixture_action].join('\t') + '\n'
	os.write_file(registry_path, registry_text)!
	os.chmod(registry_path, 0o444)!
	registry := nativeaccountauth.load(registry_path)!
	registry.verify_service(apk, uid, gid, fixture_service, fixture_action)!
	for name in ['data', 'home'] {
		path := output + '/' + name
		os.mkdir(path, mode: 0o700)!
		require(unsafe { C.chown(path.str, i32(uid), i32(gid)) } == 0, 'target-owned data and home')!
	}
	mut pins := map[string]string{}
	for path in [runtime + '/usr/bin/run-android', runtime + '/usr/bin/vinix-android-native',
		runtime + '/usr/lib/art/libvinix-android-native.so',
		runtime + '/usr/lib/java/dex/android_translation_layer/api-impl.jar', apk, registry_path,
		os.executable()] {
		pins[path] = digest(path)!
	}
	frame := ['vinix-android-service-host-v1', fixture_package, fixture_service, fixture_action,
		fixture_sha256].join('\t') + '\n'
	mut cases := []CaseReceipt{}
	for test in [
		ProbeCase{'forged-package', frame.replace(fixture_package + '\t', 'org.vinix.forged\t'), false},
		ProbeCase{'extra-frame', frame + frame, false},
		ProbeCase{'lifecycle', frame, true},
	] {
		cases << run_case(test, runtime, apk, registry_path, output, uid, gid)!
	}
	for path, pin in pins { require(digest(path)! == pin, 'input changed during fixture')! }
	os.write_file(output + '/receipt.json', json2.encode(Receipt{
		created_utc:   time.utc().str()
		uid:           uid
		gid:           gid
		inputs_sha256: pins
		cases:         cases
	}, prettify: true) + '\n')!
	println('HEADLESS-SERVICE-CONTROLLER-PASS pre-runtime-rejection root-channel application-once main-looper delayed-binder EOF-unbind destroy exit-zero')
	println('HEADLESS-SERVICE-CONTROLLER-RECEIPT ' + digest(output + '/receipt.json')!)
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
