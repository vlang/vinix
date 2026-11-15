// SPDX-License-Identifier: GPL-2.0-or-later
// Compile the production initializer and syscall-wrapped failure/handoff probe.
module main

import crypto.sha256
import hwhost
import json2
import os
import perfproducer

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn execute(args []string, state string, name string) ! {
	os.write_file(state + '/' + name + '.argv.json', json2.encode(args) + '\n')!
	hwhost.run_tool(args, {}, state + '/' + name + '.log', 300)!
}

fn build(compiler string, root string, support string, state string, arch string) ! {
	if arch !in ['aarch64', 'x86_64'] || os.exists(state) || os.is_link(state) {
		return error('supported architecture and fresh state required')
	}
	os.mkdir_all(state)!
	mut inputs := map[string]string{}
	for path in [compiler, os.executable(), @FILE, root + '/tests/desktop-perf/perfproducer/core.v',
		root + '/tests/desktop-perf/initfixture/core.v', root + '/tests/kernel-gaps/serialcore/core.v',
		root + '/build-support/compile-v-module', root + '/build-support/run-v-tool.sh',
		root + '/build-support/find-v.sh', root + '/tests/linuxkpi/generate_module.v'] {
		inputs[path] = digest(path)!
	}
	for directory in ['tools/hosttest', 'tests/linuxkpi/hosttest', 'tests/hardware-platform/hwhost'] {
		for extension in ['.v', '.h'] {
			for path in os.walk_ext(root + '/' + directory, extension) { inputs[path] = digest(path)! }
		}
	}
	source := perfproducer.generate_init(compiler, root, state, arch)!
	inputs[root + '/tests/desktop-perf/' + if arch == 'aarch64' {
		'arm-init/main.v'
	} else {
		'x86-init/main.v'
	}] = digest(state + '/init-source.v')!
	mut cc := [os.find_abs_path_of_executable(if arch == 'aarch64' {
		'clang'
	} else {
		'x86_64-linux-musl-gcc'
	})!]
	inputs[cc[0]] = digest(cc[0])!
	if arch == 'aarch64' {
		cc << ['--target=aarch64-linux-musl', '--sysroot=' + support + '/sdk',
			'--gcc-install-dir=' + support + '/sdk/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0',
			'-fno-stack-protector']
	}
	cc << ['-D_GNU_SOURCE', '-static', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
		'-Wno-unused-parameter']
	mut linker := []string{}
	if arch == 'aarch64' { linker << ['-fuse-ld=lld', '-L' + support + '/sdk/lib'] }
	execute([...cc, ...linker, source, '-o', state + '/init'], state, 'link-init')!
	execute([...cc, '-Dmain=perf_init_under_test', '-c', source, '-o', state + '/init.o'], state, 'compile-init')!
	for name, module_dir in {
		'fixture': root + '/tests/desktop-perf/initfixture'
		'serial':  root + '/tests/kernel-gaps/serialcore'
	} {
		argv := [root + '/build-support/compile-v-module', module_dir, state + '/' + name + '.c',
			'--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'nofloat']
		os.write_file(state + '/generate-' + name + '.argv.json', json2.encode(argv) + '\n')!
		hwhost.run_tool(argv, {
			'VINIX_V_COMPILER': compiler
		}, state + '/generate-' + name + '.log', 300)!
		execute([...cc, '-c', state + '/' + name + '.c', '-o', state + '/' + name + '.o'], state, 'compile-' + name)!
	}
	mut link := [...cc, ...linker, state + '/init.o', state + '/fixture.o', state + '/serial.o']
	for name in ['open', 'dup2', 'close', 'mkdir', 'mount', 'access', 'execv'] {
		link << '-Wl,--wrap=' + name
	}
	link << ['-o', state + '/probe']
	execute(link, state, 'link-probe')!
	for path, pin in inputs { if digest(path)! != pin { return error('changed input: ' + path) } }
	os.write_file(state + '/receipt.json', json2.encode({
		'architecture': json2.Any(arch)
		'inputs':       json2.decode[json2.Any](json2.encode(inputs))!
		'init':         digest(state + '/init')!
		'probe':        digest(state + '/probe')!
	},
		prettify: true
	) + '\n')!
}

fn check_text(raw string, arch string) ! {
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported architecture') }
	text := raw.replace('\r', '')
	if text.contains('KERNEL PANIC') || text.contains('FATAL EXCEPTION') || text.contains('PERFINIT: FAIL') {
		return error('failed guest')
	}
	rows := text.split_into_lines().filter(it.starts_with('LINUX PERFINIT'))
	if rows.len != 13 { return error('incomplete or duplicate initializer verdicts') }
	for index in 0 .. 11 {
		stage := match index {
			0 { 1 }
			1 { 2 }
			2 { 3 }
			3 { 5 }
			5, 6 { 7 }
			else { 8 }
		}
		if rows[index] != 'LINUX PERFINIT CASE: mode=${index} stage=${stage} failures=0' {
			return error('initializer case differs')
		}
	}
	if rows[11] != 'LINUX PERFINIT SUMMARY: cases=11 checks=113 failures=0' || rows[12] != 'LINUX PERFINIT: PASS' {
		return error('initializer summary differs')
	}
	label := if arch == 'aarch64' { 'arm' } else { 'x86' }
	for line in ['PERF-ERROR ${label} mkdir /root failed errno=13',
		'PERF-ERROR ${label} ext2 /root mount failed errno=5 device_present=false',
		'PERF-ERROR ${label} ext2 /root mount failed errno=5 device_present=true',
		'PERF-ERROR ${label} perf-init exec failed'] {
		if text.split_into_lines().filter(it == line).len != 1 {
			return error('initializer diagnostic differs')
		}
	}
	device := if arch == 'aarch64' { '/dev/vda' } else { '/dev/sd0' }
	banner := 'PERF-${label.to_upper()} root=${device} filesystem=ext2 resolution=2048x1536'
	if text.split_into_lines().filter(it == banner).len != 5
		|| text.split_into_lines().filter(it.starts_with('PERF-')).len != 9 {
		return error('initializer banner/diagnostic count differs')
	}
}

fn controls(text string, arch string) ! {
	check_text(text, arch)!
	mut bad := [text + '\nKERNEL PANIC\n', text + '\nFATAL EXCEPTION\n',
		text.replace('PERFINIT: PASS', 'PERFINIT: FAIL'),
		text.replace('checks=113', 'checks=112'), text.replace('cases=11', 'cases=10'),
		text.replace('errno=5', 'errno=2'), text.replace('device_present=false', 'device_present=true'),
		text.replace('resolution=2048x1536', 'resolution=1x1'),
		text + '\nPERF-ERROR unexpected\n', text.replace('failures=0', 'failures=1')]
	for line in text.replace('\r', '').split_into_lines().filter(it.starts_with('LINUX PERFINIT')) {
		bad << text.replace('\r', '').replace(line + '\n', '')
		bad << text + '\n' + line + '\n'
	}
	for candidate in bad {
		check_text(candidate, arch) or { continue }
		return error('invalid initializer transcript accepted')
	}
	println('Initializer checker: 1 positive and ${bad.len} negative controls PASS')
}

fn run() ! {
	if os.args.len == 7 && os.args[1] == 'build' {
		build(os.args[2], os.real_path(os.args[3]), os.real_path(os.args[4]), os.abs_path(os.args[5]), os.args[6])!
	} else if os.args.len == 4 && os.args[1] in ['check', 'controls'] {
		text := os.read_file(os.args[2])!
		if os.args[1] == 'controls' { controls(text, os.args[3])! }
		else { check_text(text, os.args[3])! }
	} else {
		return error('usage: init-check build COMPILER ROOT SUPPORT FRESH_STATE ARCH | check|controls SERIAL ARCH')
	}
	println('Initializer qualification: PASS')
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
