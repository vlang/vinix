// SPDX-License-Identifier: GPL-2.0-or-later
module emulatorhost

import guesthost
import hosttest
import os
import policyhost
import time

pub fn label(kind string) string { return kind.to_upper() }
pub fn demo_name(kind string) string { return if kind == 'ps1' { 'tetrade.exe' } else if kind == 'ps2' { 'paddle.elf' } else { 'paddle.z64' } }
fn build_dir(kind string) !string {
	return hosttest.module_resolve(os.getenv_opt('VINIX_' + label(kind) + '_BUILD_DIR') or { guesthost.root() + '/build/' + kind })!
}
fn sdk(kind string) string { return os.getenv_opt('VINIX_' + label(kind) + '_TEST_SYSROOT') or { guesthost.root() + '/build-aarch64-userland/sysroot' } }
fn report(err IError) int {
	eprintln(err.msg())
	return if err.code() == 2 { 2 } else if err.msg() in ['Host test interrupted', 'Guest run interrupted'] { 130 } else { 1 }
}
fn parse(args []string, specs []hosttest.Option, usage string) !guesthost.Options {
	return guesthost.parse(args, specs, [], usage) or { return error_with_code(err.msg(), 2) }
}
fn timeout(options guesthost.Options, fallback int) !int {
	value := options.integer('--timeout', fallback) or { return error_with_code('invalid integer for --timeout', 2) }
	if value <= 0 { return error_with_code('timeout must be positive', 2) }
	return value
}
pub fn mkdir(path string) ! {
	if path.contains('\x00') { return error('embedded null byte') }
	if os.is_dir(path) { return }
	parent := path.trim_right('/').all_before_last('/')
	if parent != '' && parent != path { mkdir(parent)! }
	os.mkdir(path) or { if !os.is_dir(path) { return err } }
}
fn pause(seconds f64) ! {
	end := f64(time.sys_mono_now()) / 1e9 + seconds
	for f64(time.sys_mono_now()) / 1e9 < end {
		policyhost.command_checkpoint()!
		left := end - f64(time.sys_mono_now()) / 1e9
		if left > 0 { time.sleep(time.Duration(if left < 0.025 { left } else { 0.025 } * 1e9)) }
	}
	policyhost.command_checkpoint()!
}
fn run(argv []string) ! { policyhost.inherited(argv)! }
fn say(line string) { println(line); flush_stdout() }

// copytree(dirs_exist_ok=True, symlinks=True): merge directories, retain
// literal link targets (including dangling links), copy file metadata, then
// restore each directory's source metadata after its children.
pub fn stage_tree(source string, destination string) ! {
	policyhost.command_checkpoint()!
	mkdir(destination)!
	for name in os.ls(source)! {
		input := source + '/' + name
		output := destination + '/' + name
		if os.is_link(input) {
			os.symlink(os.readlink(input)!, output)!
			hosttest.module_copy_link_stat(input, output)!
		} else if os.is_dir(input) {
			stage_tree(input, output)!
		} else {
			hosttest.module_copy_file_preserving_stat(input, output)!
		}
	}
	hosttest.module_copy_directory_stat(source, destination)!
}

fn flags(sysroot string) []string {
	return [os.getenv_opt('CC') or { 'clang' }, '--target=aarch64-linux-musl', '--sysroot=' + sysroot,
		'-static', '-O2', '-fno-stack-protector', '-Wall', '-Wextra', '-Werror']
}

pub fn compile_guest(kind string, work string, sysroot string, prebuilt string) !string {
	init := work + '/init'
	if prebuilt != '' { hosttest.module_copy_file_preserving_stat(prebuilt, init)!; return init }
	mut options := flags(sysroot)
	mut source := guesthost.root() + '/tests/ps1/guest.c'
	if kind != 'ps1' {
		options << ['-D_GNU_SOURCE', '-fno-strict-aliasing']
		source = work + '/fixture.o'
		guesthost.compile_module(guesthost.root() + '/tests/' + kind + '/guestfixture', source,
			'aarch64', [...options, '-L' + sysroot + '/lib', '-fuse-ld=lld'])!
	}
	run([...options, source, '-L' + sysroot + '/lib', '-fuse-ld=lld', '-o', init])!
	return init
}
