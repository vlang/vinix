// SPDX-License-Identifier: GPL-2.0-or-later
module allocationhost

import cachecli
import crypto.sha256
import hosttest
import json2
import os
import sourcecommand
import time

pub const benchmark_flags = ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-builtin']
pub const sampler_verdict = 'Shared kernel allocator sampler: success, three-phase OOM/zeroing rollback, TSC failure and kext ABI passed'

pub fn root() string { return hosttest.root() }

fn here() string { return root() + '/tests/alloc-bench' }

fn resolve(path string) !string {
	return hosttest.module_resolve(if path == '' { '.' } else { path })!
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn write_json(path string, value json2.Any) ! { hosttest.write_json(path, value)! }

pub fn capture(argv []string, env map[string]string, timeout f64) !sourcecommand.Output {
	cachecli.checkpoint()!
	result := sourcecommand.capture(argv, env, timeout, 64 * 1024 * 1024, cachecli.cancelled)!
	cachecli.checkpoint()!
	return result
}

fn checked(argv []string) !sourcecommand.Output {
	result := capture(argv, os.environ(), -1)!
	if result.status != 0 {
		return hosttest.ModuleCommandError{argv, hosttest.Result{result.stdout, result.stderr, result.status}}
	}
	return result
}

fn report_failure(failure IError) {
	if failure is hosttest.ModuleCommandError {
		print(failure.result.stdout)
		eprint(failure.result.stderr)
		eprintln('native compiler command failed')
	} else {
		eprintln(failure.msg())
	}
}

fn run(argv []string) ! {
	result := checked(argv)!
	print(result.stdout)
	eprint(result.stderr)
}

struct CommandDeadline {
	timeout f64
	started u64
}

fn wait_command(pid int, pointer voidptr) ! {
	data := unsafe { &CommandDeadline(pointer) }
	for !sourcecommand.child_exited(pid)! {
		cachecli.checkpoint()!
		if data.timeout >= 0 && f64(time.sys_mono_now() - data.started) >= data.timeout * f64(time.second) {
			return error('command timed out')
		}
		time.sleep(10 * time.millisecond)
	}
}

fn logged(argv []string, env map[string]string, log string, append bool, directory string, timeout f64) !sourcecommand.Output {
	cachecli.checkpoint()!
	context := CommandDeadline{timeout, time.sys_mono_now()}
	result := sourcecommand.run_logged_owned(argv, env, cachecli.cancelled, log, append, directory, wait_command, unsafe { &context }, 0)!
	cachecli.checkpoint()!
	if result.status != 0 { return error('command failed; see ' + log) }
	return result
}

fn checkpoint_sleep(duration time.Duration) ! {
	deadline := time.sys_mono_now() + u64(duration)
	for time.sys_mono_now() < deadline {
		cachecli.checkpoint()!
		now := time.sys_mono_now()
		if now >= deadline { break }
		remaining := deadline - now
		time.sleep(if remaining < u64(50 * time.millisecond) {
			time.Duration(remaining)
		} else {
			50 * time.millisecond
		})
	}
	cachecli.checkpoint()!
}

fn environment() map[string]string {
	mut env := os.environ()
	env['ASAN_OPTIONS'] = $if macos { 'detect_leaks=0' } $else { 'detect_leaks=1' }
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	return env
}

fn clean_diagnostics(text string) bool {
	return !['runtime error', 'AddressSanitizer', 'LeakSanitizer'].any(text.contains(it))
}

fn compiler_flags(arch string, guest bool, sampler bool) []string {
	mut flags := []string{}
	if guest && arch == 'arm64' {
		sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root() + '/build-aarch64-userland/sysroot' }
		flags = [os.getenv_opt('CC_AARCH64') or { 'clang' }, '--target=aarch64-linux-musl',
			'--sysroot=' + sdk, '-fuse-ld=lld', '-L' + sdk + '/lib']
	} else if guest {
		flags = [os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }]
	} else {
		flags = [os.getenv_opt('CC') or { 'clang' }]
		$if macos {
			flags << ['-arch', if arch == 'arm64' { 'arm64' } else { 'x86_64' }]
		}
	}
	flags << if sampler {
		['-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fno-builtin', '-ffreestanding',
			'-fno-strict-aliasing', '-fno-stack-protector']
	} else {
		benchmark_flags
	}
	if !guest { flags << ['-fsanitize=address,undefined', '-fno-omit-frame-pointer'] }
	return flags
}

fn object_flags(flags []string, sampler bool) []string {
	return flags.filter(!it.starts_with('-L') && !it.starts_with('-l') && !it.starts_with('-fuse-ld=') && !(sampler && it.starts_with('-Wl,')))
}

fn implicit_allocations(imports string, allowed []string) bool {
	for symbol in hosttest.undefined_symbols(imports) {
		name := if symbol.starts_with('_') { symbol[1..] } else { symbol }
		if name in allowed { continue }
		if name in ['malloc', 'calloc', 'realloc', 'free', 'memdup', 'v_malloc'] || name.starts_with('new_array') {
			return true
		}
	}
	return false
}

fn forbidden_generated_calls(text string, names []string) bool {
	for name in names {
		mut start := 0
		for start < text.len {
			offset := text[start..].index(name) or { break }
			position := start + offset
			mut end := position + name.len
			if name == 'new_array' {
				for end < text.len && hosttest.word_char(text[end]) { end++ }
			}
			for end < text.len && text[end].is_space() { end++ }
			if (position == 0 || !hosttest.word_char(text[position - 1])) && end < text.len && text[end] == `(` {
				return true
			}
			start = position + name.len
		}
	}
	return false
}

fn generated_call_count(text string, name string) int {
	mut count := 0
	mut start := 0
	needle := name + '('
	for start < text.len {
		offset := text[start..].index(needle) or { break }
		position := start + offset
		if position == 0 || !hosttest.word_char(text[position - 1]) { count++ }
		start = position + needle.len
	}
	return count
}
