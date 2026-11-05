// SPDX-License-Identifier: GPL-2.0-or-later
module linuxcheck

import os
import json2
import probedesktop

fn testsuite_begin() {
	if os.args.len == 4 && os.args[1] == '--target-mode-control' {
		if os.args[3] == 'remove' { os.chmod(os.args[2], 0o644) or { panic(err) } }
		println('ARM64-MODE-CONTROL: native helper completed')
		C._exit(37)
	}
}

fn executable_test_directory(name string) string {
	path := os.join_path(os.temp_dir(), 'vinix-arm64-mode-${os.getpid()}-${name}')
	os.mkdir(path) or { panic(err) }
	return path
}

// Header-only ARM64 metadata controls are never executed. The bounded child
// below is this native V test binary, which changes only a separate control file.
fn executable_test_header(path string, kind u8, mode u32) {
	mut header := []u8{len: 64}
	header[0] = 0x7f
	header[1] = `E`
	header[2] = `L`
	header[3] = `F`
	header[4] = 2
	header[5] = 1
	header[6] = 1
	header[16] = kind
	header[18] = 183
	os.write_file_array(path, header) or { panic(err) }
	os.chmod(path, int(mode)) or { panic(err) }
}

fn test_arm64_executable_requires_permission_without_changing_elf_library_rules() {
	base := executable_test_directory('permission')
	defer { os.rmdir_all(base) or {} }
	path := base + '/target'
	executable_test_header(path, 2, 0o644)
	mut rejected := false
	require_arm64_executable(path) or {
		rejected = err.msg().contains('no execute permission bits (mode 0644)')
	}
	assert rejected
	assert (os.lstat(path) or { panic(err) }).mode & 0o7777 == 0o644
	os.chmod(path, 0o751) or { panic(err) }
	target := require_arm64_executable(path) or { panic(err) }
	assert target.path == path && target.mode == 0o751
	arm64_executable_unchanged(target) or { panic(err) }
	library := base + '/library.so'
	executable_test_header(library, 3, 0o644)
	require_arm64_elf(library) or { panic(err) }
	rejected = false
	require_arm64_executable(library) or { rejected = err.msg().contains('no execute permission') }
	assert rejected
	os.chmod(library, 0o755) or { panic(err) }
	pie := require_arm64_executable(library) or { panic(err) }
	assert pie.mode == 0o755
}

fn test_arm64_executable_rejects_aliases_and_nonregular_files_before_opening() {
	base := executable_test_directory('type')
	defer { os.rmdir_all(base) or {} }
	path := base + '/target'
	executable_test_header(path, 2, 0o755)
	os.symlink(path, base + '/alias') or { panic(err) }
	for invalid in [base, base + '/alias'] {
		mut rejected := false
		require_arm64_executable(invalid) or { rejected = err.msg().contains('regular file') }
		assert rejected
	}
	mut rejected := false
	os.write_file(path, 'not an ELF') or { panic(err) }
	require_arm64_executable(path) or { rejected = err.msg().contains('ARM64 ELF') }
	assert rejected
}

fn test_arm64_executable_detects_permission_changes_even_when_still_executable() {
	base := executable_test_directory('changed')
	defer { os.rmdir_all(base) or {} }
	path := base + '/target'
	executable_test_header(path, 2, 0o755)
	target := require_arm64_executable(path) or { panic(err) }
	for mode in [u32(0o750), 0o644] {
		os.chmod(path, int(mode)) or { panic(err) }
		mut rejected := false
		arm64_executable_unchanged(target) or {
			rejected = err.msg().contains('mode changed from 0755 to 0${mode:o}')
		}
		assert rejected
		assert (os.lstat(path) or { panic(err) }).mode & 0o7777 == mode
	}
}

