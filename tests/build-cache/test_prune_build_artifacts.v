// SPDX-License-Identifier: GPL-2.0-only
import hosttest
import os
import prunehost
import time

#include <signal.h>
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/file.h>

fn C.kill(i32, i32) i32
fn C.rename(&char, &char) i32
fn C.utimensat(i32, &char, &C.timespec, i32) i32
fn C.flock(i32, i32) i32

struct Inspector {
	mode    string
	path    string
	outside string
}

fn (inspector Inspector) active(paths []string, root string) !map[string]bool {
	assert root != '' && paths.len > 0
	match inspector.mode {
		'fail' { return error('inspection failed') }
		'replace' {
			os.write_file(inspector.path + '.new', 'new build')!
			if C.rename((inspector.path + '.new').str, inspector.path.str) != 0 {
				return os.error_posix()
			}
		}
		'marker' { os.write_file(inspector.path + '.keep', '')! }
		'link' {
			os.rm(inspector.path)!
			os.symlink(inspector.outside, inspector.path)!
		}
		else {}
	}
	return map[string]bool{}
}

fn fixture(root string, name string) !string {
	path := root + '/' + name
	os.mkdir_all(os.dir(path))!
	os.write_file(path, 'reproducible archive\n')!
	return path
}

fn clock() f64 { return f64(time.now().unix_micro()) / 1e6 }

fn check_policy(root string) ! {
	now := clock()
	mut old := []string{}
	for variant in ['host-fill', 'runtime-fix', '2x', 'clean', 'debug'] {
		old << fixture(root, 'build/minecraft-desktop-initramfs-${variant}.tar')!
	}
	old << fixture(root, 'build/desktop-perf/initramfs-desktop-123.iso')!
	metadata := fixture(root, 'build/desktop-perf/initramfs-desktop-123.iso.json')!
	old << fixture(root, 'build/.initramfs-desktop-qemu.tar.gz.abc123')!
	old << fixture(root, 'build-support/init-aarch64/.initramfs-desktop.tar.def456')!
	mut preserved := []string{}
	for name in ['build/minecraft-desktop-root.ext2', 'build/minecraft-desktop-boot.img',
		'build/macos.qcow2', 'build/downloads/initramfs.tar', 'build/staging/initramfs.tar',
		'build/vinix-installer/initramfs.tar', 'build/sources.tar.gz', 'build/desktop-root-seed.tar.gz',
		'build/initramfs-desktop-qemu.tar', 'build/initramfs-desktop-qemu.iso',
		'build/initramfs-desktop-full.iso', 'build-support/init-aarch64/initramfs.tar',
		'build-support/init-aarch64/initramfs-desktop.tar'] {
		preserved << fixture(root, name)!
	}
	recent := fixture(root, 'build/new-initramfs.tar')!
	times := [C.timespec{ tv_sec: i64(now) + 7 * 86400, tv_nsec: 0 },
		C.timespec{ tv_sec: i64(now) + 7 * 86400, tv_nsec: 0 }]!
	assert unsafe { C.utimensat(C.AT_FDCWD, recent.str, &times[0], 0) } == 0
	preserved << recent
	result := prunehost.prune(root, 7, map[string]bool{}, false, now + 8 * 86400, Inspector{})!
	assert result.count == old.len && result.freed > 0
	for path in [...old, metadata] {
		assert !os.exists(path)
	}
	for path in preserved {
		assert os.exists(path)
	}
	assert prunehost.prune(root, 7, map[string]bool{}, false, now + 8 * 86400, Inspector{})!.count == 0
	// Preserve every preexisting file before independent scenarios below.
	os.rm(recent)!
}

fn check_overrides(root string) ! {
	explicit := fixture(root, 'build/custom-initramfs.tar')!
	marked := fixture(root, 'build/marked-initramfs.tar')!
	fixture(root, 'build/marked-initramfs.tar.keep')!
	removable := fixture(root, 'build/other-initramfs.tar')!
	keep := {
		explicit: true
	}
	assert prunehost.prune(root, 7, keep, true, clock() + 8 * 86400, Inspector{})!.count == 1
	assert os.exists(removable)
	assert prunehost.prune(root, 7, keep, false, clock() + 8 * 86400, Inspector{})!.count == 1
	assert os.exists(explicit) && os.exists(marked) && !os.exists(removable)
	os.rm(explicit)!
	outside := fixture(root, 'external/initramfs.tar')!
	os.symlink(outside, root + '/build/linked-initramfs.tar')!
	os.symlink(root + '/external', root + '/build/qemu-desktop-capture')!
	assert prunehost.prune(root, 0, map[string]bool{}, false, clock() + 1, Inspector{})!.count == 0
	assert os.is_link(root + '/build/linked-initramfs.tar') && os.exists(outside)
	for mode in ['replace', 'marker', 'link', 'fail'] {
		path := fixture(root, 'build/race-${mode}-initramfs.tar')!
		result := prunehost.prune(root, 0, map[string]bool{}, false, clock() + 1, Inspector{mode, path, outside}) or {
			assert mode == 'fail' && err.msg() == 'inspection failed'
			assert os.exists(path)
			os.rm(path)!
			continue
		}
		assert mode != 'fail' && result.count == 0
		assert os.exists(path) && os.read_file(outside)! == 'reproducible archive\n'
		if mode == 'replace' {
			assert os.read_file(path)! == 'new build'
		}
		os.rm(path)!
	}
}

