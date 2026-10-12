// SPDX-License-Identifier: GPL-2.0-or-later
module boottools

import cachecli
import crypto.sha256
import hosttest
import os
import sourcecommand
import time

pub fn here() string { return os.real_path(@DIR + '/..') }

pub fn repo() string { return os.dir(here()) }

pub fn path_value(path string) string { return if path == '' { '.' } else { path } }

pub fn path_env(name string, fallback string) string {
	return path_value(os.getenv_opt(name) or { fallback })
}

pub fn path_option(args cachecli.Arguments, key string, fallback string) string {
	return if key in args.options { path_value(args.value(key, '')) } else { fallback }
}

pub fn llvm() string { return path_env('LLVM_BIN', '/opt/homebrew/opt/llvm/bin') }

pub fn command(argv []string) !sourcecommand.Output {
	cachecli.checkpoint()!
	result := sourcecommand.capture(argv, os.environ(), -1, 64 * 1024 * 1024, cachecli.cancelled)!
	print(result.stdout)
	eprint(result.stderr)
	if result.status != 0 {
		return error('command failed (' + result.status.str() + '): ' + argv.join(' '))
	}
	return result
}

pub fn build_initramfs(work string) !string {
	sysroot := path_env('VINIX_AARCH64_SYSROOT', repo() + '/build-aarch64-userland/sysroot')
	root := work + '/rootfs'
	for path in ['sbin', 'dev', 'proc'] { os.mkdir_all(root + '/' + path)! }
	generated := work + '/report_init.c'
	command([repo() + '/build-support/compile-v-module', here() + '/reportcore', generated, '--arch',
		'arm64'])!
	command([llvm() + '/clang', '--target=aarch64-linux-musl', '--sysroot=' + sysroot, '-static',
		'-O2', '-Wall', '-Wextra', '-Werror', '-fuse-ld=lld', '-Wno-unused-function',
		'-Wno-unused-label', '-Wno-unused-parameter', '-L' + sysroot + '/lib', generated, '-o',
		root + '/sbin/init'])!
	archive := work + '/initramfs.tar'
	mut environment := os.environ()
	environment['COPYFILE_DISABLE'] = '1'
	result := sourcecommand.capture(['tar', '--format=ustar', '-cf', archive, '-C', root, '.'], environment, -1, 64 * 1024 * 1024, cachecli.cancelled)!
	if result.status != 0 { return error('tar failed: ' + result.stderr) }
	return archive
}

pub fn packed_image(kernel string, initramfs string, cmdline string, flags u32, stamp u64) ![]u8 {
	loader := os.read_bytes(here() + '/build/vinix-apple-loader.bin')!
	loader_end := elf_symbol(os.read_bytes(here() + '/build/vinix-apple-loader.elf')!, 'loader_end')!
	return pack(loader, loader_end, os.read_bytes(kernel)!, os.read_bytes(initramfs)!, cmdline, flags, stamp)
}

fn mtime(path string) !i64 { return hosttest.bounds_file_state(path)!['st_mtime_ns']!.i64() }

fn newer_sources(directory string, built i64, mut found []string) ! {
	for name in os.ls(directory)! {
		path := directory + '/' + name
		if name == 'obj' || (os.is_link(path) && os.is_dir(path)) { continue }
		if os.is_dir(path) {
			newer_sources(path, built, mut found)!
		} else if name.ends_with('.v') && mtime(path)! > built {
			found << path
		}
	}
}

pub fn build_cli(argv []string) int {
	args := cachecli.arguments(output_option(argv), ['--kernel', '--initramfs', '--cmdline', '--output'], []string{}, []string{}, 0, 0, 'usage: build [--kernel ELF --initramfs TAR --cmdline TEXT -o IMAGE]') or {
		eprintln(err)
		return 2
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	build_options(args) or {
		eprintln(err)
		return if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 }
	}
	return 0
}

fn build_options(args cachecli.Arguments) ! {
	kernel := path_option(args, '--kernel', path_env('VINIX_KERNEL_DIR', repo() + '/kernel') + '/bin/vinix')
	if !os.is_file(kernel) {
		return error(kernel + ': no kernel; build it with make -C kernel CC=clang ARCH=aarch64 LIMINE_MP=1')
	}
	mut newer := []string{}
	sources := os.dir(os.dir(os.abs_path(kernel)))
	newer_sources(sources, mtime(kernel)!, mut newer)!
	if newer.len > 0 {
		eprintln('warning: ' + newer.len.str() + ' kernel sources are newer than ' + kernel + ', e.g. ' + newer[0][sources.len + 1..])
	}
	command(['make', '-C', here(), '-s'])!
	work := sourcecommand.temporary('vinix-apple-build')!
	defer { os.rmdir_all(work) or {} }
	initramfs := if '--initramfs' in args.options {
		path_option(args, '--initramfs', '')
	} else {
		build_initramfs(work)!
	}
	cmdline := args.value('--cmdline', 'vinix.apple_speakers=0')
	data := packed_image(kernel, initramfs, cmdline, 0, u64(time.now().unix()))!
	output := path_option(args, '--output', here() + '/build/vinix-apple.bin')
	os.mkdir_all(os.dir(output))!
	os.write_file_array(output, data)!
	println(output + ': ' + data.len.str() + ' bytes, sha256 ' + sha256.sum(data).hex())
	println('  kernel ' + kernel)
	println('  cmdline ' + quoted(cmdline))
}

fn quoted(text string) string {
	quote := if text.contains("'") && !text.contains('"') { '"' } else { "'" }
	return quote + text.replace('\\', '\\\\').replace(quote, '\\' + quote).replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t') + quote
}
