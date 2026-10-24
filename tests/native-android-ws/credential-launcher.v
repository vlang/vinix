// SPDX-License-Identifier: GPL-2.0-or-later
// Isolated Maps credential experiment. The root compositor retains its input
// pipe and surface connection; only the Android launcher becomes Unix UID 10000.
// This fixture does not establish the production app or notification contract.
module main

import os
import crypto.sha256
import encoding.base64
import time

#include <unistd.h>
#include <grp.h>
#include <sys/mount.h>
#include <pwd.h>

struct C.passwd {
	pw_name &char
	pw_uid  u32
	pw_gid  u32
	pw_dir  &char
}

fn C.getuid() u32
fn C.geteuid() u32
fn C.getresuid(&u32, &u32, &u32) int
fn C.getresgid(&u32, &u32, &u32) int
fn C.setresuid(u32, u32, u32) int
fn C.setresgid(u32, u32, u32) int
fn C.getgroups(int, voidptr) int
fn C.setgroups(usize, voidptr) int
fn C.mount(&char, &char, &char, usize, voidptr) int
fn C.getpwuid(u32) &C.passwd
fn C.fork() int
fn C.close(int) int

const app_uid = u32(10000)
const runtime = '/opt/vinix-android-aarch64'

fn process_snapshot(experiment string, phase string, pid int, status string, maps string) {
	println('MAPS${experiment}-ROOT-WATCH-STATUS-BEGIN pid=${pid} phase=${phase}\n' + status + 'MAPS${experiment}-ROOT-WATCH-STATUS-END')
	println('MAPS${experiment}-ROOT-WATCH-MAPS-BEGIN pid=${pid} phase=${phase}\n' + maps + 'MAPS${experiment}-ROOT-WATCH-MAPS-END')
}

// Opt-in administrator diagnostics for an unchanged launcher. The spectator
// keeps its original root credentials and observes the parent through exec;
// neither the app's input pipe nor its credentials depend on this child.
fn start_root_spectator(experiment string) ! {
	if os.getenv('VINIX_MAPS_ROOT_WATCH') != '1' { return }
	$if linux {
	parent := os.getpid()
	child := C.fork()
	if child < 0 { return error('could not start root process spectator') }
	if child != 0 { return }
	C.close(0)
	println('MAPS${experiment}-ROOT-WATCH-BEGIN pid=${parent} observer=${os.getpid()} uid=${C.getuid()} deadline_ms=15000')
	mut last_maps := ''
	mut last_status := ''
	mut samples := 0
	mut changed := 0
	mut published := 0
	mut last_publication := i64(-250)
	mut reason := 'deadline'
	started := time.now()
	for time.since(started).milliseconds() < 15000 {
		status := os.read_file('/proc/${parent}/status') or {
			reason = 'process-gone'
			break
		}
		maps := os.read_file('/proc/${parent}/maps') or { '' }
		if maps != '' {
			if maps != last_maps {
				changed++
				elapsed := time.since(started).milliseconds()
				// Publish ART's load bases promptly even if the app exits before
				// the final snapshot. Bound serial traffic to four live snapshots.
				if maps.contains('libart.so') && published < 4
					&& elapsed - last_publication >= 250 {
					process_snapshot(experiment, 'live-${published}', parent, status, maps)
					published++
					last_publication = elapsed
				}
			}
			last_maps = maps
			last_status = status
			samples++
		}
		if status.split_into_lines().any(it.starts_with('State:') && it.contains('Z')) {
			reason = 'zombie'
			break
		}
		time.sleep(10 * time.millisecond)
	}
	process_snapshot(experiment, 'final', parent, last_status, last_maps)
	println('MAPS${experiment}-ROOT-WATCH-END pid=${parent} reason=${reason} samples=${samples} changes=${changed} elapsed_ms=${time.since(started).milliseconds()}')
	exit(if samples > 0 { 0 } else { 1 })
	} $else {
		return error('root process spectator requires the Linux-compatible Vinix guest')
	}
}