fn test_arm64_target_guard_refuses_lost_permission_before_creating_execution_receipts() {
	base := executable_test_directory('before')
	defer { os.rmdir_all(base) or {} }
	path := base + '/target'
	executable_test_header(path, 2, 0o755)
	target := require_arm64_executable(path) or { panic(err) }
	os.chmod(path, 0o644) or { panic(err) }
	mut rejected := false
	guarded_arm64_command(target, base, 'refused', ['/usr/bin/true', path], base,
		isolated_build_environment(), 10) or {
		rejected = err.msg().contains('mode changed from 0755 to 0644')
			&& err.msg().contains('before execution')
	}
	assert rejected
	assert !os.exists(base + '/refused.log') && !os.exists(base + '/refused.status.txt')
}

fn test_arm64_target_guard_preserves_exit_status_and_detects_child_mode_changes() {
	base := executable_test_directory('after')
	defer { os.rmdir_all(base) or {} }
	path := base + '/target'
	executable_test_header(path, 2, 0o755)
	target := require_arm64_executable(path) or { panic(err) }
	helper := os.real_path(os.executable())
	env := isolated_build_environment()
	output := checked_arm64_exit(target, base, 'kept',
		[helper, '--target-mode-control', path, 'keep'], base, env, 37) or { panic(err) }
	assert output.contains('ARM64-MODE-CONTROL: native helper completed')
	assert (os.read_file(base + '/kept.status.txt') or { panic(err) }) == '37\n'
	mut rejected := false
	guarded_arm64_command(target, base, 'changed',
		[helper, '--target-mode-control', path, 'remove'], base, env, 10) or {
		rejected = err.msg().contains('mode changed from 0755 to 0644')
			&& err.msg().contains('after execution')
	}
	assert rejected
	assert (os.read_file(base + '/changed.status.txt') or { panic(err) }) == '37\n'
	assert (os.read_file(base + '/changed.guard.txt') or { panic(err) }).contains('residual_descendants=0')
	assert (os.lstat(path) or { panic(err) }).mode & 0o7777 == 0o644
}

fn test_arm64_executable_detects_replacement_with_the_same_mode_and_header() {
	base := executable_test_directory('replacement')
	defer { os.rmdir_all(base) or {} }
	path := base + '/target'
	executable_test_header(path, 2, 0o755)
	target := require_arm64_executable(path) or { panic(err) }
	replacement := base + '/replacement'
	executable_test_header(replacement, 2, 0o755)
	assert (os.lstat(replacement) or { panic(err) }).inode != target.inode
	os.rename(replacement, path) or { panic(err) }
	mut rejected := false
	arm64_executable_unchanged(target) or { rejected = err.msg().contains('metadata changed') }
	assert rejected
	assert (os.lstat(path) or { panic(err) }).mode & 0o7777 == 0o755
}

fn test_arm64_desktop_task_roundtrip_preserves_and_enforces_the_metadata_baseline() {
	base := executable_test_directory('desktop-task')
	defer { os.rmdir_all(base) or {} }
	path := base + '/target'
	executable_test_header(path, 2, 0o755)
	target := require_arm64_executable(path) or { panic(err) }
	task := ProbeDesktopTask{
		invocation: ['/usr/bin/true', path]
		target_executable: target
		config: probedesktop.Config{startup_ms: 1000}
	}
	decoded := json2.decode[ProbeDesktopTask](json2.encode(task)) or { panic(err) }
	assert decoded.target_executable == target
	probe_desktop_validate(decoded) or { panic(err) }
	runtime := ProbeRuntime{
		invocation: ['/usr/bin/true', path]
		target_executable: target
		profile: 'header metadata control; no target execution'
		built_backends: ['gles']
		required_backends: ['gles']
	}
	probe_require_runtime(runtime) or { panic(err) }
	os.chmod(path, 0o644) or { panic(err) }
	mut rejected := false
	probe_desktop_validate(decoded) or {
		rejected = err.msg().contains('mode changed from 0755 to 0644')
	}
	assert rejected
	rejected = false
	probe_require_runtime(runtime) or {
		rejected = err.msg().contains('mode changed from 0755 to 0644')
	}
	assert rejected
	assert (os.lstat(path) or { panic(err) }).mode & 0o7777 == 0o644
}
