// SPDX-License-Identifier: GPL-2.0-or-later
module linuxcheck

import os

// Pin the produced target's regular-file identity and permissions across runs.
// ELF libraries still use require_arm64_elf without requiring execute bits.
pub struct Arm64Executable {
pub:
	path   string
	mode   u32
	device u64
	inode  u64
	size   u64
	mtime  i64
	ctime  i64
}

fn arm64_executable_stat(path string) !os.Stat {
	if path == '' || path.contains('\x00') {
		return error('ARM64 executable path is missing or invalid')
	}
	info := os.lstat(path)!
	if info.get_filetype() != .regular {
		return error('ARM64 executable must be a regular file without a symlink: ${path}')
	}
	return info
}

fn require_arm64_executable(path string) !Arm64Executable {
	info := arm64_executable_stat(path)!
	mode := info.mode & 0o7777
	if mode & 0o111 == 0 {
		return error('ARM64 executable has no execute permission bits (mode 0${mode:o}): ${path}')
	}
	require_arm64_elf(path)!
	target := Arm64Executable{
		path: path
		mode: mode
		device: info.dev
		inode: info.inode
		size: info.size
		mtime: info.mtime
		ctime: info.ctime
	}
	arm64_executable_unchanged(target)!
	return target
}

fn arm64_executable_unchanged(target Arm64Executable) ! {
	info := arm64_executable_stat(target.path)!
	mode := info.mode & 0o7777
	if mode != target.mode {
		return error('ARM64 executable mode changed from 0${target.mode:o} to 0${mode:o}: ${target.path}')
	}
	if mode & 0o111 == 0 {
		return error('ARM64 executable has no execute permission bits (mode 0${mode:o}): ${target.path}')
	}
	if info.dev != target.device || info.inode != target.inode || info.size != target.size
		|| info.mtime != target.mtime || info.ctime != target.ctime {
		return error('ARM64 executable metadata changed since qualification: ${target.path}')
	}
	require_arm64_elf(target.path)!
}

fn guarded_arm64_command(target Arm64Executable, out string, label string,
	args []string, cwd string, env map[string]string, seconds int) !(int, string) {
	if target.path == '' || target.path !in args {
		return error('${label}: invocation omitted its qualified ARM64 executable')
	}
	arm64_executable_unchanged(target) or { return error('${label}: ${err.msg()} before execution') }
	code, output := guarded_command(out, label, args, cwd, env, seconds) or {
		failure := err
		arm64_executable_unchanged(target) or {
			return error('${label}: ${err.msg()} after execution; ${failure.msg()}')
		}
		return failure
	}
	arm64_executable_unchanged(target) or { return error('${label}: ${err.msg()} after execution') }
	return code, output
}

fn checked_arm64_exit(target Arm64Executable, out string, label string,
	args []string, cwd string, env map[string]string, expected int) !string {
	code, output := guarded_arm64_command(target, out, label, args, cwd, env, 600)!
	return checked_result(out, label, code, output, expected)
}

fn probe_guarded_command(runtime ProbeRuntime, out string, label string,
	args []string, cwd string, env map[string]string) !(int, string) {
	if runtime.target_executable.path != '' {
		return guarded_arm64_command(runtime.target_executable, out, label, args,
			cwd, env, runtime.deadline_seconds)
	}
	return guarded_command(out, label, args, cwd, env, runtime.deadline_seconds)
}
