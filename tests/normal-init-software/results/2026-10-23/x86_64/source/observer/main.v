// SPDX-License-Identifier: GPL-2.0-or-later
// Optional version-check helper: observes production init, never replaces it.
// Account and package mutations are exclusively driven by graphical input.
module main

import crypto.sha256
import json2
import os
import time

#include <fcntl.h>
#include <unistd.h>
fn C.open(&char, int, ...int) int
fn C.dup2(int, int) int
fn C.close(int) int
fn C.geteuid() u32

const prefix = 'NORMAL INIT SOFTWARE '
const image_id = 'vinix-normal-init-software-1'
const declaration = '/usr/share/normal-init-software.json'
const checkpoint = '/root/normal-init-software-checkpoint.json'
const counter = '/home/alex/.local/share/vinix-apps/org.vinix.counter/counter.txt'
const launcher = '/var/lib/vinix-packages/current/share/applications/vinix-org.vinix.counter.desktop'

struct FileIdentity {
	path string
	sha256 string
	uid u32
	gid u32
	mode u32
}

struct Checkpoint {
	current string
	files []FileIdentity
}

fn discard(err IError) { unsafe { err.free() } }

fn contents(path string) string {
	return os.read_file(path) or { discard(err); '' }
}

fn file_equals(path string, expected string) bool {
	text := contents(path)
	defer { unsafe { text.free() } }
	return text == expected
}

// Parse proc's decimal identity fields directly from the owned status buffer.
// No split/substring allocations occur on this repeated polling path.
fn status_numbers(info string, key string, wanted u32, count int) bool {
	mut start := 0
	for start < info.len {
		mut end := start
		for end < info.len && info[end] != `\n` { end++ }
		mut matches := end - start >= key.len
		for i in 0 .. key.len { if start + i >= end || info[start + i] != key[i] { matches = false; break } }
		if matches {
			mut at := start + key.len
			for _ in 0 .. count {
				for at < end && info[at] in [` `, `\t`] { at++ }
				begin := at
				mut number := u64(0)
				for at < end && info[at] >= `0` && info[at] <= `9` {
					number = number * 10 + u64(info[at] - `0`)
					if number > 0xffffffff { return false }
					at++
				}
				if begin == at || number != u64(wanted) { return false }
			}
			for at < end && info[at] in [` `, `\t`] { at++ }
			return at == end
		}
		start = end + 1
	}
	return false
}

fn identity(path string) !FileIdentity {
	text := os.read_file(path)!
	defer { unsafe { text.free() } }
	info := os.stat(path)!
	return FileIdentity{path: path, sha256: sha256.hexhash(text), uid: info.uid,
		gid: info.gid, mode: info.mode & 0o7777}
}

fn process_text(pid string, name string) string {
	path := '/proc/' + pid + '/' + name
	defer { unsafe { path.free() } }
	return contents(path)
}

fn process(expected string, uid u32, parent int) int {
	entries := os.ls('/proc') or { discard(err); return 0 }
	defer { unsafe { entries.free() } }
	for entry in entries {
		if entry.int() <= 1 { continue }
		command := process_text(entry, 'cmdline')
		matched := command == expected
		unsafe { command.free() }
		if !matched { continue }
		info := process_text(entry, 'status')
		defer { unsafe { info.free() } }
		if info.contains('State:\tZ (zombie)') || info.contains('State:\tT (stopped)') { continue }
		if status_numbers(info, 'Uid:', uid, 4) && (parent == 0 || status_numbers(info, 'PPid:', u32(parent), 1)) {
			return entry.int()
		}
	}
	return 0
}

fn until(deadline i64, condition fn () bool) ! {
	for time.sys_mono_now() < deadline {
		if condition() { return }
		time.sleep(100 * time.millisecond)
	}
	return error('observer deadline expired')
}

