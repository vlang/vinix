// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hosttest
import json2
import os

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn command(state string, label string, arguments []string) !string {
	executable := os.find_abs_path_of_executable(arguments[0])!
	pin := hash(executable)!
	result := os.exec(arguments)
	os.write_file(state + '/' + label + '.log', result.output)!
	os.write_file(state + '/' + label + '-command.json', json2.encode({
		'argv':              json2.Any(arguments)
		'executable':        json2.Any(executable)
		'executable_sha256': json2.Any(pin)
		'exit_code':         json2.Any(result.exit_code)
	}, prettify: true) + '\n')!
	if hash(executable)! != pin { return error('tool changed during command') }
	if result.exit_code != 0 { return error(label + ' failed; retained command and log') }
	return result.output
}

fn retain(state string, path string, mut pins map[string]string) ! {
	canonical := os.real_path(path)
	if !os.is_abs_path(canonical) || !os.is_file(canonical) {
		return error('missing build input: ' + path)
	}
	pin := hash(canonical)!
	if canonical in pins {
		if pins[canonical]! != pin { return error('build input changed: ' + canonical) }
		return
	}
	target := state + '/inputs' + canonical
	os.mkdir_all(os.dir(target))!
	os.cp(canonical, target)!
	if hash(target)! != pin { return error('copy changed: ' + canonical) }
	pins[canonical] = pin
}

fn inventory(root string, relative string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('unexpected artifact type: ' + key) }
		}
	}
}

