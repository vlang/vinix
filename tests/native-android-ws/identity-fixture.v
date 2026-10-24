// SPDX-License-Identifier: GPL-2.0-or-later
// Run as root on Linux/Vinix. Each real credential change stays in a child.
module main

import nativeidentity
import os
import rand

#include <unistd.h>
#include <grp.h>
#include <pwd.h>
#include <sys/wait.h>
#include <sys/prctl.h>

fn C.getuid() u32
fn C.geteuid() u32
fn C.getpwuid(u32) voidptr
fn C.getgrgid(u32) voidptr
fn C.getresuid(&u32, &u32, &u32) int
fn C.getresgid(&u32, &u32, &u32) int
fn C.setresuid(u32, u32, u32) int
fn C.setresgid(u32, u32, u32) int
fn C.setgroups(usize, voidptr) int
fn C.getgroups(int, voidptr) int
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C.prctl(int, u64, u64, u64, u64) int

fn verify_exec(root string) ! {
	mut real := u32(0)
	mut effective := u32(0)
	mut saved := u32(0)
	assert C.getresuid(&real, &effective, &saved) == 0
	assert real == 10000 && effective == 10000 && saved == 10000
	assert C.getresgid(&real, &effective, &saved) == 0
	assert real == 10000 && effective == 10000 && saved == 10000
	assert C.getgroups(0, unsafe { nil }) == 0
	assert C.prctl(39, 0, 0, 0, 0) == 1
	assert C.setresuid(0, 0, 0) != 0
	status := os.read_file('/proc/self/status')!
	for key in ['CapInh:', 'CapPrm:', 'CapEff:', 'CapBnd:', 'CapAmb:'] {
		line := status.split_into_lines().filter(it.starts_with(key))
		assert line.len == 1, key
		assert line[0].all_after(':').trim_space().trim_left('0') == '', line[0]
	}
	assert os.getenv('HOME') == root + '/home'
	assert os.getenv('XDG_DATA_HOME') == root + '/home/.local/share'
	assert os.getenv('USER') == '' && os.getenv('LOGNAME') == '' && os.getenv('XDG_RUNTIME_DIR') == ''
	assert os.getwd() == root + '/data'
	assert os.read_file(root + '/application.apk')! == 'unchanged APK fixture\n'
	assert os.read_file(root + '/runtime/runtime-input')! == 'runtime readable\n'
	for directory in ['data', 'home', 'surfaces'] {
		path := root + '/' + directory + '/credential-probe'
		os.write_file(path, 'actual target Unix credentials\n')!
		assert os.stat(path)!.uid == 10000
		os.rm(path)!
	}
	println('ANDROID-IDENTITY-EXEC PASS triples=10000 groups=0 capabilities=0 nnp=1 root-regain=denied inputs=accessible')
}

fn prepare(root string) ! {
	os.mkdir_all(root)!
	os.chmod(root, 0o755)!
	for directory in ['data', 'home', 'surfaces'] {
		path := root + '/' + directory
		os.mkdir(path)!
		os.chown(path, 10000, 10000)!
		os.chmod(path, 0o700)!
	}
	for directory in ['runtime', 'runtime/lib', 'runtime/usr', 'runtime/usr/bin'] {
		os.mkdir(root + '/' + directory)!
		os.chmod(root + '/' + directory, 0o755)!
	}
	for file, contents in {
		'application.apk':                      'unchanged APK fixture\n'
		'runtime/runtime-input':                'runtime readable\n'
		'runtime/lib/ld-musl-aarch64.so.1':     'loader access fixture\n'
		'runtime/usr/bin/vinix-android-native': 'entry access fixture\n'
	} {
		os.write_file(root + '/' + file, contents)!
		os.chmod(root + '/' + file, if file.ends_with('application.apk') || file.ends_with('runtime-input') {
			0o644
		} else {
			0o755
		})!
	}
}

