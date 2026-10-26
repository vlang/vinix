// SPDX-License-Identifier: GPL-2.0-or-later
// Production-safe controls for guest-rooted compiler input capture.
module main

import crypto.sha256
import hwhost
import json2
import os
import tests.packages.audioinputs

#include <sys/stat.h>
fn C.mkfifo(&char, u32) int

struct Report {
	format int = 1
	result string = 'PASS'
	checker string
	helper string
	controls []string
	adapter_inputs map[string]string
	actual_links map[string]string
}

fn file(root string, name string, contents string) ! {
	os.mkdir_all(os.dir(root + '/' + name))!
	os.write_file(root + '/' + name, contents)!
}

fn link(root string, name string, target string) ! {
	os.mkdir_all(os.dir(root + '/' + name))!
	os.symlink(target, root + '/' + name)!
}

fn expect(root string, files map[string]string, links map[string]string) ! {
	snapshot := audioinputs.snapshot(root)!
	mut expected := map[string]string{}
	for name, target in files { expected[name] = root + '/' + target }
	if snapshot.root != root || snapshot.files != expected || snapshot.links != links {
		return error('captured sysroot files or literal links differ: ' + root)
	}
}

fn refuse(root string, reason string) ! {
	audioinputs.snapshot(root) or {
		if reason != '' && !err.msg().contains(reason) { return error('unexpected sysroot refusal: ' + err.msg()) }
		return
	}
	return error('accepted invalid sysroot: ' + root)
}

fn trace_controls(out string, mut controls []string) ! {
	sysroot := out + '/inputs/cross-sysroot'
	gcc := out + '/inputs/cross-gcc'
	mut trace := '#include <...> search starts here:\n ' + gcc + '/include\n ' + gcc + '/include-fixed\n ' + sysroot + '/include\nEnd of search list.\n. ' + sysroot + '/include/stdint.h\n'
	file(sysroot, 'include/stdint.h', 'SYNTHETIC TRACE HEADER\n')!
	for name in ['crt1.o', 'crti.o', 'crtn.o', 'libc.a'] { file(sysroot, 'lib/' + name, 'SYNTHETIC TRACE INPUT\n')!; trace += sysroot + '/lib/' + name + '\n' }
	for name in ['crtbeginT.o', 'crtend.o', 'libgcc.a', 'libgcc_eh.a'] { file(gcc, name, 'SYNTHETIC TRACE INPUT\n')!; trace += gcc + '/' + name + '\n' }
	file(out, 'cross-probe.o', 'SYNTHETIC GENERATED OBJECT\n')!
	file(out, 'cross-probe.c', 'SYNTHETIC GENERATED SOURCE\n')!
	trace += out + '/cross-probe.o\n'
	audioinputs.verify_trace(trace, out, 'cross-search.log', {})!
	controls << 'selected-captured-header-and-target-inputs'
	audioinputs.verify_trace(trace + 'Multiple include guards may be useful for:\n' + sysroot + '/include/stdint.h\n', out, 'cross-search.log', {})!
	controls << 'captured-header-guard-diagnostic'
	audioinputs.verify_trace(trace + out + '/cross-probe.c: In function \'main\':\n' + out + '/cross-probe.c:1:2: warning: retained diagnostic\n' + out + '/cross-probe.c:1:2: note: retained context\n', out, 'cross-search.log', {})!
	controls << 'exact-generated-source-diagnostics'
	for name in ['libm.a', 'libpthread.a'] {
		if name == 'libpthread.a' { link(sysroot, 'lib/' + name, 'libc.a')! }
		mut refused := false
		audioinputs.verify_trace(trace + sysroot + '/lib/' + name + '\n', out, 'cross-search.log', {}) or { refused = true }
		if !refused { return error('accepted missing or nonregular optional captured target input: ' + name) }
		controls << if name == 'libm.a' { 'missing-optional-target-input-refused' } else { 'symlink-optional-target-input-refused' }
	}
	for name, text in {
		'original-header': trace.replace('. ' + sysroot + '/include/stdint.h', '. /original/include/stdint.h')
		'original-startup': trace.replace(sysroot + '/lib/crt1.o', '/original/lib/crt1.o')
		'missing-libc': trace.replace(sysroot + '/lib/libc.a\n', '')
		'original-search': trace.replace(' ' + sysroot + '/include\n', ' /original/include\n')
		'no-header': trace.replace('. ' + sysroot + '/include/stdint.h\n', '')
		'original-guard-advice': trace + 'Multiple include guards may be useful for:\n/original/include/stdint.h\n'
		'foreign-cc-object': trace + '/original/ccforeign.o\n'
		'relative-object': trace + 'uncaptured.o\n'
		'relative-archive-with-spaces': trace + 'uncaptured library.a\n'
		'nul': trace + '\x00'
		'missing-generated-object': trace.replace(out + '/cross-probe.o\n', '')
		'foreign-source-warning': trace + '/original/foreign.c:1:2: warning: foreign\n'
		'generated-source-error': trace + out + '/cross-probe.c:1:2: error: refused\n'
		'malformed-generated-diagnostic': trace + out + '/cross-probe.c:invalid: warning: refused\n'
	} {
		mut refused := false
		audioinputs.verify_trace(text, out, 'cross-search.log', {}) or { refused = true }
		if !refused { return error('accepted invalid selected compiler input: ' + name) }
		controls << name + '-trace-refused'
	}
}