fn build() ! {
	if os.args.len != 4 {
		return error('usage: pidfdwait-build V_COMPILER ARM64_MUSL_SYSROOT FRESH_EXTERNAL_ROOT')
	}
	compiler, sdk, state := os.real_path(os.args[1]), os.real_path(os.args[2]), os.abs_path(os.args[3])
	repo := hosttest.root()
	if os.exists(state) || os.is_link(state) || state == repo || state.starts_with(repo + '/') {
		return error('fresh external artifact root required')
	}
	if !os.is_file(compiler) || !os.is_file(sdk + '/lib/libc.a') {
		return error('compiler and musl sysroot required')
	}
	os.mkdir_all(state)!
	if os.real_path(state) != state { return error('canonical artifact root required') }
	os.setenv('VINIX_V_COMPILER', compiler, true)
	os.setenv('V', compiler, true)
	os.setenv('VINIX_AARCH64_SYSROOT', sdk, true)
	mut sources := map[string]string{}
	for directory in ['tests/linux-compat/pidfdwaitfixture', 'tests/kernel-gaps/serialcore',
		'tests/native-guest-tools/guesthost', 'tests/native-guest-tools/hosttest',
		'tests/native-guest-tools/fixturehost', 'tests/native-guest-tools/policyhost'] {
		for path in os.walk_ext(repo + '/' + directory, '.v') {
			relative := path[repo.len + 1..]
			target := state + '/source/' + relative
			os.mkdir_all(os.dir(target))!
			os.cp(path, target)!
			sources[relative] = hash(target)!
		}
	}
	for relative in ['tests/linux-compat/pidfdwait-build.v', 'tests/linuxkpi/generate_module.v',
		'build-support/compile-v-module', 'build-support/run-v-tool.sh', 'build-support/find-v.sh'] {
		target := state + '/source/' + relative
		os.mkdir_all(os.dir(target))!
		os.cp(repo + '/' + relative, target)!
		sources[relative] = hash(target)!
	}
	os.write_file(state + '/source-inputs.json', json2.encode(sources, prettify: true) + '\n')!
	mut artifacts := map[string]string{}
	mut consumed := map[string]string{}
	retain(state, compiler, mut consumed)!
	for arch in ['aarch64', 'x86_64'] {
		work := state + '/' + arch
		os.mkdir(work)!
		cross := os.find_abs_path_of_executable(arch + '-linux-musl-gcc')!
		retain(state, cross, mut consumed)!
		for tool in ['cc1', 'collect2', 'as', 'ld'] {
			candidate := command(work, 'tool-' + tool, [cross, '-print-prog-name=' + tool])!.trim_space()
			retain(state, os.find_abs_path_of_executable(candidate)!, mut consumed)!
		}
		command(work, 'specs', [cross, '-dumpspecs'])!
		mut objects := []string{}
		flags := [cross, '-D_GNU_SOURCE', '-static', '-pthread', '-O2', '-fno-stack-protector',
			'-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter',
			'-fno-strict-aliasing']
		for label in ['fixture', 'serial'] {
			module_dir := state + '/source/' + if label == 'fixture' {
				'tests/linux-compat/pidfdwaitfixture'
			} else {
				'tests/kernel-gaps/serialcore'
			}
			generated := work + '/' + label + '.c'
			generated_result := hosttest.generate_module_capture(module_dir, generated, if arch == 'aarch64' {
				'arm64'
			} else {
				'amd64'
			}, ['nofloat'])!
			os.write_file(work + '/' + label + '-generate.log', generated_result.stdout + generated_result.stderr)!
			dependencies := command(work, label + '-headers', [...flags, '-M', '-MT', label, generated])!.replace('\\\n', ' ')
			for dependency in dependencies.all_after(':').fields() {
				if dependency.contains('\\') { return error('unsupported escaped dependency path') }
				retain(state, dependency, mut consumed)!
			}
			object := work + '/' + label + '.o'
			command(work, label + '-compile', [...flags, '-c', generated, '-o', object])!
			objects << object
		}
		executable := work + '/init'
		trace := command(work, 'link', [...flags, ...objects, '-Wl,-t', '-o', executable])!
		mut linked := 0
		for line in trace.split_into_lines() {
			path := line.trim_space()
			if !os.is_abs_path(path) || !os.is_file(path) { continue }
			retain(state, path, mut consumed)!
			linked++
		}
		if linked < 5 { return error('incomplete static link trace') }
		elf := command(work, 'elf', [arch + '-linux-musl-readelf', '-h', '-l', '-d', executable])!
		if elf.contains('INTERP') || elf.contains('(NEEDED)') {
			return error('fixture must be static')
		}
		bytes := os.read_bytes(executable)!
		machine := if bytes.len >= 20 { int(bytes[18]) | int(bytes[19]) << 8 } else { 0 }
		if bytes.len < 20 || bytes[..6] != [u8(127), `E`, `L`, `F`, 2, 1] || machine != if arch == 'aarch64' {
			183
		} else {
			62
		} {
			return error('unexpected executable architecture')
		}
		artifacts[arch] = hash(executable)!
	}
	for path, pin in consumed {
		if hash(path)! != pin || hash(state + '/inputs' + path)! != pin {
			return error('build input changed: ' + path)
		}
	}
	os.write_file(state + '/cross-inputs.json', json2.encode(consumed, prettify: true) + '\n')!
	for relative, pin in sources {
		if hash(repo + '/' + relative)! != pin || hash(state + '/source/' + relative)! != pin {
			return error('build source changed: ' + relative)
		}
	}
	os.write_file(state + '/build.json', json2.encode({
		'format':              json2.Any(1)
		'baseline_revision':   json2.Any('ecbd3964aff243304e16df45271c7de8dee4d2da')
		'v_compiler':          json2.Any(compiler)
		'v_compiler_sha256':   json2.Any(hash(compiler)!)
		'aarch64_sysroot':     json2.Any(sdk)
		'aarch64_libc_sha256': json2.Any(hash(sdk + '/lib/libc.a')!)
		'guest_executed':      json2.Any(false)
		'executables':         json2.Any(hosttest.string_map(artifacts))
		'coverage':            json2.Any('compiled native musl fixtures; runtime semantics require Linux reference and Vinix boots')
	}, prettify: true) + '\n')!
	mut pins := map[string]string{}
	inventory(state, '', mut pins)!
	os.write_file(state + '/sha256.json', json2.encode(pins, prettify: true) + '\n')!
	println('PIDFDWAIT-BUILD-PASS root=' + state + ' manifest_sha256=' + hash(state + '/sha256.json')!)
}

build() or {
	eprintln(err)
	exit(1)
}
