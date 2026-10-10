// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <fcntl.h>
fn C.open(&char, i32, ...voidptr) i32
fn C.close(i32) i32
fn C.write(i32, voidptr, usize) i64

fn command(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 { return error('Command failed: ${args[0]}\n${result.output}') }
	return result.output
}

fn main() {
	mut options := map[string]string{}
	mut index := 1
	for index < os.args.len {
		name := os.args[index]
		if name !in ['--arch', '--staging', '--cc'] || index + 1 >= os.args.len || name in options {
			eprintln('Usage: stage.v --arch aarch64|x86_64 --staging DIRECTORY [--cc COMPILER]'); exit(2)
		}
		options[name] = os.args[index + 1]
		index += 2
	}
	arch := options['--arch']
	staging := os.real_path(options['--staging'])
	if arch !in ['aarch64', 'x86_64'] || options['--staging'] == '' || staging == '/' || !os.is_dir(staging) {
		eprintln('Select a supported architecture and an existing target directory'); exit(2)
	}
	mut cc := options['--cc']
	if cc == '' { cc = os.getenv('VINIX_MUSL_CC_' + arch.to_upper()) }
	if cc == '' { cc = arch + '-linux-musl-gcc' }
	stage(arch, staging, cc) or { eprintln(err); exit(1) }
}

fn stage(arch string, staging string, cc string) ! {
	root := os.dir(os.dir(os.dir(@FILE)))
	machine := command([cc, '-dumpmachine'])!
	if !machine.trim_space().starts_with(arch + '-') || !machine.contains('linux') {
		return error('Compiler architecture mismatch')
	}
	work := os.join_path(os.temp_dir(), 'vinix-volume-stage-' + os.getpid().str())
	os.mkdir(work)!
	defer { os.rmdir_all(work) or { eprintln(err) } }
	source := os.join_path(work, 'volume.c')
	command(['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v',
		root + '/tools/volumes/volumecli', source, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }])!
	generated := os.read_file(source)!
	os.write_file(source, generated + '\n_Static_assert(sizeof(volumecli__Request)==32, "V request ABI");\n_Static_assert(sizeof(volumecli__Status)==128, "V status ABI");\n_Static_assert(sizeof(volumecli__Health)==1088, "V health ABI");\n_Static_assert(offsetof(volumecli__Health,data)==576, "V health data ABI");\n')!
	binary := os.join_path(work, 'vinix-volume')
	command([cc, '-static', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label', '-D_GNU_SOURCE',
		'-DVINIX_V_RUNTIME', '-I', root + '/tools/volumes/volumecli', source, '-o', binary])!
	data := os.read_bytes(binary)!
	expected := if arch == 'aarch64' { 183 } else { 62 }
	if data.len < 20 || data[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] || int(data[18]) | (int(data[19]) << 8) != expected {
		return error('Volume utility ELF architecture mismatch')
	}
	directory := os.join_path(staging, 'usr/sbin')
	os.mkdir_all(directory)!
	temporary := os.join_path(directory, '.vinix-volume-' + os.getpid().str())
	// Exclusive creation keeps a preexisting link or another publisher untouched.
	fd := unsafe { C.open(temporary.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, u32(0o755)) }
	if fd < 0 { return error('Cannot create staging temporary file') }
	defer { os.rm(temporary) or {} }
	mut written := i64(0)
	for written < data.len {
		count := unsafe { C.write(fd, &data[written], usize(data.len - written)) }
		if count <= 0 { C.close(fd); return error('Cannot write staging binary') }
		written += count
	}
	if C.close(fd) != 0 { return error('Cannot close staging binary') }
	os.chmod(temporary, 0o755)!
	os.rename(temporary, os.join_path(directory, 'vinix-volume'))!
	println('Staged vinix-volume (${arch}).')
}
