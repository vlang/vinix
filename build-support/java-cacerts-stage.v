// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

fn C.rename(&char, &char) int
fn C.open(&char, int, ...int) int
fn C.write(int, voidptr, usize) i64
fn C.close(int) int

fn command(arguments []string) !string {
	result := os.exec(arguments)
	if result.exit_code != 0 { return error('${arguments[0]} failed: ${result.output}') }
	return result.output
}

fn stage(arch string, staging string, cc string) ! {
	root := os.dir(os.dir(@FILE))
	machine := command([cc, '-dumpmachine'])!.trim_space()
	if !machine.starts_with(arch + '-') || !machine.contains('linux') || !machine.contains('musl') {
		return error('expected a ${arch} Linux musl compiler, got ${machine}')
	}
	work := os.join_path(os.temp_dir(), 'vinix-java-cacerts-stage-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or { eprintln(err) } }
	// Use the same compiler discovery as all maintained host entry points.
	v := command(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'stage', root])!
	source := os.join_path(work, 'java-cacerts.c')
	command([v, '-nocache', '-os', 'linux', '-arch', if arch == 'aarch64' {
		'arm64'
	} else {
		'amd64'
	}, '-gc', 'none', '-d', 'glibc', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-o', source,
		os.join_path(root, 'build-support/java-cacerts.v')])!
	binary := os.join_path(work, 'java-cacerts')
	command([cc, '-static', '-O2', '-D_GNU_SOURCE', source, '-pthread', '-lm', '-o', binary])!
	data := os.read_bytes(binary)!
	expected := if arch == 'aarch64' { 183 } else { 62 }
	if data.len < 64 || data[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| int(data[18]) | (int(data[19]) << 8) != expected {
		return error('Java trust-store utility ELF architecture mismatch')
	}
	directory := os.join_path(staging, 'usr/libexec/vinix-minecraft')
	os.mkdir_all(directory)!
	temporary := os.join_path(directory, '.java-cacerts-${os.getpid()}')
	// Exclusive creation avoids following a preexisting staging link.
	mut fd := unsafe { C.open(temporary.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, 0o755) }
	if fd < 0 { return error('cannot create staging temporary file') }
	defer {
		if fd >= 0 { C.close(fd) }
		os.rm(temporary) or {}
	}
	mut written := 0
	for written < data.len {
		count := unsafe { C.write(fd, &data[written], usize(data.len - written)) }
		if count < 0 && C.errno == C.EINTR { continue }
		if count <= 0 { return error('cannot write staging Java trust-store utility') }
		written += int(count)
	}
	closed := C.close(fd)
	fd = -1
	if closed != 0 { return error('cannot close staging Java trust-store utility') }
	os.chmod(temporary, 0o755)!
	destination := os.join_path(directory, 'java-cacerts')
	if unsafe { C.rename(temporary.str, destination.str) } != 0 {
		return error('cannot publish Java trust-store utility')
	}
	// Cached layers may still contain the retired interpreter wrapper.
	os.rm(os.join_path(directory, 'java-cacerts.py')) or {}
	println('Staged java-cacerts (${arch}).')
}

fn main() {
	mut options := map[string]string{}
	mut index := 1
	for index < os.args.len {
		name := os.args[index]
		if name !in ['--arch', '--staging', '--cc'] || index + 1 >= os.args.len || name in options {
			eprintln('Usage: stage.v --arch aarch64|x86_64 --staging DIRECTORY [--cc COMPILER]')
			exit(2)
		}
		options[name] = os.args[index + 1]
		index += 2
	}
	arch := options['--arch']
	staging := os.real_path(options['--staging'])
	if arch !in ['aarch64', 'x86_64'] || options['--staging'] == '' || staging == '/' || !os.is_dir(staging) {
		eprintln('Select a supported architecture and an existing target directory')
		exit(2)
	}
	mut cc := options['--cc']
	if cc == '' { cc = os.getenv('VINIX_MUSL_CC_' + arch.to_upper()) }
	if cc == '' { cc = arch + '-linux-musl-gcc' }
	stage(arch, staging, cc) or {
		eprintln(err)
		exit(1)
	}
}