fn invoke(root string, extra []string, env map[string]string) !hosttest.Result {
	argv := if tool := os.getenv_opt('VINIX_PRUNE_TOOL') {
		[tool]
	} else {
		[os.executable(), '--worker']
	}
	return hosttest.capture([...argv, '--root', root, '--older-than-days', '0', ...extra], '', 60, env)
}

fn check_native(root string) ! {
	// Real ps also sees concurrent suites' lsof arguments. Unique archive names
	// keep their root-relative input protection from affecting this fixture.
	token := os.file_name(root)
	path := fixture(root, 'build/${token}-open-initramfs.tar')!
	mut file := os.open(path)!
	assert prunehost.prune(root, 0, map[string]bool{}, false, clock() + 1, prunehost.NativeInspector{})!.count == 0
	file.close()
	assert prunehost.prune(root, 0, map[string]bool{}, false, clock() + 1, prunehost.NativeInspector{})!.count == 1
	future := fixture(root, 'build/${token}-future-initramfs.tar')!
	mut env := os.environ()
	env['VINIX_DESKTOP_INITRAMFS'] = future
	mut child := os.new_process(os.executable())
	defer {
		if child.is_alive() {
			C.kill(child.pid, 9)
			child.wait()
		}
		child.close()
	}
	child.set_args(['--wait'])
	child.set_environment(env)
	child.set_redirect_stdio()
	child.run()
	mut ready := ''
	deadline := time.sys_mono_now() + u64(5 * time.second)
	for !ready.contains('ready') && child.is_alive() && time.sys_mono_now() < deadline {
		ready += child.stdout_read()
		time.sleep(time.millisecond)
	}
	assert ready.contains('ready')
	assert prunehost.prune(root, 0, map[string]bool{}, false, clock() + 1, prunehost.NativeInspector{})!.count == 0
	assert os.exists(future)
	C.kill(child.pid, 9)
	child.wait()
	os.rm(future)!
	kept := fixture(root, 'build/${token}-override-initramfs.tar')!
	kept_iso := fixture(root, 'build/${token}-override-initramfs.iso')!
	removable := fixture(root, 'build/${token}-automatic-initramfs.tar')!
	env = os.environ()
	env['VINIX_PRUNE_BUILD'] = '0'
	assert invoke(root, ['--automatic'], env)!.code == 0 && os.exists(removable)
	env['VINIX_PRUNE_BUILD'] = '1'
	env['VINIX_DESKTOP_INITRAMFS'] = kept
	env['VINIX_AMD64_DESKTOP_ISO'] = kept_iso
	automatic := invoke(root, ['--automatic'], env)!
	assert automatic.code == 0
	assert os.exists(kept) && os.exists(kept_iso) && !os.exists(removable), automatic.stdout + automatic.stderr
	assert invoke(root, ['--keep', kept, '--keep=' + kept_iso, '--dry-run'], os.environ())!.code == 0
	assert os.exists(kept) && os.exists(kept_iso)
	// Inspection failure is closed; automatic cleanup tolerates it without deletion.
	os.mkdir(root + '/bin')!
	os.symlink(os.executable(), root + '/bin/ps')!
	mut broken := os.environ()
	broken['PATH'] = root + '/bin'
	broken['VINIX_PRUNE_TEST_PS_MODE'] = 'fail'
	assert invoke(root, []string{}, broken)!.code == 1
	assert invoke(root, ['--automatic'], broken)!.code == 0
	assert os.exists(kept) && os.exists(kept_iso)
	broken['VINIX_PRUNE_TEST_PS_MODE'] = 'ok'
	os.symlink(os.executable(), root + '/bin/lsof')!
	broken['VINIX_PRUNE_TEST_LSOF_MODE'] = 'fail'
	failed_lsof := invoke(root, []string{}, broken)!
	assert failed_lsof.code == 1 && failed_lsof.stderr.contains('could not inspect open build archives')
	assert !failed_lsof.stderr.contains('private-environment-fixture')
	assert os.exists(kept) && os.exists(kept_iso)
	broken['VINIX_PRUNE_TEST_LSOF_MODE'] = 'protect'
	broken['VINIX_PRUNE_TEST_PROTECTED'] = kept
	protected := invoke(root, ['--keep', kept_iso], broken)!
	assert protected.code == 0 && protected.stdout == '' && os.exists(kept)
	broken['VINIX_PRUNE_TEST_LSOF_MODE'] = 'empty'
	assert invoke(root, ['--keep', kept_iso, '--dry-run'], broken)!.stdout.contains('Would remove build/' + os.file_name(kept))
	for value in ['nan', 'inf', '-1', 'invalid'] {
		assert invoke(root, ['--older-than-days=' + value], os.environ())!.code == 2
	}
	// Every owned lock must close in repeated in-process calls.
	fd_dir := if os.is_dir('/proc/self/fd') { '/proc/self/fd' } else { '/dev/fd' }
	before_fds := os.ls(fd_dir)!.len
	for _ in 0 .. 64 {
		assert prunehost.locked_prune(root, 7, map[string]bool{}, false)!.count == 0
	}
	assert os.ls(fd_dir)!.len == before_fds
}

