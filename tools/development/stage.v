// SPDX-License-Identifier: GPL-2.0-or-later
module main

import devcore
import json2
import os

struct Receipt {
	schema       int = 1
	architecture string
	host         string
	v            devcore.Pin
	cc           devcore.Pin
	cc_argv      []string
mut:
	complete bool
	binaries map[string]string
}

fn stage() ! {
	args := os.args[1..]
	if args.len == 0 || args == ['--help'] {
		println('Usage: v run stage.v aarch64|x86_64 FRESH-STAGING-DIRECTORY [CC-ARGV-JSON]')
		return
	}
	if args.len !in [2, 3] || args[0] !in ['aarch64', 'x86_64'] {
		return error('invalid arguments; use --help')
	}
	architecture := args[0]
	mut cc := if args.len == 3 {
		json2.decode[[]string](args[2])!
	} else {
		[architecture + '-linux-musl-gcc']
	}
	if cc.len == 0 { return error('compiler argv must not be empty') }
	cc[0] = os.find_abs_path_of_executable(cc[0])!
	v := os.find_abs_path_of_executable(os.getenv_opt('VINIX_V_COMPILER') or { @VEXE })!
	repository := os.dir(os.dir(os.dir(@FILE)))
	devcore.fresh_directory(args[1])!
	output := os.real_path(args[1])
	work := output + '/.build'
	os.mkdir(work, mode: 0o700)!
	os.mkdir_all(output + '/usr/bin')!
	mut receipt := Receipt{
		architecture: architecture
		host:         os.uname().sysname
		v:            devcore.Pin{v, devcore.file_hash(v)!}
		cc:           devcore.Pin{cc[0], devcore.file_hash(cc[0])!}
		cc_argv:      cc
	}
	manifest := output + '/development-tools.json'
	os.write_file(manifest, json2.encode(receipt, prettify: true) + '\n')!
	for tool, source in {
		'vinix-build':   'build.v'
		'vinix-vm':      'vm.v'
		'vinix-qualify': 'qualify.v'
		'vinix-jobs':    'jobs.v'
	} {
		println('Staging ${tool} for ${architecture}')
		c := work + '/' + tool + '.c'
		status := devcore.run([v, '-nocache', '-gc', 'none', '-enable-globals', '-d', 'no_backtrace',
			'-d', 'no_segfault_handler', '-os', 'linux', '-arch',
			if architecture == 'aarch64' { 'arm64' } else { 'amd64' }, '-o', c,
			repository + '/tools/development/' + source], repository, devcore.environment(0), 300, work + '/' + tool + '-v.log')!
		if status != 0 { return error('V translation failed; see ${work}') }
		binary := output + '/usr/bin/' + tool
		linked := devcore.run([...cc, '-static', '-O2', '-std=gnu11', '-D_GNU_SOURCE', c, '-o',
			binary, '-lm', '-lpthread'],
			repository, devcore.environment(0), 300, work + '/' + tool + '-cc.log')!
		if linked != 0 { return error('native link failed; see ${work}') }
		mut file := os.open(binary)!
		mut header := []u8{len: 20}
		count := file.read(mut header)!
		file.close()
		machine := int(header[18]) | int(header[19]) << 8
		if count != 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
			|| machine != if architecture == 'aarch64' { 183 } else { 62 } {
			return error('wrong ELF target: ${tool}')
		}
		os.chmod(binary, 0o755)!
		receipt.binaries[tool] = devcore.file_hash(binary)!
		os.write_file(manifest, json2.encode(receipt, prettify: true) + '\n')!
	}
	devcore.verify(receipt.v)!
	devcore.verify(receipt.cc)!
	receipt.complete = true
	os.write_file(manifest, json2.encode(receipt, prettify: true) + '\n')!
	os.rmdir_all(work)!
}

fn main() {
	stage() or {
		eprintln(err)
		exit(1)
	}
}