fn approved_runtime_mount() !string {
	mut found := ''
	for line in os.read_file('/proc/self/mounts')!.split_into_lines() {
		fields := line.fields()
		if fields.len < 4 || fields[1] != runtime { continue }
		if found != '' { return error('duplicate runtime mount entry') }
		options := fields[3].split(',')
		for required in ['ro', 'nosuid', 'nodev', 'wxallowed'] {
			if required !in options { return error('runtime mount lacks ' + required) }
		}
		if 'noexec' in options { return error('approved runtime is not executable') }
		found = line
	}
	if found == '' { return error('approved runtime mount not advertised') }
	return found
}

fn approve_runtime(experiment string) ! {
	$if linux {
	// Use the existing administrator-controlled mount policy. The executable
	// runtime gets its own read-only attachment; ordinary mounts keep W^X.
	for executable in ['/lib/ld-musl-aarch64.so.1', '/usr/bin/vinix-android-native'] {
		resolved := os.real_path(runtime + executable)
		if !resolved.starts_with(runtime + '/') || !os.is_file(resolved) {
			return error('runtime executable escapes dedicated attachment: ' + resolved)
		}
		println('MAPS${experiment}-RUNTIME-EXECUTABLE ' + executable + ' resolved=' + resolved)
	}
	if C.mount(runtime.str, runtime.str, unsafe { nil }, usize(C.MS_BIND), unsafe { nil }) != 0 {
		return error('could not bind the dedicated Android runtime')
	}
	flags := usize(C.MS_BIND | C.MS_REMOUNT | C.MS_RDONLY | C.MS_NOSUID | C.MS_NODEV | C.MS_STRICTATIME)
	if C.mount(c'none', runtime.str, unsafe { nil }, flags, c'wxallowed') != 0 {
		return error('could not authorize runtime mount W^X exception')
	}
	println('MAPS${experiment}-RUNTIME-MOUNT-ADMIN ' + approved_runtime_mount()!)
	} $else {
		return error('runtime approval requires the Linux-compatible Vinix guest')
	}
}

fn own_fixture(path string) ! {
	if os.is_link(path) { return error('symlink in credential fixture: ' + path) }
	if os.is_dir(path) {
		for name in os.ls(path)! { own_fixture(path + '/' + name)! }
	}
	os.chown(path, int(app_uid), int(app_uid))!
	os.chmod(path, 0o700)!
}

struct AccountDatabaseUpdate {
	path    string
	existed bool
	before  string
	after   string
}

fn prepare_database(path string, name string, id_column int, entry string) !AccountDatabaseUpdate {
	existed := os.exists(path)
	before := if existed { os.read_file(path)! } else { '' }
	mut found := false
	for line in before.split_into_lines() {
		if line == '' || line.starts_with('#') { continue }
		columns := line.split(':')
		if columns.len <= id_column || columns[id_column].len == 0
			|| !columns[id_column].bytes().all(it >= `0` && it <= `9`) {
			return error('malformed account database: ' + path)
		}
		if columns[0] == name || columns[id_column].u64() == u64(app_uid) {
			if line != entry || found {
				return error('fixture account name or numeric ID already assigned: ' + path)
			}
			found = true
		}
	}
	separator := if before != '' && !before.ends_with('\n') { '\n' } else { '' }
	after := if found {
		before
	} else {
		before + separator + entry + '\n'
	}
	return AccountDatabaseUpdate{path, existed, before, after}
}

fn prepare_account_databases(passwd string, group string, name string, home string) ![]AccountDatabaseUpdate {
	// Validate both databases before writing either: a group collision must not
	// leave behind a newly appended passwd account.
	return [prepare_database(passwd, name, 2,
		'${name}:x:10000:10000:Maps credential fixture:${home}:/bin/sh')!,
		prepare_database(group, name, 2, '${name}:x:10000:')!]
}

fn publish_databases(updates []AccountDatabaseUpdate, data string, experiment string) ! {
	for update in updates {
		if os.exists(update.path) != update.existed
			|| (update.existed && os.read_file(update.path)! != update.before) {
			return error('account database changed after preflight: ' + update.path)
		}
	}
	for update in updates {
		if update.after != update.before || !update.existed {
			os.write_file(update.path, update.after)!
			if !update.existed { os.chmod(update.path, 0o644)! }
		}
		if os.read_file(update.path)! != update.after || !update.after.starts_with(update.before) {
			return error('account database did not retain original bytes: ' + update.path)
		}
		stem := data + '/credential-' + os.base(update.path)
		os.write_file(stem + '-before.txt', update.before)!
		os.write_file(stem + '-after.txt', update.after)!
		println('MAPS${experiment}-ACCOUNT-DATABASE path=${update.path} original_bytes=${update.before.len} before_sha256=' + sha256.sum(update.before.bytes()).hex() + ' after_sha256=' + sha256.sum(update.after.bytes()).hex() + ' original_prefix=retained')
		// Serial evidence outlives the guest's temporary filesystem. Base64 retains
		// exact database bytes, including a missing final newline in the original.
		println('MAPS${experiment}-ACCOUNT-BYTES path=${update.path} before_base64=' + base64.encode_str(update.before) + ' after_base64=' + base64.encode_str(update.after))
	}
}