fn root_admission() !bool {
	if C.geteuid() != 0 || os.getpid() <= 1 || os.getppid() != 1 {
		return error('observer must be a root optional helper of the real PID 1')
	}
	for name, expected in {'HOME':'/root', 'USER':'root', 'VINIX_SYSTEM_SESSION':'1'} {
		actual := os.getenv(name)
		matched := actual == expected
		unsafe { actual.free() }
		if !matched { return error('production init environment differs: ' + name) }
	}
	image := contents('/.vinix-image-id')
	trimmed_image := image.trim_space()
	defer { unsafe { trimmed_image.free(); image.free() } }
	// sysdisk pads the old image-id length with spaces when it commits.
	if trimmed_image != image_id { return error('unexpected installed image') }
	root := os.stat('/')!
	mounts := contents('/proc/mounts')
	defer { unsafe { mounts.free() } }
	if root.dev == 0 || !mounts.contains('/dev/root / ext2 ') {
		return error('production init did not use the installer-selected disk root')
	}
	proof := json2.decode[map[string]string](os.read_file(declaration)!)!
	for path, expected in proof {
		if path.starts_with('@link:') {
			link_path := unsafe { tos(path.str + 6, path.len - 6) }
			info := os.lstat(link_path)!
			if info.dev != root.dev || info.uid != 0 || info.gid != 0 || info.mode & 0o170000 != 0o120000
				|| os.readlink(link_path)! != expected { return error('installed image alias identity differs: ' + link_path) }
			continue
		}
		info := os.lstat(path)!
		if info.dev != root.dev || info.uid != 0 || info.gid != 0 || info.mode & 0o170000 != 0o100000
			|| info.mode & 0o022 != 0 || (identity(path)!).sha256 != expected {
			return error('installed image input identity differs: ' + path)
		}
	}
	$if arm64 {
		executable := os.readlink('/proc/1/exe')!
		if executable != '/sbin/init' { return error('ARM PID 1 is not the production freestanding init') }
	} $else {
		command := contents('/proc/1/cmdline')
		defer { unsafe { command.free() } }
		if !command.contains('/sbin/init\x00') { return error('x86 PID 1 did not execute the production init script') }
	}
	if !os.exists('/usr/sbin/vinix-volume') { return error('production boot-restore helper is absent') }
	for path in ['/etc/vinix/volumes.vmap','/etc/vinix/volumes.vset','/etc/vinix/volumes.d',
		'/etc/vinix/boot-volume.vcrypt','/etc/vinix/boot-volumes.d'] {
		if os.exists(path) || os.is_link(path) { return error('fixture expects no configured extra-volume restore plan') }
	}
	fresh := !os.exists(checkpoint)
	if !fresh {
		previous := json2.decode[Checkpoint](os.read_file(checkpoint)!)!
		if os.readlink('/var/lib/vinix-packages/current')! != previous.current {
			return error('package generation changed across cold boot')
		}
		for file in previous.files {
			if identity(file.path)! != file || (os.stat(file.path)!).dev != root.dev {
				return error('cold boot changed exact accounts trust state or private data: ' + file.path)
			}
		}
		println(prefix + 'BOOT 2 exact accounts trust state private-data retained PASS')
	} else {
		passwd := contents('/etc/passwd')
		defer { unsafe { passwd.free() } }
		if os.exists('/root/.vinix-user') || passwd.contains('alex:')
			|| os.exists('/var/lib/vinix-packages/current') || os.is_link('/var/lib/vinix-packages/current') {
			return error('first boot requires fresh registration and package state')
		}
	}
	println(prefix + 'production PID1 installed disk inputs boot-restore-present PASS')
	return fresh
}

fn approvals() !int {
	text := contents('/var/log/vinix/auth.log')
	defer { unsafe { text.free() } }
	if text.contains('loginpass') { return error('password appeared in authentication audit') }
	return text.count('uid=1000 run packages-change as alex: exit 0')
}

fn state_text() string { return contents('/var/lib/vinix-packages/current/state.json') }

fn data(value string) !FileIdentity {
	file := identity(counter)!
	path := os.dir(counter)
	defer { unsafe { path.free() } }
	directory := os.lstat(path)!
	text := contents(counter)
	defer { unsafe { text.free() } }
	if text != value || file.uid != 1000 || file.gid != 1000 || directory.uid != 1000
		|| directory.gid != 1000 || directory.mode & 0o777 != 0o700 {
		return error('Counter private data ownership mode or exact value differs')
	}
	return file
}

fn command(arguments []string) !string {
	mut child := os.new_process('/usr/bin/vinix-package')
	defer { child.close() }
	child.set_args(arguments)
	child.set_redirect_stdio()
	child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	diagnostic := child.stderr_slurp()
	defer { unsafe { diagnostic.free() } }
	child.wait()
	if child.code != 0 || output.len > 1024 * 1024 {
		unsafe { output.free() }
		return error('read-only package command failed: ' + diagnostic)
	}
	return output
}

