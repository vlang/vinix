// SPDX-License-Identifier: GPL-2.0-or-later
// Build the diagnostic controller with the available V, retaining actual inputs.
module main

import crypto.sha256
import json2
import os

fn command(argv []string, log string) !string {
	os.write_file(log + '.argv.json', json2.encode(argv, prettify: true))!
	result := os.exec(argv)
	os.write_file(log, result.output)!
	os.write_file(log + '.exit', result.exit_code.str())!
	if result.exit_code != 0 { return error('command failed; see ' + log) }
	return result.output
}

fn checksum(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	defer { unsafe { digest.free(); free(digest) } }
	mut buffer := []u8{len: 65536}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	mut result := []u8{len: 32}
	defer { unsafe { result.free() } }
	digest.checksum_into(mut result)
	return result.hex()
}

fn build(root string) ! {
	if os.exists(root) { return error('fresh output required') }
	os.mkdir_all(root + '/inputs')!
	v := '/Users/alex/code/v/v'
	repo := os.real_path(os.dir(@FILE) + '/../..')
	source := repo + '/tests/native-android-ws/maps-account-guest.v'
	os.setenv('VEXE', v, true)
	os.chdir(repo)!
	imports := '@vlib|' + repo + '/tests/native-android-ws|' + repo + '/tests/linuxkpi|' + repo + '/build-support/android'
	common := [v, '-new-compiler', '-no-parallel', '-gc', 'none', '-nocache', '-path', imports]
	arm := ['-os', 'linux', '-arch', 'arm64', '-cc', '/opt/homebrew/bin/aarch64-linux-musl-gcc', '-cflags', '-static -no-pie']
	command([v, 'version'], root + '/v-version.log')!
	mut inputs := map[string]string{}
	for target in [ []string{}, arm ] {
		mut argv := common.clone()
		argv << target
		argv << ['-print-v-files', source]
		listing := command(argv, root + '/listing-' + inputs.len.str() + '.log')!
		for line in listing.split_into_lines() {
			path := line.trim_space()
			if !path.ends_with('.v') || !os.is_file(path) { continue }
			inputs[os.real_path(path)] = ''
		}
	}
	inputs[v] = ''
	inputs[@FILE] = ''
	for path, _ in inputs {
		inputs[path] = checksum(path)!
		destination := root + '/inputs/' + path.trim_left('/')
		os.mkdir_all(os.dir(destination))!
		os.cp(path, destination)!
		if checksum(destination)! != inputs[path] { return error('input copy changed: ' + path) }
	}
	os.write_file(root + '/input-sha256.json', json2.encode(inputs, prettify: true))!
	mut host_command := common.clone()
	host_command << ['-cc', 'cc', '-o', root + '/host', source]
	command(host_command, root + '/host-build.log')!
	command([root + '/host', '--self-test'], root + '/self-test.log')!
	mut arm_command := common.clone()
	arm_command << arm
	arm_command << ['-showcc', '-keepc', '-o', root + '/maps-account-guest', source]
	command(arm_command, root + '/arm-build.log')!
	elf := os.read_bytes(root + '/maps-account-guest')!
	if elf.len < 64 || elf[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] || elf[18..20] != [u8(183), 0] {
		return error('AArch64 ELF64 required')
	}
	for path, expected in inputs {
		if checksum(path)! != expected { return error('input changed: ' + path) }
	}
	os.write_file(root + '/output.sha256', sha256.sum(elf).hex() + '\n')!
	println('CURRENT-MAPS-CONTROLLER-BUILD-PASS ' + root)
}

fn main() {
	if os.args.len != 2 { eprintln('usage: build-current-maps-controller FRESH_ROOT'); exit(2) }
	build(os.abs_path(os.args[1])) or { eprintln(err); exit(1) }
}
