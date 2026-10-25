// SPDX-License-Identifier: GPL-2.0-or-later
// Build the host-only system package check from its private consumed V closure.
module main

import crypto.sha256
import json2
import os
import time

const self = 'tests/native-android-ws/system-package-check-build.v'
const checker_source = 'tests/native-android-ws/system-package-check.v'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const frozen_seal = 'e397ed67a4b2ab748b5a72edd7ce4cea739cace133118df4efde2d915bcb528f'
const vroot = '/Users/alex/code/v'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn original_vlib(path string) bool {
	return path.starts_with(vroot + '/vlib/')
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn clone_file(from string, to string) ! {
	if os.exists(to) || os.is_link(to) { return error('clone destination exists: ' + to) }
	os.mkdir_all(os.dir(to))!
	r := os.exec(['/bin/cp', '-c', os.real_path(from), to])
	if r.exit_code != 0 { return error('APFS clone failed: ' + r.output) }
	if hash(from)! != hash(to)! { return error('clone mismatch: ' + from) }
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('nonregular evidence entry: ' + key) }
		}
	}
}

fn command(out string, label string, argv []string) !string {
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(out + '/commands/' + label + '.log', r.output)!
	write_json(out + '/commands/' + label + '.json', {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'VROOT': json2.Any(os.getenv('VROOT'))
		'VEXE': json2.Any(os.getenv('VEXE'))
		'VMODULES': json2.Any(os.getenv('VMODULES'))
		'VTMP': json2.Any(os.getenv('VTMP'))
		'command_binary_sha256': json2.Any(hash(os.real_path(argv[0]))!)
		'exit_code': json2.Any(r.exit_code)
	})!
	if r.exit_code != 0 { return error(label + ' failed:\n' + r.output) }
	return r.output
}

fn closure(out string, label string, compiler string, paths string, source string, extra []string) !map[string]string {
	mut argv := [compiler, '-print-v-files', '-enable-globals', '-path', paths]
	argv << extra
	argv << source
	listing := command(out, label, argv)!
	mut pins := map[string]string{}
	for line in listing.split_into_lines() {
		path := line.trim_space()
		if path.ends_with('.v') {
			if !path.starts_with('/') { return error('nonabsolute consumed source: ' + path) }
			if path in pins { return error('duplicate consumed source: ' + path) }
			pins[path] = hash(path)!
		}
	}
	if pins.len == 0 { return error('empty consumed source closure') }
	write_json(out + '/' + label + '-sha256.json', pins)!
	return pins
}

fn same(before map[string]string, after map[string]string) ! {
	if before.len != after.len { return error('consumed source set changed') }
	for path, pin in before {
		if after[path] or { '' } != pin { return error('consumed source changed: ' + path) }
	}
}

// Preserve the C inputs beside imported modules and the default GC archive.
fn native_inputs(snapshots map[string]string, out string) !map[string]string {
	mut pins := map[string]string{}
	mut retained_paths := map[string]string{}
	mut directories := map[string]string{}
	for origin, destination in snapshots { directories[os.dir(origin)] = os.dir(destination) }
	for directory, destination in directories {
		for name in os.ls(directory)! {
			if !name.ends_with('.h') && !name.ends_with('.c') { continue }
			path := directory + '/' + name
			if !os.is_file(path) { continue }
			retained := destination + '/' + name
			if retained == path { continue }
			pins[path] = hash(path)!
			clone_file(path, retained)!
			retained_paths[path] = retained
		}
	}
	for directory in [vroot + '/thirdparty/libgc/include', vroot + '/thirdparty/stdatomic/nix'] {
		for path in os.walk_ext(directory, '.h') {
			pins[path] = hash(path)!
			retained := out + '/native-inputs/' + path.trim_left('/')
			clone_file(path, retained)!
			retained_paths[path] = retained
		}
	}
	for path in [vroot + '/thirdparty/tcc/lib/libgc.a'] {
		pins[path] = hash(path)!
		retained := out + '/native-inputs/' + path.trim_left('/')
		clone_file(path, retained)!
		retained_paths[path] = retained
	}
	// The SDK compiler is a system-volume input; retain its identity and hash.
	c_compiler := os.real_path('/usr/bin/cc')
	pins[c_compiler] = hash(c_compiler)!
	retained_paths[c_compiler] = c_compiler
	write_json(out + '/native-inputs-before.json', pins)!
	write_json(out + '/native-input-snapshots.json', retained_paths)!
	return pins
}