fn adapter_control(out string, adapter string, backend string) !map[string]string {
	if adapter == '' && backend == '' { return {} }
	if !os.is_abs_path(adapter) || !os.is_executable(adapter) || !os.is_abs_path(backend) || !os.is_executable(backend) { return error('requires absolute executable adapter and backend') }
	mut query := os.new_process(backend)
	query.set_args(['-print-file-name=libc.a'])
	query.set_redirect_stdio()
	query.run()
	original := query.stdout_slurp().trim_space()
	query.wait()
	code := query.code
	query.close()
	if code != 0 || !os.is_abs_path(original) || !os.is_file(original) { return error('original backend libc is unavailable') }
	sysroot := out + '/missing-captured-libc/inputs/cross-sysroot'
	gcc := out + '/missing-captured-libc/inputs/cross-gcc'
	for directory in [sysroot + '/include', gcc + '/include', gcc + '/include-fixed'] { os.mkdir_all(directory)! }
	for name in ['crt1.o', 'crti.o', 'crtn.o', 'libm.a', 'libpthread.a'] { file(sysroot, 'lib/' + name, '')! }
	for name in ['crtbeginT.o', 'crtend.o', 'libgcc.a', 'libgcc_eh.a'] { file(gcc, name, '')! }
	os.setenv('VINIX_AUDIO_BACKEND_CC', backend, true)
	os.setenv('VINIX_AUDIO_FROZEN_SYSROOT', sysroot, true)
	os.setenv('VINIX_AUDIO_FROZEN_GCC', gcc, true)
	mut child := os.new_process(adapter)
	child.set_args(['-static'])
	child.set_redirect_stdio()
	child.run()
	output := child.stdout_slurp() + child.stderr_slurp()
	child.wait()
	status := child.code
	child.close()
	os.write_file(out + '/missing-captured-libc.log', output)!
	if status != 2 || !output.contains('audio-cross-cc: missing captured target input: ' + sysroot + '/lib/libc.a') { return error('adapter failed to refuse missing captured libc before backend fallback') }
	return {'adapter': sha256.sum(os.read_bytes(adapter)!).hex(), 'backend': sha256.sum(os.read_bytes(backend)!).hex(), 'original-libc': sha256.sum(os.read_bytes(original)!).hex()}
}

fn checksums(paths map[string]string) !map[string]string {
	mut sums := map[string]string{}
	for name, path in paths {
		if (os.lstat(path)!).mode & 0o170000 != 0o100000 { return error('nonregular actual-link input: ' + path) }
		sums[name] = sha256.sum(os.read_bytes(path)!).hex()
	}
	return sums
}