fn verify_state(installed bool, count int) ! {
	output := command(['verify'])!
	defer { unsafe { output.free() } }
	state := json2.decode[json2.Any](state_text())!.as_map()
	configuration := json2.decode[json2.Any](os.read_file('/etc/vinix-packages/config.json')!)!.as_map()
	key := configuration['repositories']!.as_array()[0].as_map()['public_key']!.str()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	if state['architecture']!.str() != architecture || approvals()! != count { return error('architecture or exact approval count differs') }
	packages := state['packages']!.as_array()
	if !installed {
		if packages.len != 0 || state['requested']!.as_array().len != 0 || os.exists(launcher) {
			return error('uninstall retained active package or launcher')
		}
		return
	}
	if packages.len != 1 || state['requested']!.as_array().map(it.str()) != ['org.vinix.counter'] {
		return error('different signed requested package closure activated')
	}
	row := packages[0].as_map()
	package := row['package']!.as_map()
	if row['repository']!.str() != 'native' || row['public_key']!.str() != key
		|| package['id']!.str() != 'org.vinix.counter' || package['version']!.str() != '1.1.0'
		|| package['architecture']!.str() != architecture || package['kind']!.str() != 'native'
		|| package['license']!.str() != 'MIT' || package['permissions']!.as_array().map(it.str()) != ['display']
		|| !contents(launcher).contains('org.vinix.counter') {
		return error('signed package provenance manifest or launcher differs')
	}
}

fn wait_state(installed bool, count int, deadline i64) ! {
	for time.sys_mono_now() < deadline {
		text := state_text()
		matched := if installed { text.contains('"version":"1.1.0"') } else { text.contains('"packages":[]') }
		unsafe { text.free() }
		if matched && approvals()! == count { verify_state(installed, count)!; return }
		time.sleep(100 * time.millisecond)
	}
	return error('graphical package state transition timed out')
}

fn proposal(operation string, count int, value string) ! {
	before := state_text()
	defer { unsafe { before.free() } }
	private := if value != '' { data(value)! } else { FileIdentity{} }
	output := command(['review', operation, 'org.vinix.counter'])!
	defer { unsafe { output.free() } }
	review := json2.decode[json2.Any](output)!.as_map()
	if review['operation']!.str() != operation || review['rows']!.as_array().len != 1
		|| review['fingerprint']!.str().len != 64 || state_text() != before || approvals()! != count
		|| (value != '' && data(value)! != private) { return error('read-only complete proposal changed state') }
	println(prefix + 'PROPOSAL ' + output.trim_space())
	println(prefix + 'review=' + operation + ' unchanged-state approvals=' + count.str() + ' PASS')
}

fn wait_data(value string, deadline i64) ! {
	mut seen := []int{cap: 32}
	seen.flags |= .noslices
	defer { unsafe { seen.free() } }
	mut helper_seen := false
	mut counter_seen := false
	for time.sys_mono_now() < deadline {
		entries := os.ls('/proc')!
		for entry in entries {
			command := process_text(entry, 'cmdline')
			end := command.index_u8(0)
			program := if end >= 0 { unsafe { tos(command.str, end) } } else { command }
			helper := command.starts_with('/usr/bin/vinix-package\x00')
				&& command.contains('\x00run-window\x00org.vinix.counter\x00')
			child := program.ends_with('/bin/counter')
			unsafe { command.free() }
			if !helper && !child { continue }
			status := process_text(entry, 'status')
			ordinary := status_numbers(status, 'Uid:', 1000, 4) && status_numbers(status, 'Gid:', 1000, 4)
			unsafe { status.free() }
			if !ordinary { unsafe { entries.free() }; return error('Counter launch child did not retain ordinary identity') }
			helper_seen = helper_seen || helper
			counter_seen = counter_seen || child
			pid := entry.int()
			if pid !in seen {
				if seen.len == 32 { unsafe { entries.free() }; return error('too many Counter launch child identities') }
				seen << pid
			}
		}
		unsafe { entries.free() }
		text := contents(counter)
		matched := text == value
		unsafe { text.free() }
		if matched && helper_seen && counter_seen {
			data(value)!
			mut alive := false
			for pid in seen {
				digits := pid.str()
				path := '/proc/' + digits
				alive = alive || os.exists(path)
				unsafe { digits.free(); path.free() }
			}
			if !alive {
				println(prefix + 'native Counter and package launch child reaped uid=1000 PASS')
				return
			}
		}
		time.sleep(100 * time.millisecond)
	}
	return error('Counter save or child retirement timed out')
}