// Embedded text is not listed by -print-v-files and may be loaded at runtime.
fn embedded_inputs(snapshots map[string]string, out string) !map[string]string {
	mut pins := map[string]string{}
	mut retained_paths := map[string]string{}
	for origin, destination in snapshots {
		code := os.read_file(origin)!.split_into_lines().filter(!it.trim_space().starts_with('//')).join('\n')
		for tail in code.split('$embed_file(')[1..] {
			literal := tail.trim_space()
			if literal.len == 0 || literal[0] !in [u8(39), u8(34)] {
				return error('nonliteral embed input: ' + origin)
			}
			quote := literal[..1]
			end := literal[1..].index(quote) or { return error('unterminated embed input') }
			relative := literal[1..end + 1]
			if relative.starts_with('/') || relative.contains('\\') { return error('unsupported embed path') }
			path := os.norm_path(os.dir(origin) + '/' + relative)
			retained := os.norm_path(os.dir(destination) + '/' + relative)
			if !retained.starts_with(out + '/') { return error('embed snapshot escaped output') }
			if path in pins { continue }
			pins[path] = hash(path)!
			clone_file(path, retained)!
			retained_paths[path] = retained
		}
	}
	write_json(out + '/embedded-inputs-before.json', pins)!
	write_json(out + '/embedded-input-snapshots.json', retained_paths)!
	return pins
}