// The diagnostic copies only directory entries: target bytes are hardlinked
// from a prior preserved capture. Its C is generated from current V sources.
fn actual_links(out string, captured string, adapter_path string, backend_path string, compiler_path string) !map[string]string {
	if captured == '' { return {} }
	if !os.is_abs_path(captured) || !os.is_abs_path(compiler_path) || !os.is_executable(compiler_path)
		|| !os.is_abs_path(adapter_path) || !os.is_executable(adapter_path) || !os.is_abs_path(backend_path) || !os.is_executable(backend_path) { return error('actual links require absolute captured inputs, V, adapter and backend') }
	compiler := os.real_path(compiler_path)
	adapter := os.real_path(adapter_path)
	backend := os.real_path(backend_path)
	root := os.real_path(os.dir(os.dir(os.dir(@FILE))))
	work := out + '/actual-links'
	mut paths := map[string]string{}
	for prefix in ['cross-sysroot', 'cross-gcc'] {
		tree := audioinputs.snapshot(captured + '/inputs/' + prefix)!
		if tree.links.len != 0 { return error('actual links require a materialized regular capture') }
		for name, source in tree.files {
			path := work + '/inputs/' + prefix + '/' + name
			os.mkdir_all(os.dir(path))!
			os.link(source, path)!
			paths[prefix + '/' + name] = path
		}
	}
	mut origins := map[string]string{}
	for prefix, original in {'vlib': 'vlib', 'v-thirdparty/stdatomic': 'thirdparty/stdatomic'} {
		tree := audioinputs.snapshot(captured + '/inputs/' + prefix)!
		if tree.links.len != 0 { return error('actual links require materialized V inputs') }
		for name, retained in tree.files {
			path := os.real_path(os.dir(compiler) + '/' + original + '/' + name)
			if (os.lstat(path)!).mode & 0o170000 != 0o100000
				|| sha256.sum(os.read_bytes(path)!).hex() != sha256.sum(os.read_bytes(retained)!).hex() { return error('original V input differs from preserved capture: ' + path) }
			key := prefix + '/' + name
			origins[key] = path
			paths['original/' + key] = path
			paths['captured/' + key] = retained
		}
	}
	os.write_file(work + '/original-v-paths.json', json2.encode(origins) + '\n')!
	for tree in ['tools/packages/audiopcm', 'tools/packages/appsdk', 'tests/packages/audio-portal-tone'] {
		for name, path in (audioinputs.snapshot(root + '/' + tree)!).files { paths['source/' + tree + '/' + name] = path }
	}
	for name in ['tests/packages/audio-cross-probe.v', 'tests/packages/audio-cross-cc.v', 'tests/packages/audio-input-check.v', 'tests/packages/audioinputs/tree.v'] { paths['source/' + name] = root + '/' + name }
	paths['tool/v'] = compiler
	paths['tool/adapter'] = adapter
	paths['tool/backend'] = backend
	for name in ['cc1', 'collect2', 'as', 'ld', 'lto-wrapper'] {
		hwhost.run_tool([backend, '-print-prog-name=' + name], {}, work + '/tool-' + name + '.log', 300)!
		value := os.read_file(work + '/tool-' + name + '.log')!.trim_space()
		paths['tool/' + name] = if value.contains('/') { os.real_path(value) } else { os.find_abs_path_of_executable(value)! }
	}
	hwhost.run_tool([backend, '-print-prog-name=liblto_plugin.so'], {}, work + '/tool-lto-plugin.log', 300)!
	plugin := os.read_file(work + '/tool-lto-plugin.log')!.trim_space()
	if !os.is_abs_path(plugin) { return error('GCC LTO plugin must have an absolute executable-tool path') }
	paths['tool/lto-plugin'] = os.real_path(plugin)
	before := checksums(paths)!
	os.write_file(work + '/input-before.json', json2.encode(before) + '\n')!
	os.write_file(work + '/input-paths.json', json2.encode(paths) + '\n')!
	os.setenv('VINIX_AUDIO_BACKEND_CC', backend, true)
	os.setenv('VINIX_AUDIO_FROZEN_SYSROOT', work + '/inputs/cross-sysroot', true)
	os.setenv('VINIX_AUDIO_FROZEN_GCC', work + '/inputs/cross-gcc', true)
	mut outputs := map[string]string{}
	mut commands := map[string][]string{}
	for name, source in {'cross-probe': 'tests/packages/audio-cross-probe.v', 'tone-build/tone': 'tests/packages/audio-portal-tone'} {
		os.mkdir_all(os.dir(work + '/' + name))!
		generated := work + '/' + name + '.c'
		generate := [compiler, '-os', 'linux', '-arch', 'arm64', '-gc', 'none', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-prod', '-path', '@vlib|@vmodules|' + root, '-o', generated, root + '/' + source]
		commands[name + '/generate'] = generate
		os.write_file(work + '/commands.json', json2.encode(commands) + '\n')!
		hwhost.run_tool(generate, {}, work + '/' + name + '-generate.log', 300)!
		trace := if name == 'cross-probe' { 'cross-search.log' } else { 'tone-build/build.log' }
		compile := [adapter, '-static', '-O1', '-D_GNU_SOURCE', '-fno-stack-protector', generated, '-o', work + '/' + name, '-lm', '-lpthread']
		commands[name + '/link'] = compile
		os.write_file(work + '/commands.json', json2.encode(commands) + '\n')!
		hwhost.run_tool(compile, {}, work + '/' + trace, 300)!
		binary := os.read_bytes(work + '/' + name)!
		if binary.len < 64 || binary[0] != 127 || binary[1] != `E` || binary[2] != `L` || binary[3] != `F`
			|| binary[4] != 2 || binary[5] != 1 || binary[16] != 2 || binary[17] != 0 || binary[18] != 183 || binary[19] != 0 { return error('actual link is not an AArch64 ELF executable: ' + name) }
		audioinputs.verify_trace(os.read_file(work + '/' + trace)!, work, trace, audioinputs.header_allowlist(root, {}, origins))!
	}
	after := checksums(paths)!
	os.write_file(work + '/input-after.json', json2.encode(after) + '\n')!
	if before != after { return error('actual-link inputs changed') }
	for name, path in (audioinputs.snapshot(work)!).files {
		if !name.starts_with('inputs/') { outputs[name] = sha256.sum(os.read_bytes(path)!).hex() }
	}
	os.write_file(work + '/outputs.json', json2.encode(outputs) + '\n')!
	return {'inputs': sha256.sum(json2.encode(before).bytes()).hex(), 'outputs': sha256.sum(json2.encode(outputs).bytes()).hex(), 'architecture': 'aarch64'}
}

fn run(out string, adapter string, backend string, captured string, compiler string) ! {
	$if prod {} $else { return error('compile audio input checker with -prod') }
	if os.exists(out) || os.is_link(out) { return error('requires new control output') }
	os.mkdir_all(out)!
	mut controls := []string{}
	mut root := out + '/empty'
	os.mkdir_all(root)!
	expect(root, {}, {})!
	controls << 'empty-root'
	root = out + '/regular'
	file(root, 'include/header.h', 'regular header\n')!
	expect(root, {'include/header.h': 'include/header.h'}, {})!
	controls << 'nested-regular-input'
	for absolute in [false, true] {
		root = out + if absolute { '/absolute' } else { '/relative' }
		file(root, 'lib/libc.so', 'guest libc\n')!
		target := if absolute { '/lib/libc.so' } else { '../lib/libc.so' }
		link(root, 'lib64/loader', target)!
		expect(root, {'lib/libc.so': 'lib/libc.so', 'lib64/loader': 'lib/libc.so'}, {'lib64/loader': target})!
		controls << if absolute { 'absolute-link-rooted-in-guest' } else { 'relative-parent-link-rooted-in-guest' }
	}
	root = out + '/chain'
	file(root, 'lib/libc.so', 'guest libc\n')!
	link(root, 'first', 'second')!
	link(root, 'second', '/lib/libc.so')!
	expect(root, {'lib/libc.so': 'lib/libc.so', 'first': 'lib/libc.so', 'second': 'lib/libc.so'},
		{'first': 'second', 'second': '/lib/libc.so'})!
	controls << 'mixed-absolute-relative-link-chain'
	root = out + '/component-parent'
	file(root, 'leaf', 'wrong lexical target\n')!
	file(root, 'real/leaf', 'correct resolved target\n')!
	os.mkdir_all(root + '/real/sub')!
	link(root, 'alias', '/real/sub')!
	link(root, 'entry', 'alias/../leaf')!
	expect(root, {'leaf': 'leaf', 'real/leaf': 'real/leaf', 'entry': 'real/leaf'},
		{'alias': '/real/sub', 'entry': 'alias/../leaf'})!
	controls << 'directory-link-resolved-before-parent-component'
	root = out + '/directory-alias'
	file(root, 'real/header.h', 'aliased header\n')!
	link(root, 'include', '/real')!
	expect(root, {'real/header.h': 'real/header.h', 'include/header.h': 'real/header.h'}, {'include': '/real'})!
	controls << 'directory-alias-materializes-logical-files'
	root = out + '/literal-mutation'
	file(root, 'lib/libc.so', 'unchanged bytes\n')!
	link(root, 'loader', '/lib/libc.so')!
	before := audioinputs.snapshot(root)!
	os.rm(root + '/loader')!
	link(root, 'loader', 'lib/libc.so')!
	after := audioinputs.snapshot(root)!
	if before.files != after.files || before.links == after.links { return error('literal mutation was not independently observable') }
	controls << 'literal-link-mutation-with-identical-files-detected'
	for name, target in {'escape': '../outside', 'absolute-escape': '/../outside', 'missing': '/lib/missing'} {
		root = out + '/' + name
		link(root, 'bad', target)!
		refuse(root, if name.contains('escape') { 'escapes its root' } else { '' })!
		controls << name + '-refused'
	}
	root = out + '/link-cycle'
	link(root, 'a', 'b')!
	link(root, 'b', 'a')!
	refuse(root, 'cyclic')!
	controls << 'file-link-cycle-refused'
	root = out + '/directory-cycle'
	file(root, 'dir/file', 'cycle fixture\n')!
	link(root, 'dir/up', '/')!
	refuse(root, 'cyclic sysroot directory')!
	controls << 'directory-cycle-refused'
	root = out + '/nondirectory-component'
	file(root, 'regular', 'not a directory\n')!
	link(root, 'bad', 'regular/../regular')!
	refuse(root, 'nonregular sysroot input')!
	controls << 'regular-file-before-parent-component-refused'
	root = out + '/special'
	os.mkdir_all(root)!
	path := root + '/fifo'
	if C.mkfifo(path.str, 0o600) != 0 { return error('cannot create FIFO control') }
	refuse(root, 'nonregular sysroot input')!
	controls << 'special-file-refused-without-opening'
	refuse(out + '/does-not-exist', '')!
	controls << 'missing-root-refused'
	trace_controls(out, mut controls)!
	adapter_inputs := adapter_control(out, adapter, backend)!
	if adapter_inputs.len != 0 { controls << 'missing-captured-libc-refused-with-original-present' }
	links := actual_links(out, captured, adapter, backend, compiler)!
	if links.len != 0 { controls << 'actual-frozen-probe-link'; controls << 'actual-frozen-current-tone-link' }
	os.write_file(out + '/result.json', json2.encode(Report{
		checker: sha256.sum(os.read_bytes(@FILE)!).hex()
		helper: sha256.sum($embed_file('audioinputs/tree.v').to_string().bytes()).hex()
		controls: controls
		adapter_inputs: adapter_inputs
		actual_links: links
	}) + '\n')!
	println('AUDIO INPUT CAPTURE PASS controls=' + controls.len.str())
}

fn main() {
	mut values := map[string]string{}
	for argument in os.args[1..] {
		key := argument.all_before('=')
		if key !in ['--out', '--adapter', '--backend', '--link-inputs', '--v'] || !argument.contains('=') || key in values { eprintln('use --out=NEW_DIRECTORY [--adapter=ABS --backend=ABS] [--link-inputs=ABS --v=ABS]'); exit(1) }
		values[key] = argument.all_after('=')
	}
	if values['--out'] == '' { eprintln('requires --out=NEW_DIRECTORY'); exit(1) }
	if (values['--link-inputs'] == '') != (values['--v'] == '') { eprintln('actual links require both --link-inputs and --v'); exit(1) }
	run(os.abs_path(values['--out']), values['--adapter'], values['--backend'], values['--link-inputs'], values['--v']) or { eprintln(err); exit(1) }
}