fn run() ! {
	println(prefix + 'START optional-helper observer')
	fresh := root_admission()!
	deadline := time.sys_mono_now() + 1200 * time.second
	until(deadline, fn () bool {
		return process('/usr/sbin/vinix-session\x00graphical\x00--desktop\x00/usr/bin/vinix-desktop\x00', 0, 1) > 0
	})!
	manager_lock := os.lstat('/run/vinix/graphical-manager.lock')!
	if manager_lock.uid != 0 || manager_lock.gid != 0 || manager_lock.mode & 0o777 != 0o600 { return error('manager lock is not root private') }
	println(prefix + 'production init direct-child graphical manager root-private-lock PASS')
	if fresh {
		until(deadline, fn () bool { return process('/usr/bin/vinix-desktop\x00--register-only\x00', 0, 0) > 0 })!
		println(prefix + 'exclusive root registration READY')
	}
	until(deadline, fn () bool { return process('/usr/bin/vinix-desktop\x00--greeter\x00', 101, 0) > 0 })!
	if process('/usr/bin/vinix-desktop\x00', 1000, 0) != 0 { return error('ordinary desktop started before login') }
	println(prefix + 'ordinary greeter uid=101 READY')
	until(deadline, fn () bool {
		return process('/usr/bin/vinix-desktop\x00', 1000, 0) > 0
			&& file_equals('/run/user/1000/vinix-desktop-ready', 'ready\n')
			&& file_equals('/run/vinix/session/active', '1000\n')
	})!
	for path in ['/home/alex', '/run/user/1000'] {
		info := os.lstat(path)!
		if info.uid != 1000 || info.gid != 1000 || info.mode & 0o777 != 0o700 { return error('ordinary home/runtime is not private') }
	}
	ready := os.lstat('/run/user/1000/vinix-desktop-ready')!
	if ready.uid != 1000 || ready.gid != 1000 || ready.mode & 0o170000 != 0o100000 || ready.mode & 0o022 != 0 {
		return error('readiness ownership/mode differs')
	}
	println(prefix + 'authenticated ordinary compositor uid=1000 private-home-runtime PASS')
	if fresh {
		for time.sys_mono_now() < deadline {
			if os.exists('/var/lib/vinix-packages/catalog.json') && approvals()! == 1 { break }
			time.sleep(100 * time.millisecond)
		}
		if approvals()! != 1 { return error('graphical refresh was not approved') }
		println(prefix + 'signed catalog refreshed approvals=1 PASS')
		proposal('install', 1, '')!
		wait_state(true, 2, deadline)!
		println(prefix + 'installed signed=1.1.0 approvals=2 PASS')
		wait_data('2', deadline)!
		verify_state(true, 2)!
		mut files := []FileIdentity{}
		for path in ['/etc/passwd','/etc/group','/etc/shadow','/etc/vinix-packages/config.json',
			'/var/lib/vinix-packages/current/state.json','/var/lib/vinix-packages/catalog.json',
			'/var/lib/vinix-packages/trust-history.json',counter] { files << identity(path)! }
		os.write_file(checkpoint, json2.encode(Checkpoint{
			current: os.readlink('/var/lib/vinix-packages/current')!, files: files}) + '\n')!
		println(prefix + 'BOOT 1 signed acquisition private=2 exact checkpoint ready for UI shutdown PASS')
	} else {
		verify_state(true, 2)!
		private := data('2')!
		proposal('remove', 2, '2')!
		wait_state(false, 3, deadline)!
		if data('2')! != private { return error('uninstall changed retained private data') }
		println(prefix + 'uninstalled approvals=3 private=2 launcher-absent PASS')
		proposal('install', 3, '2')!
		wait_state(true, 4, deadline)!
		if data('2')! != private { return error('reinstall changed retained private data') }
		println(prefix + 'reinstalled signed=1.1.0 approvals=4 private=2 PASS')
		wait_data('3', deadline)!
		verify_state(true, 4)!
		println(prefix + 'BOOT 2 exact retention uninstall reinstall private=3 ready for UI shutdown PASS')
	}
}

fn main() {
	// x86 production init intentionally redirects this optional helper to null.
	serial := C.open(c'/dev/com1', C.O_WRONLY)
	if serial >= 0 { C.dup2(serial, 1); C.dup2(serial, 2); if serial > 2 { C.close(serial) } }
	run() or { eprintln(prefix + 'FAIL ' + err.msg()); exit(1) }
}