fn build() ! {
	if os.args.len != 6 {
		return error('usage: system-package-check-build FROZEN329_ROOT BASELINE325 JAVA FRESH_BUILD_OUT FRESH_CHECK_OUT')
	}
	frozen := os.real_path(os.args[1])
	baseline := os.real_path(os.args[2])
	java := os.real_path(os.args[3])
	out := os.abs_path(os.args[4])
	check_out := os.abs_path(os.args[5])
	repo := os.real_path('.')
	for target in [out, check_out] {
		if os.exists(target) || os.is_link(target) { return error('fresh output required: ' + target) }
		for root in [repo, frozen, baseline] {
			if target == root || target.starts_with(root + '/') { return error('external output required') }
		}
	}
	if out == check_out || out.starts_with(check_out + '/') || check_out.starts_with(out + '/') {
		return error('build and check outputs must be independent sibling roots')
	}
	started := time.utc().str()
	compiler_origin := frozen + '/tools/v_old276'
	if hash(compiler_origin)! != compiler_pin { return error('compiler pin mismatch') }
	if hash(frozen + '/framework/sources.json')! != frozen_seal { return error('frozen source seal mismatch') }
	frozen_sources := json2.decode[map[string]string](os.read_file(frozen + '/framework/sources.json')!)!
	os.mkdir_all(out + '/commands')!
	os.mkdir_all(out + '/tmp')!
	os.mkdir_all(out + '/vmodules')!
	clone_file(os.executable(), out + '/build-runner')!
	clone_file(repo + '/' + self, out + '/build-runner.v')!
	clone_file(frozen + '/framework/sources.json', out + '/frozen-sources.json')!
	clone_file(compiler_origin, out + '/vroot/v')!
	clone_file(vroot + '/v.mod', out + '/vroot/v.mod')!
	source := out + '/sources/' + checker_source
	clone_file(repo + '/' + checker_source, source)!
	for relative, pin in frozen_sources {
		from := frozen + '/framework/sources/' + relative
		if hash(from)! != pin { return error('changed frozen source: ' + relative) }
		clone_file(from, out + '/sources/tests/native-android-tools/' + relative)!
	}
	module_root := out + '/sources/tests/native-android-tools'
	origin_paths := module_root + '|tests/host-policy|tests/linuxkpi|tests/native-generators|tests/native-guest-tools|build-support|tools|@vlib|@vmodules'
	os.setenv('VROOT', vroot, true)
	os.setenv('VEXE', compiler_origin, true)
	os.setenv('VTMP', out + '/tmp', true)
	origins := closure(out, 'discovery', compiler_origin, origin_paths, source, []string{})!
	mut paths := [module_root]
	mut mapped := map[string]string{}
	mut snapshots := map[string]string{}
	mut baked_builtin_count := 0
	for origin, pin in origins {
		mut destination := origin
		if origin.starts_with(vroot + '/vlib/') {
			destination = out + '/vroot/' + origin.all_after(vroot + '/')
		} else if !origin.starts_with(out + '/') {
			destination = out + '/closure/' + origin.trim_left('/')
		}
		if destination != origin { clone_file(origin, destination)! }
		if hash(destination)! != pin { return error('consumed snapshot mismatch: ' + origin) }
		snapshots[origin] = destination
		// Use the validated framework compiler's standard V library layout.
		// Every consumed origin retains an identical clone and is checked
		// before and after compilation; production sources remain private.
		if original_vlib(origin) {
			mapped[origin] = pin
			baked_builtin_count++
		} else {
			mapped[destination] = pin
		}
		if !destination.starts_with(out + '/vroot/vlib/') {
			module_parent := os.dir(os.dir(destination))
			if module_parent !in paths { paths << module_parent }
		}
	}
	write_json(out + '/origin-snapshots.json', snapshots)!
	native_before := native_inputs(snapshots, out)!
	embedded_before := embedded_inputs(snapshots, out)!
	paths << vroot + '/vlib'
	private_paths := paths.join('|')
	compiler := compiler_origin
	os.setenv('VROOT', vroot, true)
	os.setenv('VEXE', compiler, true)
	os.setenv('V', compiler, true)
	os.setenv('VINIX_V_COMPILER', compiler, true)
	os.setenv('VMODULES', out + '/vmodules', true)
	extra := []string{}
	before := closure(out, 'consumed-before', compiler, private_paths, source, extra)!
	same(mapped, before)!
	for path, _ in before {
		if !path.starts_with(out + '/') && !original_vlib(path) {
			return error('source escaped private snapshot: ' + path)
		}
	}
	checker := out + '/system-package-check'
	mut compile_argv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', 'cc',
		'-enable-globals', '-cflags', '-O2', '-path', private_paths, '-o', checker]
	compile_argv << extra
	compile_argv << source
	command(out, 'compile-checker', compile_argv)!
	mut native_after := map[string]string{}
	native_snapshots := json2.decode[map[string]string](os.read_file(out + '/native-input-snapshots.json')!)!
	for path, pin in native_before {
		native_after[path] = hash(path)!
		if hash(native_snapshots[path]!)! != pin { return error('retained C input changed: ' + path) }
	}
	same(native_before, native_after)!
	write_json(out + '/native-inputs-after.json', native_after)!
	after := closure(out, 'consumed-after', compiler, private_paths, source, extra)!
	same(before, after)!
	for origin, pin in origins {
		if hash(origin)! != pin { return error('discovery input changed: ' + origin) }
		if hash(snapshots[origin]!)! != pin { return error('retained source snapshot changed: ' + origin) }
	}
	if hash(compiler)! != compiler_pin || hash(compiler_origin)! != compiler_pin {
		return error('compiler changed during compilation')
	}
	mut generated := map[string]string{}
	inventory(out + '/tmp', '', mut generated)!
	if !generated.keys().any(it.ends_with('.c')) { return error('generated C was not retained') }
	command(out, 'run-checker', [checker, baseline, java, check_out, out + '/sources'])!
	mut embedded_after := map[string]string{}
	embedded_snapshots := json2.decode[map[string]string](os.read_file(out + '/embedded-input-snapshots.json')!)!
	for path, pin in embedded_before {
		embedded_after[path] = hash(path)!
		if hash(embedded_snapshots[path]!)! != pin { return error('retained embed input changed: ' + path) }
	}
	same(embedded_before, embedded_after)!
	write_json(out + '/embedded-inputs-after.json', embedded_after)!
	write_json(out + '/result.json', {
		'scope': json2.Any('HOST source transformation/DEX check only; no guest run, crypto or dialog qualification')
		'argv': json2.Any(os.args)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'frozen_sources_manifest_sha256': json2.Any(frozen_seal)
		'compiler_sha256': json2.Any(compiler_pin)
		'consumed_v_files': json2.Any(before.len)
		'all_consumed_v_sources_private': json2.Any(false)
		'original_vlib_files': json2.Any(baked_builtin_count)
		'original_vlib_exception': json2.Any('Validated compiler uses its original VROOT/vlib with default GC; complete consumed origin hashes are identical before/after compilation and have identical retained snapshots. All production, checker and imported repository V sources are private.')
		'consumed_closure_identical_before_after': json2.Any(true)
		'native_inputs_identical_before_after': json2.Any(true)
		'embedded_inputs': json2.Any(embedded_before.len)
		'embedded_inputs_identical_before_compile_after_run': json2.Any(true)
		'native_inputs_scope': json2.Any('Adjacent module headers/C helpers, GC headers/archive, stdatomic headers and C compiler; system SDK/dynamic libraries remain environment inputs.')
		'checker_sha256': json2.Any(hash(checker)!)
		'check_manifest_sha256': json2.Any(hash(check_out + '/sha256.json')!)
		'copy_method': json2.Any('/bin/cp -c APFS file clones; every clone hash checked')
		'exit_code': json2.Any(0)
	})!
	mut pins := map[string]string{}
	inventory(out, '', mut pins)!
	write_json(out + '/sha256.json', pins)!
	println('SYSTEM-PACKAGE-HOST-BUILD-PASS consumed=${before.len} manifest=${hash(out + '/sha256.json')!}')
}

fn main() {
	$if prod { eprintln('requires assertions; compile without -prod'); exit(2) }
	build() or { eprintln(err); exit(1) }
}