fn provision_account(data string, home string, experiment string) ! {
	name := 'maps' + experiment
	publish_databases(prepare_account_databases('/etc/passwd', '/etc/group', name, home)!, data, experiment)!
	account := C.getpwuid(app_uid)
	if account == unsafe { nil } || account.pw_uid != app_uid || account.pw_gid != app_uid
		|| unsafe { cstring_to_vstring(account.pw_name) } != name
		|| unsafe { cstring_to_vstring(account.pw_dir) } != home {
		return error('provisioned passwd account does not resolve to fixture identity')
	}
	println('MAPS${experiment}-ACCOUNT-RESOLVED name=${name} uid=10000 gid=10000 home=${home}')
}

fn account_database_self_test() ! {
	root := os.join_path(os.temp_dir(), 'vinix-account-preflight-' + os.getpid().str())
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	passwd := root + '/passwd'
	group := root + '/group'
	original_passwd := '# retain exact prefix\nroot:x:0:0:root:/root:/bin/sh'
	original_group := 'root:x:0:\n'
	os.write_file(passwd, original_passwd)!
	os.write_file(group, original_group + 'other:x:10000:\n')!
	if _ := prepare_account_databases(passwd, group, 'maps253', '/tmp/home') {
		return error('group ID collision passed preflight')
	}
	if os.read_file(passwd)! != original_passwd
		|| os.read_file(group)! != original_group + 'other:x:10000:\n' {
		return error('failed preflight changed database bytes')
	}
	os.write_file(group, original_group)!
	updates := prepare_account_databases(passwd, group, 'maps253', '/tmp/home')!
	// Recheck every input before the first write, including a group changed
	// after preparation while the passwd input remains valid.
	os.write_file(group, original_group + '# changed\n')!
	if _ := publish_databases(updates, root, 'self-test') {
		return error('changed group database was published')
	}
	if os.read_file(passwd)! != original_passwd {
		return error('changed group caused a passwd write')
	}
	os.write_file(group, original_group)!
	publish_databases(updates, root, 'self-test')!
	for update in prepare_account_databases(passwd, group, 'maps253', '/tmp/home')! {
		if update.after != update.before { return error('account creation is not idempotent') }
	}
	if os.read_file(root + '/credential-passwd-before.txt')! != original_passwd
		|| !os.read_file(passwd)!.starts_with(original_passwd)
		|| os.read_file(root + '/credential-group-before.txt')! != original_group {
		return error('original database provenance changed')
	}
	println('MAPS-ACCOUNT-PREFLIGHT-PASS collision=preserved changed-input=preserved prefix=retained idempotent=true')
}

