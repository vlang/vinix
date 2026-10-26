// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import guesthost
import hosttest
import json2
import os

struct Preparation {
	format int = 1
	architecture string
	fixture_sha256 string
	serial_source_sha256 map[string]string
	compiler_path string
	compiler_sha256 string
	init_sha256 string
}

struct Receipt {
	format int = 1
	architecture string
	context string = 'native musl fixture in QEMU; fixed overflow identity policy only'
	preparation_sha256 string
	kernel_sha256 string
	init_sha256 string
	serial_sha256 string
	exit_code int
	detail string
}

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn verify_elf(bytes []u8, arch string) ! {
	machine := if bytes.len >= 20 { int(bytes[18]) + (int(bytes[19]) << 8) } else { 0 }
	if bytes.len < 20 || bytes[..6] != [u8(127), `E`, `L`, `F`, 2, 1]
		|| machine != if arch == 'aarch64' { 183 } else { 62 } {
		return error('expected matching little-endian ELF64 for ' + arch)
	}
}

fn serial_inventory(source string) !map[string]string {
	mut inputs := map[string]string{}
	for path in os.ls(source)! {
		if path.ends_with('.v') { inputs[path] = digest(source + '/' + path)! }
	}
	return inputs
}

fn prepare_fixture(source string, state string, arch string) !(string, string, string) {
	compiler := os.find_abs_path_of_executable(if arch == 'aarch64' {
		os.getenv_opt('CC_AARCH64') or { 'aarch64-linux-musl-gcc' }
	} else {
		os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }
	})!
	pin := digest(compiler)!
	flags := [compiler, '-D_GNU_SOURCE', '-static', '-pthread', '-O2', '-fno-stack-protector',
		'-fno-strict-aliasing', '-Wall', '-Wextra', '-Werror']
	guesthost.compile_module(guesthost.root() + '/tests/kernel-gaps/serialcore', state + '/serial.o', arch, flags)!
	guesthost.compile_module(os.dir(source), state + '/fixture.o', arch, flags)!
	init := state + '/init'
	command := [...flags, state + '/serial.o', state + '/fixture.o', '-o', init]
	result := os.exec(command)
	os.write_file(state + '/link.log', result.output)!
	os.write_file(state + '/link-command.json', json2.encode(command, prettify: true) + '\n')!
	if result.exit_code != 0 { return error('fixture link failed; see link.log') }
	if digest(compiler)! != pin { return error('cross compiler changed during preparation') }
	return init, compiler, pin
}

fn run() !int {
	options := guesthost.parse(os.args[1..], [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--prepared-dir', value: true },
		hosttest.Option{ name: '--prepare-only' },
		hosttest.Option{ name: '--timeout', value: true },
	], [], 'Usage: run.v --arch aarch64|x86_64 --state-dir FRESH-ABS-DIR [--prepare-only | --kernel-dir DIR --prepared-dir DIR] [--timeout SECONDS]')!
	for required in ['--arch', '--state-dir'] {
		if !options.has(required) { return error('missing ' + required) }
	}
	arch := options.value('--arch', '')
	state := options.value('--state-dir', '')
	if !os.is_abs_path(state) || os.exists(state) { return error('state directory must be fresh and absolute') }
	preparing := options.has('--prepare-only')
	if preparing && (options.has('--kernel-dir') || options.has('--prepared-dir')) {
		return error('--prepare-only cannot run a kernel or reuse a preparation')
	}
	if !preparing && (!options.has('--kernel-dir') || !options.has('--prepared-dir')) {
		return error('guest execution requires --kernel-dir and --prepared-dir')
	}
	timeout := options.integer('--timeout', 180)!
	if timeout <= 0 { return error('timeout must be positive') }
	source := os.dir(@FILE) + '/fixture/core.v'
	fixture := os.read_bytes(source)!
	os.mkdir_all(state + '/fixture')!
	os.write_file_array(state + '/fixture/core.v', fixture)!
	if preparing {
		os.mkdir_all(state + '/build')!
		serial := guesthost.root() + '/tests/kernel-gaps/serialcore'
		serial_inputs := serial_inventory(serial)!
		init, compiler, compiler_pin := prepare_fixture(state + '/fixture/core.v', state + '/build', arch)!
		verify_elf(os.read_bytes(init)!, arch)!
		// Catch concurrent source changes while the shared serial helper compiled.
		if serial_inventory(serial)! != serial_inputs { return error('serial helper changed during compilation') }
		prepared := Preparation{ architecture: arch, fixture_sha256: sha256.sum(fixture).hex(),
			serial_source_sha256: serial_inputs, compiler_path: compiler,
			compiler_sha256: compiler_pin, init_sha256: digest(init)! }
		os.write_file(state + '/preparation.json', json2.encode(prepared, prettify: true) + '\n')!
		println('PROCFS OVERFLOW PREPARED: ' + init)
		return 0
	}
	prepared_dir := os.real_path(options.value('--prepared-dir', ''))
	prepared_text := os.read_file(prepared_dir + '/preparation.json')!
	prepared := json2.decode[Preparation](prepared_text)!
	if prepared.format != 1 || prepared.architecture != arch
		|| prepared.fixture_sha256 != sha256.sum(fixture).hex()
		|| digest(prepared_dir + '/fixture/core.v')! != prepared.fixture_sha256 {
		return error('preparation does not match current fixture and requested architecture')
	}
	init_bytes := os.read_bytes(prepared_dir + '/build/init')!
	verify_elf(init_bytes, arch)!
	if sha256.sum(init_bytes).hex() != prepared.init_sha256 { return error('prepared init checksum mismatch') }
	kernel := os.read_bytes(options.value('--kernel-dir', '') + '/bin/vinix')!
	verify_elf(kernel, arch)!
	os.mkdir_all(state + '/kernel/bin')!
	os.write_file_array(state + '/kernel/bin/vinix', kernel)!
	os.write_file_array(state + '/init', init_bytes)!
	os.write_file(state + '/preparation.json', prepared_text)!
	mut detail := ''
	code := guesthost.guest('', state + '/init', state + '/guest', state + '/kernel', arch,
		['PROCFS OVERFLOW: root reads/writes/truncation/repeat/namespace guards PASS',
		 'PROCFS OVERFLOW: UID10000 reads/writes/retained descriptors/repeat/namespace guards PASS',
		 'PROCFS OVERFLOW: PASS'], ['PROCFS OVERFLOW FAIL:'], false, true, timeout) or {
		detail = err.msg()
		1
	}
	receipt := Receipt{ architecture: arch, preparation_sha256: digest(state + '/preparation.json')!,
		kernel_sha256: sha256.sum(kernel).hex(), init_sha256: prepared.init_sha256,
		serial_sha256: digest(state + '/guest/serial.log') or { '' }, exit_code: code, detail: detail }
	os.write_file(state + '/receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	println('PROCFS OVERFLOW RECEIPT: ' + state + '/receipt.json')
	return code
}

fn main() {
	code := run() or { eprintln(err.msg()); exit(2) }
	exit(code)
}