fn child(root string, kind string) ! {
	mut uid := '10000'
	mut gid := '10000'
	if kind in ['unknown-user', 'unknown-group'] {
		mut absent := ''
		for value in 10001 .. 20000 {
			if (kind == 'unknown-user' && C.getpwuid(u32(value)) == unsafe { nil })
				|| (kind == 'unknown-group' && C.getgrgid(u32(value)) == unsafe { nil }) {
				absent = value.str()
				break
			}
		}
		if absent == '' { return error('fixture requires an unallocated application ID') }
		if kind == 'unknown-user' { uid = absent } else { gid = absent }
	}
	config := nativeidentity.parse(uid, gid, root + '/data', root + '/home')!
	if kind == 'nonroot' {
		assert C.setgroups(0, unsafe { nil }) == 0
		assert C.setresgid(10001, 10001, 10001) == 0
		assert C.setresuid(10001, 10001, 10001) == 0
	}
	os.setenv('USER', 'root', true)
	os.setenv('LOGNAME', 'root', true)
	os.setenv('XDG_RUNTIME_DIR', '/run/user/0', true)
	config.activate(root + '/application.apk', if kind == 'relative-runtime' {
		'runtime'
	} else {
		root + '/runtime'
	},
		root + '/surfaces/surface') or {
		if kind in ['fresh', 'owned-surface'] { return err }
		if kind in ['unknown-user', 'unknown-group'] {
			assert err.msg().contains('pre-provisioned Unix account and group'), err.msg()
		}
		println('ANDROID-IDENTITY-REJECT ${kind}: ${err}')
		return
	}
	if kind !in ['fresh', 'owned-surface'] {
		return error('accepted invalid credential fixture: ' + kind)
	}
	os.execvp(os.executable(), ['--verify', root])!
}

fn run() ! {
	if os.args.len == 3 && os.args[1] == '--verify' {
		verify_exec(os.args[2])!
		return
	}
	if C.getuid() != 0 || C.geteuid() != 0 {
		return error('fixture requires real and effective root')
	}
	base := os.join_path(os.temp_dir(), 'vinix-android-identity-' + rand.uuid_v4())
	os.mkdir(base)!
	os.chmod(base, 0o755)!
	defer { os.rmdir_all(base) or {} }
	cases := ['fresh', 'owned-surface', 'nonroot', 'unknown-user', 'unknown-group', 'root-data',
		'root-home', 'unwritable-data', 'inaccessible-apk', 'inaccessible-runtime', 'unexecutable-entry',
		'root-surface', 'surface-symlink', 'surface-directory', 'data-symlink', 'relative-runtime',
		'surface-parent']
	for kind in cases {
		root := base + '/' + kind
		prepare(root)!
		surface := root + '/surfaces/surface'
		match kind {
			'root-data' { os.chown(root + '/data', 0, 0)! }
			'root-home' { os.chown(root + '/home', 0, 0)! }
			'unwritable-data' { os.chmod(root + '/data', 0o500)! }
			'inaccessible-apk' { os.chmod(root + '/application.apk', 0o600)! }
			'inaccessible-runtime' { os.chmod(root + '/runtime/runtime-input', 0o600)! }
			'unexecutable-entry' {
				os.chmod(root + '/runtime/usr/bin/vinix-android-native', 0o644)!
			}
			'root-surface', 'owned-surface' {
				os.write_file(surface, '')!
				os.chmod(surface, 0o600)!
				if kind == 'owned-surface' { os.chown(surface, 10000, 10000)! }
			}
			'surface-symlink' { os.symlink(root + '/application.apk', surface)! }
			'surface-directory' {
				os.mkdir(surface)!
				os.chown(surface, 10000, 10000)!
			}
			'data-symlink' {
				os.rmdir(root + '/data')!
				os.symlink(root + '/home', root + '/data')!
			}
			'surface-parent' { os.chown(root + '/surfaces', 0, 0)! }
			else {}
		}
		pid := C.fork()
		if pid < 0 { return error('cannot fork identity fixture') }
		if pid == 0 {
			child(root, kind) or {
				eprintln('ANDROID-IDENTITY-FAIL ${kind}: ${err}')
				exit(1)
			}
			exit(0)
		}
		mut status := 0
		if C.waitpid(pid, &status, 0) != pid || status != 0 {
			return error('identity fixture failed: ${kind} status=${status}')
		}
		// Read-only rejection must not alter the source APK or its ownership.
		assert os.read_file(root + '/application.apk')! == 'unchanged APK fixture\n'
		assert os.stat(root + '/application.apk')!.uid == 0
	}
	println('ANDROID-IDENTITY-SUITE PASS cases=${cases.len}')
}

fn main() {
	run() or {
		eprintln('ANDROID-IDENTITY-SUITE FAIL ${err}')
		exit(1)
	}
}