fn check_lock(root string) ! {
	mut held := os.open_file(root + '/build/.prune-build-artifacts.lock', 'a+')!
	defer { held.close() }
	assert C.flock(held.fd, C.LOCK_EX) == 0
	mut child := os.new_process(os.executable())
	defer {
		if child.is_alive() {
			C.kill(child.pid, 9)
			child.wait()
		}
		child.close()
	}
	mut env := os.environ()
	env['VINIX_PRUNE_TEST_READY'] = root + '/ready'
	child.set_args(['--worker', '--root', root])
	child.set_environment(env)
	child.set_redirect_stdio()
	child.run()
	deadline := time.sys_mono_now() + u64(5 * time.second)
	for !os.exists(root + '/ready') && child.is_alive() && time.sys_mono_now() < deadline {
		time.sleep(time.millisecond)
	}
	assert os.exists(root + '/ready')
	time.sleep(50 * time.millisecond)
	assert child.is_alive()
	assert C.flock(held.fd, C.LOCK_UN) == 0
	for child.is_alive() && time.sys_mono_now() < deadline { time.sleep(time.millisecond) }
	assert !child.is_alive()
	child.wait()
	assert child.code == 0, child.stderr_slurp()
}

fn check_names(root string) ! {
	// Independently stated selection boundaries, including Unicode word membership.
	assert prunehost.candidates(os.temp_dir() + '/definitely-missing-prune-root')!.len == 0
	mut expected := []string{}
	for name in ['build/é-initramfs.tar', 'build/.é-initramfs.tar.abc123',
		'build/desktop-perf/any name.iso'] {
		expected << fixture(root + '/names', name)!
	}
	for name in ['build/.hidden-initramfs.tar', 'build/initramfs with space.tar',
		'build/.initramfs.tar.abc_23', 'build/initramfs.TAR', 'build/no-image.tar',
		'build/.initramfs.tar.abc1234'] {
		fixture(root + '/names', name)!
	}
	expected.sort()
	assert prunehost.candidates(root + '/names')! == expected
}

fn main() {
	if os.file_name(os.args[0]) == 'ps' {
		if os.getenv('VINIX_PRUNE_TEST_PS_MODE') == 'fail' { exit(17) }
		return
	}
	if os.file_name(os.args[0]) == 'lsof' {
		match os.getenv('VINIX_PRUNE_TEST_LSOF_MODE') {
			'fail' {
				eprintln('private-environment-fixture')
				exit(17)
			}
			'protect' { println('n' + os.getenv('VINIX_PRUNE_TEST_PROTECTED')) }
			else { exit(1) }
		}
		return
	}
	if os.args.len > 1 && os.args[1] == '--worker' {
		if ready := os.getenv_opt('VINIX_PRUNE_TEST_READY') { os.write_file(ready, 'ready')! }
		prunehost.run(os.args[2..])
		return
	}
	if os.args.len > 1 && os.args[1] == '--wait' {
		println('ready')
		mut buffer := []u8{len: 1}
		mut input := os.stdin()
		input.read(mut buffer) or {}
		return
	}
	root := hosttest.resolve_path(hosttest.work_dir('', 'vinix-prune-check-')!)!
	defer { hosttest.remove_work_dir(root) or { panic(err) } }
	check_names(root)!
	check_policy(root)!
	check_overrides(root)!
	check_native(root)!
	check_lock(root)!
	println('PASS native pruning checks')
}