fn run() ! {
	$if linux {
	if C.getuid() != 0 || C.geteuid() != 0 {
		return error('fixture requires a root guest launcher')
	}
	if os.args.len < 2 || os.args[1] != '/opt/android-test/application.apk' {
		return error('fixture requires the unchanged test APK path')
	}
	experiment := (os.read_file('/opt/android-test/credential-run') or { '251' }).trim_space()
	if experiment !in ['251', '252', '253', '254', '255'] { return error('unsupported credential experiment') }
	fixture_data := '/tmp/maps' + experiment + '-data'
	fixture_home := '/tmp/maps' + experiment + '-home'
	if experiment != '251' { approve_runtime(experiment)! }
	if !os.is_dir(fixture_data) { return error('missing prepared companion data') }
	surface := os.getenv('VINIX_SURFACE_PATH')
	if !surface.starts_with('/tmp/') || surface.contains('/../') || os.exists(surface) {
		return error('fixture requires a fresh surface under /tmp: ' + surface)
	}
	// The guest image mounts /tmp for shared compositor surfaces. Retain that
	// inherited path and stdin; no descriptor or application bytes are replaced.
	os.chmod('/tmp', 0o1777)!
	os.mkdir_all(fixture_home)!
	if experiment in ['253', '254', '255'] { provision_account(fixture_data, fixture_home, experiment)! }
	own_fixture(fixture_data)!
	own_fixture(fixture_home)!
	for key, value in {
		'ANDROID_APP_DATA_DIR': fixture_data
		'HOME':                 fixture_home
		'XDG_DATA_HOME':        fixture_home + '/.local/share'
		'XDG_CONFIG_HOME':      fixture_home + '/.config'
		'XDG_CACHE_HOME':       fixture_home + '/.cache'
		'XDG_STATE_HOME':       fixture_home + '/.local/state'
	} {
		os.setenv(key, value, true)
	}
	if experiment in ['253', '254', '255'] {
		for key, value in {
			'VINIX_ANDROID_UID':  '10000'
			'VINIX_ANDROID_GID':  '10000'
			'VINIX_ANDROID_HOME': fixture_home
			'VINIX_ANDROID_ROOT': runtime
		} {
			os.setenv(key, value, true)
		}
		println('MAPS${experiment}-PRODUCTION-LAUNCH root=${C.getuid()},${C.geteuid()} uid=10000 gid=10000 data=${fixture_data} home=${fixture_home} surface=${surface}')
		if experiment == '254' { os.setenv('VINIX_MAPS_ROOT_WATCH', '1', true) }
		if experiment != '255' { start_root_spectator(experiment)! }
		os.execvp('/usr/bin/run-android-identity', os.args[1..])!
		return
	}
	os.chdir(fixture_data)!
	if C.setgroups(0, unsafe { nil }) != 0 || C.getgroups(0, unsafe { nil }) != 0
		|| C.setresgid(app_uid, app_uid, app_uid) != 0
		|| C.setresuid(app_uid, app_uid, app_uid) != 0 {
		return error('could not drop real/effective/saved credentials')
	}
	mut uids := [3]u32{}
	mut gids := [3]u32{}
	if C.getresuid(&uids[0], &uids[1], &uids[2]) != 0
		|| C.getresgid(&gids[0], &gids[1], &gids[2]) != 0 {
		return error('could not read credential triples')
	}
	for i in 0 .. 3 {
		if uids[i] != app_uid || gids[i] != app_uid {
			return error('credential triples differ from application UID')
		}
	}
	if C.setresuid(0, 0, 0) == 0 {
		return error('dropped process could regain root')
	}
	if C.getresuid(&uids[0], &uids[1], &uids[2]) != 0
		|| C.getresgid(&gids[0], &gids[1], &gids[2]) != 0 {
		return error('could not read credentials after root-regain attempt')
	}
	for i in 0 .. 3 {
		if uids[i] != app_uid || gids[i] != app_uid {
			return error('credentials changed after root-regain attempt')
		}
	}
	for directory in [fixture_data, fixture_home] {
		probe := directory + '/.credential-write-probe'
		os.write_file(probe, 'uid10000 writable\n')!
		if os.read_file(probe)! != 'uid10000 writable\n' {
			return error('application-owned directory probe changed')
		}
		os.rm(probe)!
	}
	status := os.read_file('/proc/self/status')!
	os.write_file(fixture_data + '/credential-status.txt', status)!
	println('MAPS${experiment}-PROC-STATUS-BEGIN\n' + status + 'MAPS${experiment}-PROC-STATUS-END')
	println('MAPS${experiment}-UNIX-UID real=${uids[0]} effective=${uids[1]} saved=${uids[2]} gid=${gids[0]},${gids[1]},${gids[2]} groups=0 regain_root=denied write_probes=pass data=${fixture_data} surface=${surface}')
	if experiment == '252' { println('MAPS252-RUNTIME-MOUNT-APP ' + approved_runtime_mount()!) }
	os.execvp('/usr/bin/run-android-original', os.args[1..])!
	} $else {
		return error('credential launch requires the Linux-compatible Vinix guest')
	}
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--account-self-test' {
		account_database_self_test() or { panic(err) }
		return
	}
	run() or {
		eprintln('MAPS-CREDENTIAL-FAIL: ${err}')
		exit(1)
	}
}
